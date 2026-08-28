# nixos-config — dragonflyg4 (HP Dragonfly G4)

NixOS + Hyprland, system and Home Manager configuration in one flake. Clone it
on a fresh install and `nixos-rebuild` builds the whole desktop.

- HP Dragonfly G4 · i7-1355U · Intel Iris Xe (no NVIDIA) · 16G RAM · UEFI
- Belgian keyboard · `en_GB.UTF-8` · Europe/Brussels · user `ogryson` · bash
- Login screen: greetd + ReGreet · Compositor: Hyprland · Bar: waybar

## Layout

```
flake.nix                   entrypoint (system + home-manager)
configuration.nix           system: drivers, services, virt, printing, power, hibernate
hardware-configuration.nix  machine-specific, generated per host (see below)
greeter.nix                 login screen: greetd + ReGreet in a bare Hyprland
wallpaper.nix               one wallpaper for login, desktop and lock screen
theme.nix                   colour palette, sampled from that wallpaper
wallpapers/                 the images themselves (must be git-tracked)
home.nix                    home-manager entry (wires up home/*)
home/
  packages.nix              apps, dev tooling, CLI/terminal tools
  programs.nix              git, bash, kitty, shell QoL
  desktop.nix               Hyprland + Wayland desktop (packages and config)
  shortcuts.nix             Hyprland keyboard and mouse bindings
  webapps.nix               PWA launchers (SoundCloud, Snapchat)
disko/
  laptop-luks.nix           declarative disk layout: LUKS2 + btrfs subvolumes
docs/
  installation.md           full install procedure (encrypted disk)
  hibernation-ipu6.md       why hibernation aborts on this machine (IPU6 camera)
```

## Daily use

```bash
rebuild                                  # passwordless wrapper for nixos-rebuild switch
sudo nixos-rebuild test --flake .#dragonflyg4   # try a risky change without making it the boot default
sudo nixos-rebuild switch --rollback     # undo a bad switch
```

Flakes only read **git-tracked** files. After adding any new file (module,
script, wallpaper), `git add` it or the build fails with
`path '...' does not exist in the Nix store`.

Update inputs:

```bash
nix flake update            # or: nix flake lock --update-input zen-browser
git add flake.lock
rebuild
```

If the desktop will not start, `Ctrl+Alt+F2` gives a TTY login, and the previous
generation can be selected in systemd-boot.

## Installing on a fresh machine

Full procedure — backup, disk layout, LUKS encryption, `nixos-install` — lives
in [`docs/installation.md`](docs/installation.md). Partitioning is declarative:
`disko/laptop-luks.nix` formats the disk in one command, parameterised on
device and swap size, so every machine gets the same encrypted btrfs layout and
only the generated hardware file differs.

## Changing the look

**Wallpaper:** put the image in `wallpapers/`, **`git add` it**, and point `src`
in `wallpaper.nix` at it. Login screen, desktop (hyprpaper) and lock screen
(hyprlock) all share that one image.

**Colours:** `theme.nix` holds the palette sampled from the current wallpaper.
Waybar, mako, SwayOSD, rofi, hyprlock, the window borders and the login screen
all read from it, so one hex change propagates everywhere. After a wallpaper
swap, resample with:

```bash
magick wallpapers/your-wallpaper.jpg -resize 200x -colors 16 -unique-colors txt:
```

## Notes worth keeping

**waybar: `interval = 0` does not mean "never poll".** To waybar it means *"this
script is persistent, keep reading its stdout forever"*. If the script prints and
exits, waybar hits EOF and spins on the dead pipe: no error, no log line, the
module renders correctly, and the bar quietly eats a CPU core forever. One module
shipped this way and cost **15% CPU permanently** — 42 million read syscalls and
80 GB of pipe reads in under two hours of uptime.

Use `interval = "once"` (the string, not `0`) for a script that runs and exits:
it runs once at startup and then only when its `signal` arrives. `interval = 0`
is correct only for a script that never returns.

To catch a process busy-looping without complaining, read its syscall counters
rather than guessing from `htop`:

```bash
P=$(pgrep waybar)
A=$(awk '/syscr/{print $2}' /proc/$P/io); sleep 10
B=$(awk '/syscr/{print $2}' /proc/$P/io)
echo "read syscalls/sec: $(( (B-A) / 10 ))"
```

A healthy waybar sits under ~20/sec; thousands per second means something is
spinning on a dead file descriptor. `strace` cannot attach here
(`kernel.yama.ptrace_scope = 1`) — bisect instead by launching a throwaway bar
with a subset of modules (`waybar -c test.json -s test.css`).

A `rebuild` only writes waybar's new config to disk; the running instance keeps
the old one until `kill -SIGUSR2 $(pgrep waybar)`.

**hyprpaper 0.8+:** `preload` is gone and `wallpaper` is a block
(`wallpaper { monitor = ; path = … ; fit_mode = cover }`). The old
`wallpaper = ,/path` form raises no error, it just does nothing — the only trace
is `Monitor eDP-1 has no target: no wp will be created` in
`journalctl --user -u hyprpaper`.

**Login screen:** ReGreet runs inside a bare Hyprland rather than under SDDM.
SDDM's weston-based greeter never picked up this laptop's I2C-HID touchpad, and
it offered a `hyprland-uwsm` session that dies instantly unless
`programs.hyprland.withUWSM` is on. `greeter.nix` filters that session out. Do
not enable `withUWSM` without adapting `greeter.nix`.

**Hibernation** aborts on this hardware unless the IPU6 camera modules are
blacklisted, and even then it is unverified. Never set
`MemorySleepMode = "deep"` — the machine does not wake from S3. Full diagnosis
in `docs/hibernation-ipu6.md`.

**External monitor:** matched by EDID description, not connector name — the
USB-C dock speaks DP-MST and renames the output on every replug. That same MST
path is why `ddcutil` cannot control its backlight; brightness goes through the
compositor gamma ramp (`wl-gammarelay-rs`) instead, which dims the image, not
the backlight.
