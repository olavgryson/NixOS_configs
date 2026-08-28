# Installing on a fresh machine

Full install of this flake on an empty disk, with root filesystem and swap
encrypted (LUKS2 + btrfs). Works on any x86_64 UEFI laptop; the disk layout is
declared once in `disko/laptop-luks.nix` and the only machine-specific file is
the generated `hardware-configuration.nix`.

---

## 0. Backup, on the machine being replaced

On an external disk, and **verified before anything is wiped**:

1. Home directory without the caches:

   ```bash
   rsync -aAXv --info=progress2 \
     --exclude='.cache' --exclude='.local/share/Trash' \
     --exclude='.npm' --exclude='.nvm' --exclude='.cargo' \
     /home/ogryson/  /run/media/EXT/home-backup/
   ```

2. The secrets that deliberately never enter this repo:
   - `~/.ssh/` — the keypair, restored after install.
   - `~/.gnupg/` and `~/.password-store/` — without both, `pass` decrypts nothing.
   - `/etc/NetworkManager/system-connections/` — WiFi credentials
     (`sudo cp -a`, restore to the same path, then `chown root:root` + `chmod 600`).
   - Browser profiles.

3. This repo itself: clone or copy it to the external disk, so the install does
   not depend on reaching a forge over the network.

4. Verify: restore one random file and open it, compare `du -sh` of source and
   destination. Only then wipe.

---

## 1. Boot the installer

1. Write the NixOS **minimal** ISO to a USB stick. No desktop needed — the
   desktop is built from this config.
2. Boot it in UEFI mode, secure boot off.
3. Network: `nmtui` (or `wpa_supplicant`), then confirm with `ping nixos.org`.
4. Get the repo onto the machine (external disk or `git clone`), and `cd` into
   it — the next step reads the layout from there.

---

## 2. Partition, encrypt, format

One command does the whole disk. Swap must be at least as large as RAM,
otherwise hibernation has nowhere to write its image:

```bash
lsblk                                    # confirm the target disk
(umask 077; read -rsp 'disk passphrase: ' pw; printf %s "$pw" > /tmp/disk.key)

sudo nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- \
  --mode destroy,format,mount ./disko/laptop-luks.nix \
  --argstr device /dev/nvme0n1 \
  --argstr swapSize 17G          # >= RAM: 16G RAM -> 17G

rm /tmp/disk.key                         # tmpfs, but do not leave it lying around
```

`--mode destroy,format,mount` wipes the disk, creates the layout and mounts it
under `/mnt`. Add `--dry-run` first to print the script without touching
anything. Arguments per machine: `device` (`/dev/nvme0n1` or `/dev/sda`) and
`swapSize`.

What it builds — see `disko/laptop-luks.nix` for the authoritative version:

| Partition | Size       | Contents                                              |
|-----------|------------|-------------------------------------------------------|
| ESP       | 1G         | vfat, `/boot`, plaintext (UEFI has to read it)         |
| swap      | `swapSize` | LUKS2 `cryptswap` → swap labelled `SWAP`               |
| root      | rest       | LUKS2 `cryptroot` → btrfs `NIXOS`, subvolumes `@`, `@home`, `@nix` (`compress=zstd,noatime`) |

Both containers get the same passphrase from the key file, so it is typed once
here and once per boot — see *One password instead of two* below to drop even
that second prompt.

Why an encrypted swap **partition** rather than a random-key swap or a btrfs
swapfile: a random key can only be unlocked after boot, which rules out resume
from hibernation, and a swapfile needs a `resume_offset` that shifts whenever
the file is recreated. A LUKS partition is unlocked in the initrd, before
resume, and keeps its label.

---

## 3. Generate the hardware configuration

```bash
sudo nixos-generate-config --root /mnt
```

This is the one file the repo cannot ship: real disk UUIDs, kernel modules,
`fileSystems`. Then check what it wrote for the encrypted devices:

```bash
grep -A2 'luks\|swapDevices' /mnt/etc/nixos/hardware-configuration.nix
```

It emits a `boot.initrd.luks.devices` entry for the container holding root. It
does **not** reliably emit one for swap — without that entry the machine boots
but never resumes from hibernation, and `swapDevices` points at a device that
does not exist yet. Add what is missing, using the UUID of the raw partition
(`blkid /dev/nvme0n1p2`), not of the mapper:

```nix
boot.initrd.luks.devices."cryptswap".device = "/dev/disk/by-uuid/<uuid-of-the-swap-partition>";
swapDevices = [ { device = "/dev/disk/by-label/SWAP"; } ];

# One prompt for both containers: systemd in the initrd caches the first
# passphrase and retries it on the remaining LUKS devices. Encrypted hosts
# only -- this cannot live in configuration.nix conditioned on
# `boot.initrd.luks.devices`, because the LUKS module reads this option back
# and the evaluation loops.
boot.initrd.systemd.enable = true;
```

These are the only hand-written additions to a generated hardware file;
everything else stays as `nixos-generate-config` wrote it.

---

## 4. Install

`flake.nix` defines one `nixosConfigurations.<host>` attribute per machine. A
new machine needs its own entry there, and its own hardware file, before this
works.

```bash
git clone /run/media/EXT/nixos-config /mnt/home/ogryson/nixos-config
cd /mnt/home/ogryson/nixos-config
cp /mnt/etc/nixos/hardware-configuration.nix ./hardware-configuration.nix
git add .                                  # flakes only read git-tracked files
sudo nixos-install --flake .#<host> --no-root-passwd
```

Reboot, remove the USB stick. The LUKS passphrase prompt appears before the
ReGreet login screen.

---

## 5. First boot

1. `passwd` — the config ships `initialPassword = "changeme"` and root is
   locked; administration goes through `sudo`.
2. Restore from backup: `~/.ssh/` (`chmod 600` the private key), `~/.gnupg/`,
   `~/.password-store/`, NetworkManager connections, browser profiles.
3. `rebuild` to confirm the machine can rebuild itself.

Keybinds to get going: `SUPER+Return` terminal, `SUPER+Space` launcher,
`SUPER+B` browser, `SUPER+L` lock. Full list in `home/shortcuts.nix`.

---

## One password instead of two

Out of the box an encrypted machine asks twice: the LUKS passphrase in the
initrd, then the login password in ReGreet. The root filesystem has to be
mounted before any login screen exists, so the disk cannot be unlocked *by* the
login. What can be done is to let the TPM unlock the disk, leaving only the
login password to type — the same trade Windows makes with BitLocker.

Check the machine has a TPM2 (older laptops may ship TPM 1.2, or have it off in
BIOS):

```bash
systemd-cryptenroll --tpm2-device=list
```

Enroll both containers, binding the key to firmware and secure-boot state:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p3
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2
```

Then tell the initrd to use it, in the host's hardware file, and `rebuild`:

```nix
boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "tpm2-device=auto" ];
boot.initrd.luks.devices."cryptswap".crypttabExtraOpts = [ "tpm2-device=auto" ];
```

**What this costs.** Automatic unlock means a stolen laptop boots straight to
the login screen: the disk no longer protects anything on its own, only the
user password does. Pulling the SSD out and reading it elsewhere still fails,
which is what encryption is mostly for. If that trade is unacceptable, enroll
with `--tpm2-with-pin=yes` instead — the disk then asks for a PIN, which is a
boot prompt again, just a shorter one.

**Keep the passphrase slot.** PCR 0+7 covers firmware and secure boot: a BIOS
update or a secure-boot change invalidates the enrollment and the machine falls
back to asking the passphrase. Re-enroll afterwards
(`systemd-cryptenroll --wipe-slot=tpm2 …` then enroll again).

**No usable TPM2?** The alternative single-password setup is to keep the boot
passphrase and enable autologin in `greeter.nix`, so unlocking the disk logs
straight in. That makes the disk passphrase the only secret — anyone who knows
it has the desktop, and the lock screen still asks the user password.

---

## Encryption notes

- **Existing installs are not converted.** LUKS cannot be added to a mounted
  filesystem in place; an unencrypted machine has to be backed up and
  reinstalled with this procedure.
- **Header backup.** A damaged LUKS header makes the disk unrecoverable even
  with the right passphrase. Keep one off-machine:
  `sudo cryptsetup luksHeaderBackup /dev/nvme0n1p3 --header-backup-file luks-root.img`
- **Second passphrase.** `sudo cryptsetup luksAddKey /dev/nvme0n1p3` adds a
  slot, so a forgotten primary passphrase is not a reinstall.
