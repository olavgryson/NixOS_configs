################################################################################
#  Look and feel: cursor (set three ways) and GTK theme.
################################################################################
{ pkgs, config, ... }:

let
  # In one place, because the cursor has to be set three ways: through
  # home.pointerCursor (which writes ~/.icons/default and the GTK settings) and
  # through XCURSOR_* in Hyprland's environment (for the compositor itself and
  # every client that draws its own cursor).
  cursorTheme = "capitaine-cursors";
  cursorSize = 24;
in
{
  home.pointerCursor = {
    # Explicitly on: recent home-manager deprecates inferring this from the
    # rest of the block.
    enable = true;
    package = pkgs.capitaine-cursors;
    # NOTE: this is the DIRECTORY NAME under share/icons, not the `Name=` from
    # index.theme ("Capitaine Cursors", with a space — XCursor does not look
    # that up).
    name = cursorTheme;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Noto Sans";
      size = 10;
    };
  };

  # XCURSOR_* set the cursor for the compositor and every client too (see
  # the note on cursorTheme above), so nothing falls back to ~/.icons/default.
  wayland.windowManager.hyprland.settings.env = [
    "XCURSOR_THEME,${cursorTheme}"
    "XCURSOR_SIZE,${toString cursorSize}"
  ];
}
