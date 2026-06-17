################################################################################
#  PLACEHOLDER — DO NOT TRUST THIS FILE AS-IS.
#
#  This file is MACHINE-SPECIFIC and must be GENERATED on the new NixOS install.
#  It contains disk UUIDs, kernel modules and filesystem layout that only the
#  installer can know. You were right that I cannot hand-write this correctly.
#
#  During install (see README.md, step 5) run:
#       nixos-generate-config --root /mnt
#  then COPY the generated /mnt/etc/nixos/hardware-configuration.nix OVER this
#  file. After that, Claude will diff it against inventory/40-lsmod.txt and
#  inventory/41-cpu.txt to sanity-check it.
#
#  The stub below only lets the flake evaluate for review BEFORE install.
#  It will NOT boot. Replace it.
################################################################################
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # --- everything below is a NON-FUNCTIONAL placeholder ---
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Replace these with the GENERATED fileSystems block (correct UUIDs + subvols).
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
