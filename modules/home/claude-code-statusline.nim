import std/[json, options, strformat, strutils, times, math]

# ───────────────────────────── CONFIGURATION ─────────────────────────────
const
  segments = ["model", "effort", "context", "limits"] # display order; add, remove or reorder freely
  separator = " │ "
  useColors = true

  barWidth = 10 # 0 disables the bar, percentage only
  barFill = "█"
  barEmpty = "░"

  warnPct = 70
  critPct = 90

  contextLabel = "ctx"
  contextShowTokens = true # adds "(45k/200k)"

  limit5hLabel = "5h"
  limit7dLabel = "7j"
  limitsShowBar = false
  limitsShowReset = true # "↻2h13m" countdown to reset

  effortIcon = "⚡"
  effortHideLevels: seq[string] = @[] # e.g. @["medium"] to hide the default level
# ───────────────────────────────────────────────────────────────────────

const
  reset = if useColors: "\e[0m" else: ""
  dim = if useColors: "\e[2m" else: ""
  bold = if useColors: "\e[1m" else: ""
  red = if useColors: "\e[31m" else: ""
  green = if useColors: "\e[32m" else: ""
  yellow = if useColors: "\e[33m" else: ""
  blue = if useColors: "\e[34m" else: ""
  magenta = if useColors: "\e[35m" else: ""
  cyan = if useColors: "\e[36m" else: ""

proc optFloat(n: JsonNode): Option[float] =
  if n == nil: none(float) else: some(n.getFloat())

proc optInt(n: JsonNode): Option[int] =
  if n == nil: none(int) else: some(n.getInt())

proc roundOpt(o: Option[float]): Option[int] =
  if o.isNone: none(int) else: some(round(o.get()).int)

var data: JsonNode
try:
  data = parseJson(stdin.readAll())
except CatchableError:
  data = newJObject()

let model = block:
  let dn = data{"model", "display_name"}
  let id = data{"model", "id"}
  if dn != nil: dn.getStr("?")
  elif id != nil: id.getStr("?")
  else: "?"

let effort = block:
  let e = data{"effort", "level"}
  if e != nil: e.getStr("") else: ""

let ctxPct = roundOpt(optFloat(data{"context_window", "used_percentage"}))
let ctxTokens = optInt(data{"context_window", "total_input_tokens"})
let ctxSize = optInt(data{"context_window", "context_window_size"})
let l5Pct = roundOpt(optFloat(data{"rate_limits", "five_hour", "used_percentage"}))
let l5Reset = optInt(data{"rate_limits", "five_hour", "resets_at"})
let l7Pct = roundOpt(optFloat(data{"rate_limits", "seven_day", "used_percentage"}))
let l7Reset = optInt(data{"rate_limits", "seven_day", "resets_at"})
let nowS = epochTime().int

# ─────────────────────────────── HELPERS ────────────────────────────────
proc colorForPct(p: Option[int]): string =
  if p.isNone: return green
  let v = p.get()
  if v >= critPct: red
  elif v >= warnPct: yellow
  else: green

proc makeBar(p, w: int): string =
  if w <= 0: return ""
  var pp = p
  if pp > 100: pp = 100
  if pp < 0: pp = 0
  let filled = (pp * w) div 100
  let empty = w - filled
  barFill.repeat(filled) & barEmpty.repeat(empty)

proc humanTokens(n: Option[int]): string =
  if n.isNone: return ""
  let v = n.get()
  if v >= 1_000_000:
    let dec = (v mod 1_000_000) div 100_000
    if dec == 0: fmt"{v div 1_000_000}M" else: fmt"{v div 1_000_000}.{dec}M"
  elif v >= 1000:
    fmt"{v div 1000}k"
  else:
    fmt"{v}"

proc timeUntil(target: Option[int]): string =
  if target.isNone: return ""
  var diff = target.get() - nowS
  if diff < 0: diff = 0
  let d = diff div 86400
  let h = (diff mod 86400) div 3600
  let m = (diff mod 3600) div 60
  if d > 0: fmt"{d}j{h}h"
  elif h > 0: fmt"{h}h{m:02}m"
  else: fmt"{m}m"

# ─────────────────────────────── SEGMENTS ───────────────────────────────
# To add a segment: write a seg<Name> proc and add it to callSeg below.

proc segModel(): string =
  fmt"{bold}{cyan}{model}{reset}"

proc segEffort(): string =
  if effort == "": return "" # models without an effort knob leave this empty
  if effort in effortHideLevels: return ""
  let col = case effort
    of "low": dim
    of "medium": blue
    of "high": yellow
    of "xhigh", "max": magenta
    else: ""
  fmt"{col}{effortIcon}{effort}{reset}"

proc segContext(): string =
  if ctxPct.isNone:
    return fmt"{dim}{contextLabel} --{reset}" # before the first API response
  let p = ctxPct.get()
  let col = colorForPct(ctxPct)
  let bar = makeBar(p, barWidth)
  result = fmt"{contextLabel} "
  if bar != "": result &= fmt"{col}{bar}{reset} "
  result &= fmt"{col}{p}%{reset}"
  if contextShowTokens and ctxTokens.isSome and ctxSize.isSome:
    let ht = humanTokens(ctxTokens)
    let hs = humanTokens(ctxSize)
    result &= fmt" {dim}({ht}/{hs}){reset}"

proc limitPart(label: string, pct: Option[int], resetAt: Option[int]): string =
  if pct.isNone: return ""
  let p = pct.get()
  let col = colorForPct(pct)
  result = fmt"{label} "
  if limitsShowBar:
    result &= fmt"{col}{makeBar(p, barWidth)}{reset} "
  result &= fmt"{col}{p}%{reset}"
  if limitsShowReset and resetAt.isSome:
    result &= fmt" {dim}↻{timeUntil(resetAt)}{reset}"

proc segLimits(): string = # Pro/Max only, and only after the first API response
  let a = limitPart(limit5hLabel, l5Pct, l5Reset)
  let b = limitPart(limit7dLabel, l7Pct, l7Reset)
  if a != "" and b != "": fmt"{a}  {b}" else: a & b

proc callSeg(name: string): string =
  case name
  of "model": segModel()
  of "effort": segEffort()
  of "context": segContext()
  of "limits": segLimits()
  else: ""

# ──────────────────────────────── OUTPUT ────────────────────────────────
var parts: seq[string]
for seg in segments:
  let v = callSeg(seg)
  if v != "": parts.add(v)
echo parts.join(separator)
