# GNOME Files / Nautilus Custom Folder Icons

Guidelines for applying custom folder icons in GNOME Files (Nautilus) under GTK4 and icon themes (e.g., Papirus-Dark):

## Core Rules
1. **Use `metadata::custom-icon-name`**, NOT `metadata::custom-icon file:///...`. Standalone file URIs trigger GTK4 fallback to `text-x-generic` (document icon).
2. **Install Custom PNG/SVG Icons into Active Theme Paths**:
   ```bash
   mkdir -p ~/.local/share/icons/Papirus-Dark/64x64/places/
   cp /path/to/icon.png ~/.local/share/icons/Papirus-Dark/64x64/places/<icon-name>.png
   gtk-update-icon-cache -f -t ~/.local/share/icons/Papirus-Dark
   ```
3. **Apply Icon Name & Refresh**:
   ```bash
   gio set <dir> metadata::custom-icon-name <icon-name>
   nautilus -q
   ```
   - Built-in Papirus green folder: `gio set <dir> metadata::custom-icon-name folder-green`
   - Custom installed icon: `gio set <dir> metadata::custom-icon-name <icon-name>`
