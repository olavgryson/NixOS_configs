# NixOS migratie — dragonflyg4 (HP Dragonfly G4)

Van **Debian 13 + KDE** → **NixOS + Hyprland**. Volledige wipe + restore.
Deze repo is het zaad: clone hem op de nieuwe install en `nixos-rebuild` bouwt alles.

## Systeemprofiel (vastgelegd 2026-06-17 vanaf het oude systeem)
- HP Dragonfly G4 · i7-1355U · **Intel Iris Xe** (geen NVIDIA → Hyprland easy) · 16G RAM · UEFI
- BE-toetsenbord · `en_GB.UTF-8` · Europe/Brussels · gebruiker `ogryson` · shell bash
- Volledige inventaris staat in `./inventory/` (pakketten, services, netwerk, enz.)

## Repo-structuur
```
flake.nix                  entrypoint (systeem + home-manager)
configuration.nix          systeem: drivers, services, virt, printing, hibernate, Hyprland-basis
hardware-configuration.nix  PLACEHOLDER → genereren op nieuwe machine (Fase 2)
home.nix                   home-manager entry (wire-up, importeert home/*)
home/
  packages.nix             apps, dev-tooling, CLI/terminal-tools
  programs.nix             git, bash, kitty, shell-QoL
  desktop.nix              Hyprland + Wayland-desktop (pakketten én config)
  webapps.nix              PWA-launchers (SoundCloud, Snapchat)
inventory/                 ruwe dump van het oude systeem (referentie)
```

---

## Fase 0 — Backup (op het OUDE systeem, vóór je iets wist)

Op externe schijf (≥ 500G), en **verifieer** voor je wist:

1. **Persoonlijke data** — heel `/home/ogryson` behalve caches:
   ```bash
   rsync -aAXv --info=progress2 \
     --exclude='.cache' --exclude='.local/share/Trash' \
     --exclude='.npm' --exclude='.nvm' --exclude='.cargo' \
     /home/ogryson/  /run/media/EXT/dragonfly-home/
   ```
2. **Geheimen apart noteren/kopiëren** (komen NIET in deze git-repo):
   - `~/.ssh/` (je `id_ed25519` keypair) → terugzetten na install.
   - WiFi-wachtwoorden: `sudo cp -a /etc/NetworkManager/system-connections/ EXT/nm-connections/`
     (terugzetten naar dezelfde map op NixOS, dan `chmod 600`, `chown root`). Anders 23 netwerken opnieuw via `nmtui`.
   - Browser-profielen, KeePass-db, GPG (geen gevonden), `.config` van apps die je wil bewaren.
3. **Ollama-modellen**: `~/.ollama/` meenemen (qwen3.5:4b, qwen3:1.7b) — of later opnieuw `ollama pull`.
4. **Deze repo**: kopieer `~/nixos-config/` naar de externe schijf (of push naar een private GitHub repo).
5. **VERIFIEER**: zet één willekeurige file terug en open hem. Check `du -sh` van bron vs doel. Pas dán wissen.

---

## Fase 1 — NixOS minimal installeren

1. Schrijf de **minimal/console ISO** naar USB (geen DE nodig — wij bouwen Hyprland uit config).
2. Boot USB (UEFI, secure boot UIT in BIOS).
3. Netwerk: `sudo systemctl start wpa_supplicant` of `nmtui` → join WiFi. Test `ping nixos.org`.

### Partitieschema (hele schijf `/dev/nvme0n1`) — MET swap voor hibernate
RAM = 16G → swap-partitie 17G (≥ RAM, nodig om te kunnen hibernaten).
```bash
sudo wipefs -a /dev/nvme0n1
sudo parted /dev/nvme0n1 -- mklabel gpt
sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB          # ESP 1G (was 512M = te krap)
sudo parted /dev/nvme0n1 -- set 1 esp on
sudo parted /dev/nvme0n1 -- mkpart swap linux-swap 1GiB 18GiB   # 17G swap = hibernate-target
sudo parted /dev/nvme0n1 -- mkpart primary 18GiB 100%          # rest = btrfs
sudo mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
sudo mkswap -L SWAP /dev/nvme0n1p2
sudo swapon /dev/nvme0n1p2          # AAN laten staan → generate-config pikt swapDevices op
sudo mkfs.btrfs -L NIXOS /dev/nvme0n1p3
```
Btrfs-subvolumes (zelfde @/@home-stijl als je oude setup):
```bash
sudo mount /dev/nvme0n1p3 /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
sudo btrfs subvolume create /mnt/@nix
sudo umount /mnt
OPTS=compress=zstd,noatime
sudo mount -o subvol=@,$OPTS /dev/nvme0n1p3 /mnt
sudo mkdir -p /mnt/{home,nix,boot}
sudo mount -o subvol=@home,$OPTS /dev/nvme0n1p3 /mnt/home
sudo mount -o subvol=@nix,$OPTS   /dev/nvme0n1p3 /mnt/nix
sudo mount /dev/nvme0n1p1 /mnt/boot
```
> Hibernate staat aan in de config (`boot.resumeDevice` = label `SWAP`, lid-dicht →
> suspend-then-hibernate na 30 min). Belangrijk: laat `swapon` actief vóór
> `nixos-generate-config`, anders ontbreekt `swapDevices` (dan handmatig toevoegen,
> zie comment in `configuration.nix`).

---

## Fase 2 — hardware-configuration.nix genereren (het stuk dat IK niet kan schrijven)

```bash
sudo nixos-generate-config --root /mnt
```
Dit maakt `/mnt/etc/nixos/hardware-configuration.nix` met de échte disk-UUIDs, kernelmodules en `fileSystems`. **Dit bestand is leidend** — het placeholder-bestand in deze repo vervang je ermee.

---

## Fase 3 — Claude Code binnenhalen + overdracht aan mij

1. Tijdelijke shell met de tools:
   ```bash
   nix-shell -p git nodejs claude-code
   ```
   (of installeer eerst alleen het systeem in Fase 4 — `claude-code` zit al in `home.nix`.)
2. Clone deze repo van de externe schijf:
   ```bash
   git clone /run/media/EXT/nixos-config ~/nixos-config   # of van GitHub
   ```
3. Kopieer de gegenereerde hardware-config erover:
   ```bash
   cp /mnt/etc/nixos/hardware-configuration.nix ~/nixos-config/hardware-configuration.nix
   ```
4. Start Claude Code in `~/nixos-config` en zeg: **"verifieer hardware-configuration tegen inventory/ en bouw het systeem"**.
   Dan doe ik:
   - hardware-config diffen tegen `inventory/40-lsmod.txt` + `41-cpu.txt`
   - `fileSystems` checken (subvols, `/nix`, ESP)
   - eventueel hibernate/swap, secure boot, monitor-resolutie afwerken

---

## Fase 4 — Bouwen

```bash
# installer (vanuit /mnt):
sudo nixos-install --flake ~/nixos-config#dragonflyg4
# of, al gebooted in NixOS:
sudo nixos-rebuild switch --flake ~/nixos-config#dragonflyg4
```
Reboot → SDDM → kies **Hyprland**. Keybinds: `SUPER+Return` terminal, `SUPER+R` launcher, `SUPER+B` browser, `SUPER+L` lock.

---

## Fase 5 — Restore + handmatige laatste loodjes

- **Data terug**: `rsync` je backup naar `/home/ogryson/` (sla de KDE-`.config` over; Hyprland is nieuw).
- **SSH**: `~/.ssh/` terugzetten, `chmod 600 id_ed25519`.
- **WiFi**: NM-connections terugzetten of opnieuw joinen.
- **Ollama**: modellen NIET nodig — geen restore/pull. Service staat aan; pull later handmatig als je ze ooit wil.
- **pass** (password-store): vereist je GnuPG-sleutel + `~/.password-store`. Zet `~/.gnupg/` en `~/.password-store/` terug uit de backup, anders kan `pass` niks ontsleutelen.
- **Webapps** (SoundCloud, Snapchat): geen native Linux/nixpkgs-app beschikbaar → blijven `--app=` wrappers (Chromium), al geregeld in `home/webapps.nix`. Verschijnen vanzelf in wofi.
- **Browsers**: firefox · chromium (voor de webapps) · **librewolf** · **zen** (vervangt brave, via flake-input). Bij de eerste build verifieer ik de zen-flake-URL + binary-naam.

## Antigravity editor (handmatig packagen)
Google Antigravity zit **niet** in nixpkgs (te nieuw + proprietary). Op de nieuwe
machine pak ik dit zo aan — kies één:
1. **Officiële download** (`.deb`/AppImage) → ik schrijf een derivation
   (`pkgs/antigravity.nix`, autoPatchelf/appimageTools) met de juiste hash.
   Geef me de download-URL, of ik haal hem van de Antigravity-site.
2. Tijdelijk via `distrobox`/`nix-shell` tot het gepackaged is.
Tot dan: VSCode + Claude Code dekken het meeste.
- **Brother scanner** (MFCL2800DW): SANE staat aan; USB-scannen vereist mogelijk `brscan5` — meld het als de scanner niet opduikt, dan voeg ik een overlay/driver toe.
- **node/bun**: config levert `nodejs_22` + `bun` systeembreed; je `.nvm`/`.bun` uit de backup is niet meer nodig (mag weg).

## Wat ik NIET kon voorbereiden (kernel-/machine-gebonden)
- `hardware-configuration.nix` (disk-UUIDs, kernelmodules) → Fase 2.
- Exacte monitor-resolutie/refresh in Hyprland → na eerste boot fijnstellen.
- Secrets (SSH/WiFi/browser) → bewust buiten de repo gehouden, uit backup.
