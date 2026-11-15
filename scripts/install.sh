#!/usr/bin/env bash
# Full install of one host of this flake from the NixOS minimal ISO.
# Wipes DEVICE, lays out disko/laptop-luks.nix, installs, and puts the repo in
# ~/nixos-config on the new system. See docs/installation.md.
#
#   ./scripts/install.sh <host> <device> <swap-size>
#   ./scripts/install.sh probook650 /dev/sda 17G
set -euo pipefail

host=${1:?host, e.g. probook650}
device=${2:?device, e.g. /dev/sda or /dev/nvme0n1}
swap=${3:?swap size >= RAM, e.g. 17G}

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
export NIX_CONFIG="experimental-features = nix-command flakes"

case "$host" in
  dragonflyg4) hwfile=hardware-configuration.nix ;;
  *)           hwfile=hardware-$host.nix ;;
esac
[ -f "$hwfile" ] || { echo "no $hwfile: add the host to flake.nix first" >&2; exit 1; }

lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS "$device"
read -rp "ERASE everything on $device? Type YES: " ok
[ "$ok" = YES ] || exit 1

# Leftovers from an earlier attempt keep the disk busy and make disko fail.
sudo swapoff -a || true
sudo umount -R /mnt 2>/dev/null || true
for m in cryptroot cryptswap; do sudo cryptsetup close "$m" 2>/dev/null || true; done

(umask 077
 read -rsp "disk passphrase: " pw; echo
 read -rsp "again: " pw2; echo
 [ "$pw" = "$pw2" ] || { echo "passphrases differ" >&2; exit 1; }
 printf %s "$pw" > /tmp/disk.key)
trap 'rm -f /tmp/disk.key' EXIT

sudo -E nix run github:nix-community/disko -- \
  --mode destroy,format,mount ./disko/laptop-luks.nix \
  --argstr device "$device" --argstr swapSize "$swap"
rm -f /tmp/disk.key

sudo nixos-generate-config --root /mnt --show-hardware-config > "$hwfile"
git add -A                                   # flakes only read tracked files

sudo -E nixos-install --flake ".#$host" --no-root-passwd

sudo mkdir -p /mnt/home/ogryson
sudo cp -a "$repo" /mnt/home/ogryson/nixos-config
sudo git -C /mnt/home/ogryson/nixos-config remote set-url origin \
  git@github.com:olavgryson/NixOS_configs.git
sudo chown -R 1000:100 /mnt/home/ogryson     # ogryson:users

echo "Done. Reboot and remove the stick; first login password is 'changeme'."
