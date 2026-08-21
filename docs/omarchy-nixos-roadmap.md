# Omarchy 4.0 NixOS Port Specification & Roadmap

## 1. Objective & Vision

Bring the design, ergonomics, and workflow innovations of **Omarchy 4.0** into this declarative **NixOS + Hyprland** configuration (`dragonflyg4`), preserving NixOS stability, atomic rollbacks, and reproducible builds.

Do not port Omarchy's imperative Arch bash scripts; port the **declarative configuration assets and UX patterns** directly into Home Manager and NixOS modules.

---

## 2. Target Feature Matrix

| Feature | Omarchy 4.0 Baseline | NixOS Native Implementation |
| :--- | :--- | :--- |
| **The Style & Aesthetics** | Hyprland blur/rounding, pill-style Waybar, SwayNC, JetBrainsMono NF | Port Waybar CSS, SwayNC widgets, and Hyprland decoration rules to `home/desktop/` |
| **Dynamic Theming** | Menu swapping colors across Hyprland, Waybar, terminal, Neovim | Live theme-switcher script via Walker/Rofi triggering reload signals (`hyprctl reload`, `killall -SIGUSR2 waybar`, `swaync-client -rs`) |
| **Unified Action Menu** | Walker/Rofi launcher for apps, windows, clipboard, power | Configure `walker` or `rofi-wayland` in `home/desktop/launcher.nix` with dedicated sub-modes (`cliphist`, app list, power) |
| **AI Coding Agent Scratchpad** | Instant terminal popup for debugging with coding agents | Hyprland special workspace / scratchpad bound to `Super + A` running a persistent agent terminal (`antigravity`, `claude`, etc.) |
| **Shortcut Overview** | Searchable keyboard shortcut cheat sheet | Keybinding `Super + /` triggering a searchable Rofi/Walker helper |
| **Stability & Rollbacks** | Rolling Arch | Pure declarative NixOS Flake (`rebuild` wrapper, generational boot rollbacks, locked dependencies) |

---

## 3. Codebase Architecture (`nixos-config`)

* **Repository Root:** `/home/ogryson/nixos-config`
* **Entry Point:** `flake.nix` (`nixosConfigurations.dragonflyg4`)
* **Key Modules:**
  - `configuration.nix`: System services, kernel, audio, display manager.
  - `theme.nix`: Centralized color definitions.
  - `home/desktop/`:
    - `wm.nix`: Hyprland configuration and window rules.
    - `bar.nix`: Waybar layout and CSS.
    - `launcher.nix`: App launcher setup (Rofi/Walker).
    - `notifications.nix`: SwayNC notification center.
    - `look.nix`: GTK, Qt, fonts, cursor.
  - `home/shortcuts.nix`: Keybindings (`$mainMod = SUPER`).

---

## 4. Phased Implementation Plan

### Phase 1: Unified Menu & Shortcut Overview
1. Ensure `walker` or `rofi-wayland` + `cliphist` are integrated in `home/desktop/launcher.nix`.
2. Implement a searchable Keybinding Helper:
   - Create a script or rofi/walker menu listing all custom bindings.
   - Bind `Super + /` (or `Super + Shift + /`) in `home/shortcuts.nix` to launch the helper.
3. Configure the main launcher menu (`Super + Space`) with application launcher, window switcher, and clipboard history.

### Phase 2: Dedicated AI Coding Agent Scratchpad
1. In `home/desktop/wm.nix` and `home/shortcuts.nix`:
   - Add Hyprland special workspace rules for the agent scratchpad:
     ```ini
     workspace = special:agent, gapsout:60, gapsin:0
     windowrulev2 = workspace special:agent, class:^(agent-scratchpad)$
     windowrulev2 = float, class:^(agent-scratchpad)$
     windowrulev2 = size 75% 80%, class:^(agent-scratchpad)$
     windowrulev2 = center, class:^(agent-scratchpad)$
     ```
   - Bind `Super + A` to toggle the special workspace:
     ```ini
     bind = $mainMod, A, togglespecialworkspace, agent
     ```
2. Add a launcher script or autostart hook ensuring a terminal (e.g. Kitty/Alacritty/Ghostty with class `agent-scratchpad`) runs in the scratchpad.

### Phase 3: Dynamic Theming & Omarchy Palettes
1. Define Omarchy color palettes (Tokyo Night, Catppuccin, Gruvbox, Everforest, Rose Pine, Nordic).
2. Implement a theme switcher script integrated into the launcher menu that dynamically updates active color templates and signals Hyprland, Waybar, and SwayNC to reload instantly.

### Phase 4: Bar & Notification Polish
1. Update `home/desktop/bar.nix` to match Omarchy's pill-shaped Waybar modules and status indicators.
2. Configure SwayNC in `home/desktop/notifications.nix` with quick toggles (DND, volume, night light).

---

## 5. Verification Checklist

- [ ] `git add .` run before checking Nix build.
- [ ] `nix flake check` passes.
- [ ] `nix build .#nixosConfigurations.dragonflyg4.config.system.build.toplevel --dry-run` succeeds.
- [ ] `rebuild` executed and verified live on desktop.
- [ ] `Super + /` opens shortcut cheat sheet.
- [ ] `Super + A` toggles AI agent scratchpad.
- [ ] Theme menu toggles color palettes live.
