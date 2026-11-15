# Installing on a fresh machine

Full install of this flake on an empty disk, with root filesystem and swap
encrypted (LUKS2 + btrfs). Works on any x86_64 UEFI laptop; the disk layout is
declared once in `disko/laptop-luks.nix` and the only machine-specific file is
the generated `hardware-<host>.nix`.

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
2. Boot it in UEFI mode, secure boot off (HP: `F10` setup, `F9` boot menu).
3. Network: `nmtui`, then confirm with `ping -c2 nixos.org`.
4. Get the repo, on the branch that holds the host:

   ```bash
   nix-shell -p git
   git clone -b omarchy-port https://github.com/olavgryson/NixOS_configs.git ~/nixos-config
   cd ~/nixos-config
   ```

   The install needs the network anyway — `nixos-install` pulls everything from
   `cache.nixos.org`. **A Ventoy stick cannot serve as an offline repo drive**:
   while it serves the ISO, device-mapper holds the whole disk open.

---

## 2. Install (one command)

`flake.nix` defines one `nixosConfigurations.<host>` per machine (currently
`dragonflyg4` and `probook650`). With `lsblk` confirm the target disk, then:

```bash
./scripts/install.sh probook650 /dev/sda 17G   # host, disk, swap >= RAM
```

The script, in order:

1. Frees the disk from any earlier attempt (swap, `/mnt`, open LUKS mappings).
2. Asks the disk passphrase twice, into a tmpfs key file that is removed after.
3. Runs disko with `disko/laptop-luks.nix` (`--mode destroy,format,mount`).
4. Writes `nixos-generate-config --show-hardware-config` to the host's
   hardware file and stages it — flakes only read tracked files.
5. `nixos-install --flake .#<host> --no-root-passwd`.
6. Copies the repo to `/home/ogryson/nixos-config` on the new system, with the
   SSH remote, so `rebuild` works on first boot.

What disko builds — see `disko/laptop-luks.nix` for the authoritative version:

| Partition | Size       | Contents                                              |
|-----------|------------|-------------------------------------------------------|
| ESP       | 1G         | vfat, `/boot`, plaintext (UEFI has to read it)         |
| swap      | `swapSize` | LUKS2 `cryptswap` → swap labelled `SWAP`               |
| root      | rest       | LUKS2 `cryptroot` → btrfs `NIXOS`, subvolumes `@`, `@home`, `@nix` (`compress=zstd,noatime`) |

Why an encrypted swap **partition** rather than a random-key swap or a btrfs
swapfile: a random key can only be unlocked after boot, which rules out resume
from hibernation, and a swapfile needs a `resume_offset` that shifts whenever
the file is recreated. A LUKS partition is unlocked in the initrd, before
resume, and keeps its label.

The generated hardware file emits the LUKS entry for root, but not reliably the
one for swap. `disko/luks-boot.nix` (imported by every disko-installed host in
`flake.nix`) adds it by disko's partition label, plus the resume device, so the
generated file is used unedited. Both containers share one passphrase and the
systemd initrd asks for it once.

Reboot, remove the USB stick. The LUKS passphrase prompt appears before the
ReGreet login screen.

---

## 3. First boot

1. `passwd` — the config ships `initialPassword = "changeme"` and root is
   locked; administration goes through `sudo`.
2. Restore from backup: `~/.ssh/` (`chmod 600` the private key), `~/.gnupg/`,
   `~/.password-store/`, NetworkManager connections, browser profiles.
3. `rebuild` to confirm the machine can rebuild itself.

Keybinds to get going: `SUPER+Return` terminal, `SUPER+Space` launcher,
`SUPER+B` browser, `SUPER+L` lock, `SUPER+/` searchable keybinding cheat sheet.

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
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-partlabel/disk-main-root
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-partlabel/disk-main-swap
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
  `sudo cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-main-root --header-backup-file luks-root.img`
- **Second passphrase.** `sudo cryptsetup luksAddKey /dev/disk/by-partlabel/disk-main-root` adds a
  slot, so a forgotten primary passphrase is not a reinstall.
