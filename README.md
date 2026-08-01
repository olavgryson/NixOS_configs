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
greeter.nix                loginscherm: greetd + ReGreet in een kale Hyprland
wallpaper.nix              de ene wallpaper voor login-, desktop- en lockscherm
theme.nix                  kleurpalet, uit die wallpaper bemonsterd
wallpapers/                de afbeeldingen zelf (moeten getrackt zijn, zie hieronder)
home.nix                   home-manager entry (wire-up, importeert home/*)
home/
  packages.nix             apps, dev-tooling, CLI/terminal-tools
  programs.nix             git, bash, kitty, shell-QoL
  desktop.nix              Hyprland + Wayland-desktop (pakketten én config)
  webapps.nix              PWA-launchers (SoundCloud, Snapchat)
inventory/                 ruwe dump van het oude systeem (referentie)
docs/
  hibernation-ipu6.md      why hibernation aborts on this machine (IPU6 camera)
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
3. **Deze repo**: kopieer `~/nixos-config/` naar de externe schijf (of push naar een private GitHub repo).
4. **VERIFIEER**: zet één willekeurige file terug en open hem. Check `du -sh` van bron vs doel. Pas dán wissen.

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
Reboot → **greetd/ReGreet** loginscherm → sessie **Hyprland**.
Keybinds: `SUPER+Return` terminal, `SUPER+R` launcher, `SUPER+B` browser, `SUPER+L` lock.

### Loginscherm (`greeter.nix`) — was SDDM

SDDM is eruit. Twee concrete problemen die dat oploste:

1. **Touchpad dood op het loginscherm.** SDDM's Wayland-greeter draait onder
   `weston --shell=kiosk`, en weston pikte de I2C-HID Synaptics (`SYNA310F:00`)
   van deze laptop niet op — vandaar dat er een USB-muis nodig was, terwijl
   diezelfde touchpad in Hyprland prima werkt. ReGreet draait nu ín Hyprland,
   dus het loginscherm gebruikt exact dezelfde libinput-stack als je desktop.

2. **"Reached target Graphical Interface" na inloggen.** De hyprland-package
   levert twee sessiebestanden: `hyprland.desktop` (werkt) en
   `hyprland-uwsm.desktop` (start `uwsm`). Die tweede vereist
   `programs.uwsm.enable`, wat alleen aangaat via
   `programs.hyprland.withUWSM = true` — default uit. Koos je hem toch, dan
   stierf de sessie binnen een seconde en viel je terug op VT1, waar die
   console-regel de laatste is. SDDM onthield je keuze, dus het bleef mislukken.
   `greeter.nix` filtert die kapotte sessie nu weg; je kúnt hem niet meer kiezen.

**Wallpaper wisselen:** zet de afbeelding in `wallpapers/`, **`git add` hem**
(flakes kopiëren alleen getrackte bestanden naar de store — zonder add faalt de
build met "path does not exist"), en pas `src` in `wallpaper.nix` aan.
Loginscherm, desktop (hyprpaper) en lockscherm (hyprlock) delen die ene
afbeelding.

**Kleuren wisselen:** `theme.nix` bevat het palet dat uit de huidige wallpaper
is bemonsterd. Waybar, mako, SwayOSD, rofi, hyprlock, de vensterranden en het
loginscherm lezen daar allemaal uit, dus één hexcode aanpassen verandert het
overal tegelijk. Neem je een andere wallpaper, dan hoor je hier nieuwe kleuren
uit te halen — bijvoorbeeld met:

```bash
magick wallpapers/jouw-wallpaper.jpg -resize 200x -colors 16 -unique-colors txt:
```

**Let op bij hyprpaper:** sinds 0.8 bestaat `preload` niet meer en is `wallpaper`
een blok (`wallpaper { monitor = ; path = … ; fit_mode = cover }`). De oude
`wallpaper = ,/pad`-vorm geeft géén foutmelding, hij doet alleen niets — het
enige spoor is `Monitor eDP-1 has no target: no wp will be created` in
`journalctl --user -u hyprpaper`.

**Waybar custom modules — `interval = 0` does not mean "never poll".** To waybar
it means *"this script is persistent, keep reading its stdout forever"*. If the
script prints its output and exits, waybar hits EOF on the pipe and then spins on
it: no error, no log line, the module renders correctly, and the bar quietly eats
a CPU core forever. `custom/brightness-ext` shipped this way and cost **15% CPU
permanently** — 42 million read syscalls and 80 GB of pipe reads in under two
hours of uptime.

Use `interval = "once"` (the string, not `0`) for a script that runs and exits.
That runs it a single time at startup, and after that only when its `signal`
arrives. Both values look equally "idle" in the config, which is exactly why this
is worth writing down.

Rule of thumb: `interval = 0` is only correct for a script that never returns
(a `while true` loop that keeps printing). Anything that exits wants `"once"`
or a real number of seconds.

To catch this class of bug — a process busy-looping without complaining — read
its syscall counters rather than guessing from `htop`:

```bash
P=$(pgrep waybar)
A=$(awk '/syscr/{print $2}' /proc/$P/io); sleep 10
B=$(awk '/syscr/{print $2}' /proc/$P/io)
echo "read syscalls/sec: $(( (B-A) / 10 ))"
```

A healthy waybar sits under ~20/sec. Thousands per second means something is
spinning on a dead file descriptor. Note that `strace` cannot attach here:
`kernel.yama.ptrace_scope = 1`. Bisect instead by launching a throwaway bar with
a subset of modules (`waybar -c test.json -s test.css`) and measuring each.

After changing the config, a `rebuild` only writes the new file to disk — the
running waybar keeps the old one until you `kill -SIGUSR2 $(pgrep waybar)`.

**Als je ooit buitengesloten raakt:** `Ctrl+Alt+F2` geeft een gewone TTY-login,
en in systemd-boot kun je de vorige generatie kiezen.

---

## Fase 5 — Restore + handmatige laatste loodjes

- **Data terug**: `rsync` je backup naar `/home/ogryson/` (sla de KDE-`.config` over; Hyprland is nieuw).
- **SSH**: `~/.ssh/` terugzetten, `chmod 600 id_ed25519`.
- **WiFi**: NM-connections terugzetten of opnieuw joinen.
- **Ollama**:
- **pass** (password-store): vereist je GnuPG-sleutel + `~/.password-store`. Zet `~/.gnupg/` en `~/.password-store/` terug uit de backup, anders kan `pass` niks ontsleutelen.
- **Webapps** (SoundCloud, Snapchat): geen native Linux/nixpkgs-app beschikbaar → blijven `--app=` wrappers (Chromium), al geregeld in `home/webapps.nix`. Verschijnen vanzelf in wofi.
- **Browsers**: firefox · chromium (voor de webapps) · **librewolf** · **zen** . Bij de eerste build verifieer ik de zen-flake-URL + binary-naam.

## Antigravity editor
Zit inmiddels gewoon in nixpkgs (`antigravity` voor de GUI, `antigravity-cli`
voor de terminal-agent) — zie `home/packages.nix`. Geen handmatige derivation
meer nodig. Als extensies problemen geven met dynamic linking buiten de Nix
store, staan `antigravity-fhs`/`antigravity-ide-fhs` klaar als FHS-wrapped
alternatief.
- **Brother scanner** (MFCL2800DW): SANE staat aan; USB-scannen vereist mogelijk `brscan5` — meld het als de scanner niet opduikt, dan voeg ik een overlay/driver toe.
- **node/bun**: config levert `nodejs_22` + `bun` systeembreed; je `.nvm`/`.bun` uit de backup is niet meer nodig (mag weg).

## Wat ik NIET kon voorbereiden (kernel-/machine-gebonden)
- `hardware-configuration.nix` (disk-UUIDs, kernelmodules) → Fase 2.
- Exacte monitor-resolutie/refresh in Hyprland → na eerste boot fijnstellen.
- Secrets (SSH/WiFi/browser) → bewust buiten de repo gehouden, uit backup.
