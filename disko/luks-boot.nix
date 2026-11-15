################################################################################
#  Boot-side counterpart of ./laptop-luks.nix, for every host installed with it.
#
#  nixos-generate-config emits the LUKS entry for the container holding root,
#  but not reliably the one for swap. Without it the machine boots yet never
#  resumes from hibernation. Everything here is keyed on names disko itself
#  assigns (partition label `disk-main-<partition>`, filesystem label `SWAP`),
#  so the generated hardware file can be dropped in unedited.
################################################################################
{ lib, ... }:

{
  boot.initrd.luks.devices.cryptswap = {
    # mkDefault: a by-UUID entry in the generated hardware file wins.
    device = lib.mkDefault "/dev/disk/by-partlabel/disk-main-swap";
    allowDiscards = true;
  };

  # One prompt for both containers: the systemd initrd caches the first
  # passphrase and retries it on the remaining LUKS devices.

  # Fallback only: the generated hardware file normally lists the swap itself
  # (by UUID), and a plain definition there replaces this default.
  swapDevices = lib.mkDefault [ { device = "/dev/disk/by-label/SWAP"; } ];

  # Hibernate into the encrypted swap; it is unlocked in the initrd, before
  # resume runs.
  boot.resumeDevice = "/dev/disk/by-label/SWAP";
}
