# The Minisforum NAB6 Lite (i5-12600H, 32 GB, 1 TB NVMe, two Ethernet ports), naya. Its disk: luks-nvme.
_: {
  flake.modules.nixos.nab6 =
    { modulesPath, ... }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-intel" ];
      hardware.cpu.intel.updateMicrocode = true;
      hardware.enableRedistributableFirmware = true;
    };
}
