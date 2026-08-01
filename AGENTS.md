# AI Agent Guidelines & NixOS Maintenance Manual

This repository contains the NixOS system and Home Manager configuration for **dragonflyg4** (HP Dragonfly G4).

Any AI agent (Gemini, Claude, Antigravity, etc.) operating in this workspace **MUST** adhere to the guidelines below to ensure all system updates and configuration changes are executed efficiently, effectively, and safely without breaking system functionality.

---

## 1. Core NixOS & Flake Principles

### ⚠️ CRITICAL: Git Tracking (Flake Requirement)
Nix Flakes **only read files tracked by Git**.
- **Rule**: Whenever you add a new file (e.g., a new package module, script, or wallpaper), you **MUST** run `git add <file>` before running any Nix command.
- **Symptom if forgotten**: Build fails with `path '...' does not exist in the Nix store`.

### 🚨 Privilege Separation & Autonomous Rebuilds
- Use standard user privileges for `git`, `nix flake check`, `nix search`, `nix-instantiate`, and `nix build --dry-run`.
- **Automatic Rebuild Rule**: AI agents MUST run the `rebuild` command on their own to apply system updates after validating changes. Do NOT rely on the user to apply updates manually.
- The `rebuild` command is a custom passwordless wrapper configured in `configuration.nix` that executes `sudo nixos-rebuild switch --flake /home/ogryson/nixos-config#dragonflyg4`.

### 🌐 Language Requirement
- **Rule**: All configuration comments, UI labels, tooltips, documentation, and commit messages created or updated by AI agents **MUST** be written in **English**. Do not use Dutch or other languages for tooltips, labels, or documentation.

---

## 2. Standard Workflow for Making Changes & System Updates

Always follow this 5-step workflow:

### Step 1: Pre-Change Inspection & Status
Check git status and existing repo state:
```bash
git status
```

### Step 2: Edit Configuration
Make clean, modular updates:
- **System Settings & Services**: `./configuration.nix`, `./greeter.nix`, `./wallpaper.nix`, `./theme.nix`.
- **User Environment & Hyprland**: `./home.nix` and submodules in `./home/` (`packages.nix`, `programs.nix`, `desktop.nix`, `shortcuts.nix`, `webapps.nix`).
- **Hardware/Kernel**: `./hardware-configuration.nix` (Do not edit manually unless updating drive mounts or kernel parameters).

### Step 3: Stage Files in Git
```bash
git add .
```

### Step 4: Validate & Dry Build
Before applying any change to the live system, test compilation:
```bash
# Check flake evaluation syntax and inputs
nix flake check

# Perform a dry build to test package compilation
nix build .#nixosConfigurations.dragonflyg4.config.system.build.toplevel --dry-run
```

### Step 5: Apply Build (Autonomous)

#### Full Switch (Standard Apply)
Agents **MUST** execute `rebuild` on their own to automatically apply and test changes:
```bash
rebuild
```
*(Note: `rebuild` runs passwordlessly and applies the flake configuration as the default boot profile).*

#### Temporary Test (Safe for Risky Changes)
If making high-risk changes, test with:
```bash
sudo nixos-rebuild test --flake .#dragonflyg4
```

---

## 3. How to Perform System & Flake Updates

To update system dependencies, nixpkgs, or Home Manager:

### Update All Inputs:
```bash
# 1. Update flake.lock
nix flake update

# 2. Stage lockfile
git add flake.lock

# 3. Dry build & test
nix flake check
nix build .#nixosConfigurations.dragonflyg4.config.system.build.toplevel --dry-run

# 4. Apply switch automatically
rebuild
```

### Update a Single Input (e.g., zen-browser or home-manager):
```bash
nix flake lock --update-input zen-browser
git add flake.lock
rebuild
```

---

## 4. Rollback & Emergency Recovery

If a build fails or causes system instability after switching:

1. **Immediate Rollback**:
   ```bash
   sudo nixos-rebuild switch --rollback
   ```
2. **Bootloader Selection**:
   If the GUI or system becomes unresponsive, reboot the machine and select the previous working generation in `systemd-boot`.
3. **TTY Access**:
   Press `Ctrl + Alt + F2` to open TTY2, log in as `ogryson` or root, and run `sudo nixos-rebuild switch --rollback`.

---

## 5. System Architecture Reference

- **Host target**: `dragonflyg4` (`.#dragonflyg4`)
- **Graphics**: Intel Iris Xe (`i7-1355U` - no NVIDIA drivers needed)
- **Display Server & DM**: Hyprland managed via `ReGreet` + `greetd` in `greeter.nix`.
  - *Note*: `hyprland-uwsm` is intentionally disabled to avoid session crash loops.
- **Theme & Wallpapers**: Centralized in `theme.nix` & `wallpaper.nix`.
- **Home Manager**: Integrated as a NixOS module (`home-manager.backupFileExtension = "hm-bak"` handles dotfile conflicts automatically).
- **Rebuild Command**: Passwordless script `rebuild` provided by system packages.

---

## 6. Agent Rules & Checklist

- [ ] All new files staged with `git add`
- [ ] All comments, tooltips, UI text, and documentation written in **English**
- [ ] Flake checked with `nix flake check` or `nix build --dry-run`
- [ ] Build applied autonomously via `rebuild` command
- [ ] Verified that active services or changed apps work without runtime errors
- [ ] Reverted/rolled back immediately if any fatal issue occurred
