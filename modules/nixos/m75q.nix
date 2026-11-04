# The Lenovo ThinkCentre M75q (Ryzen 5 5600GE, 15 GB), the hashira. Its disk: luks-nvme.
_: {
  flake.modules.nixos.m75q =
    { modulesPath, ... }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];
      hardware.cpu.amd.updateMicrocode = true;
      hardware.enableRedistributableFirmware = true;
    };
}
