################################################################################
#  Disk layout for a fresh install: encrypted swap + encrypted btrfs.
#
#  Used as a standalone disko config, not imported into the system — the disk
#  is formatted with it once, and `nixos-generate-config` then writes the real
#  fileSystems/luks entries into the host's hardware file, as everywhere else
#  in this repo. See docs/installation.md.
#
#      sudo nix run github:nix-community/disko -- \
#        --mode destroy,format,mount ./disko/laptop-luks.nix \
#        --argstr device /dev/nvme0n1 --argstr swapSize 17G
#
#  Both containers take the same passphrase from `passwordFile`, so the install
#  asks for it once and (with systemd in the initrd) so does every boot.
################################################################################
{
  device ? "/dev/nvme0n1",
  # >= RAM, or hibernation has nowhere to write its image.
  swapSize ? "17G",
  # Read into a tmpfs file at install time; never lands on disk.
  passwordFile ? "/tmp/disk.key",
  ...
}:

{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # 512M overflows after a handful of generations with a large initrd.
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        # A LUKS partition rather than a random-key device or a btrfs swapfile:
        # only this variant is unlocked in the initrd, before resume, and keeps
        # a stable label across recreation.
        swap = {
          size = swapSize;
          content = {
            type = "luks";
            name = "cryptswap";
            inherit passwordFile;
            settings.allowDiscards = true;
            content = {
              type = "swap";
              extraArgs = [ "--label" "SWAP" ];
              discardPolicy = "both";
              resumeDevice = true;
            };
          };
        };

        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            inherit passwordFile;
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-L" "NIXOS" "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
