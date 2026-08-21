################################################################################
#  PLACEHOLDER hardware configuration for probook650 (HP ProBook 650 G2).
#
#  This file MUST be replaced with real output from the machine itself:
#
#      sudo nixos-generate-config --flake /home/ogryson/nixos-config
#      # then copy the generated hardware-configuration.nix over this file
#
#  The entries below only exist so `nix flake check` and a dry build evaluate
#  before the ProBook has been installed. They are NOT the real disk layout.
#  Like every hardware-configuration.nix, do not edit by hand except for
#  mount points or kernel parameters — regenerate instead.
################################################################################
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ahci" "sd_mod" "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Placeholder layout — mirrors the btrfs subvolume scheme used on dragonflyg4
  # (see ./configuration.nix snapper section). Replace wholesale with the
  # generated file after running nixos-generate-config on the ProBook.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  swapDevices = [ { device = "/dev/disk/by-label/SWAP"; } ];

  # Enables DHCP on each ethernet and wireless interface.
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
}
