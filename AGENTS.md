# Agent guidelines — nixos-config (dragonflyg4)

NixOS + Home Manager flake for **dragonflyg4** (HP Dragonfly G4). See `README.md`
for the layout, install procedure and hardware notes; don't duplicate it here.

## Hard rules

1. **`git add` before any nix command.** Flakes only read git-tracked files.
   Forgetting it fails with `path '...' does not exist in the Nix store`.
2. **English only** — every comment, label, tooltip, doc and commit message.
3. **This repo is public.** Comments and docs carry only what a future rebuild
   or a new laptop needs: what the setting does and why it is that way. No
   migration history ("used to be X", "on the old machine"), no personal data
   (SSIDs, network names, hostnames of other machines, file paths from other
   systems), no narration of past debugging sessions. If a hard-won lesson is
   still actionable, state it as a rule, not as a story.
4. **Rebuild yourself.** After validating a change, run `rebuild` — do not hand
   it back to the user to apply.
5. Never edit `hardware-configuration.nix` by hand except for mount points or
   kernel parameters.

## Workflow

```bash
git status
# edit
git add .
nix flake check
nix build .#nixosConfigurations.dragonflyg4.config.system.build.toplevel --dry-run
rebuild
```

- `rebuild` is a passwordless wrapper (defined in `configuration.nix`) for
  `sudo nixos-rebuild switch --flake /home/ogryson/nixos-config#dragonflyg4`.
- High-risk change: `sudo nixos-rebuild test --flake .#dragonflyg4` first — it
  applies without becoming the boot default.
- Broke something: `sudo nixos-rebuild switch --rollback`, or pick the previous
  generation in systemd-boot. `Ctrl+Alt+F2` gets you a TTY.
- Updating inputs: `nix flake update` (or `--update-input <name>`),
  `git add flake.lock`, then the same check/build/rebuild.
- A bare `nix flake update` can pull an nixpkgs snapshot that has no cached
  binary for `jetbrains.idea-oss`/kotlin, forcing a multi-30-minute source
  build that OOMs this laptop (userspace build, not visible until it hangs).
  Before bumping nixpkgs: either disable idea-oss (see `home/packages.nix`),
  or update selectively (`--update-input zen-browser antigravity-nix`) and keep
  nixpkgs+home-manager pinned to their locked revision.

## Where things live

- System, services, hardware: `configuration.nix`, `greeter.nix`,
  `wallpaper.nix`, `theme.nix`
- User environment: `home.nix` and `home/{packages,programs,desktop,shortcuts,webapps}.nix`
- Colours are centralised in `theme.nix`; change a hex there, not in a consumer.

## Before finishing

- [ ] New files staged with `git add`
- [ ] Comments in English, durable, no personal data
- [ ] `nix flake check` / dry build clean
- [ ] `rebuild` run, changed services verified working
- [ ] Rolled back immediately if anything fatal broke
