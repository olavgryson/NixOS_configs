################################################################################
#  The compositor itself (Hyprland).
################################################################################
{ pkgs, lib, config, ... }:

let
  monitors = import ./monitors.nix { inherit pkgs; };
  inherit (monitors) externalMonitor laptopMonitor;
  theme = import ../../theme.nix { };
  inherit (theme) raw;
  # Passed to `udiskie --event-hook`: fires on every mount/unmount so the
  # waybar module above updates immediately instead of on a poll interval.
  diskNotifyHook = pkgs.writeShellScript "disk-notify-hook" ''
    ${pkgs.procps}/bin/pkill -RTMIN+9 waybar 2>/dev/null || true
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;        # use the system Hyprland from programs.hyprland
    portalPackage = null;
    settings = {
      "$mod" = "SUPER";
      "$term" = "kitty";
      "$menu" = "rofi -show drun";
      # The zen flake installs the binary as `zen-beta`, not `zen`; with "zen"
      # the $mod+B bind silently does nothing.
      "$browser" = "zen-beta";
      "$files" = "nautilus";

      # ── Screens ─────────────────────────────────────────────────────────
      # The ultrawide sits ABOVE the laptop panel, not beside it. Hyprland has no
      # "above/below" keywords, only coordinates, so the layout is:
      #
      #     x=0                                          x=3440
      #   y=0    ┌────────────────────────────────────────┐
      #          │      external  3440x1440 (desc match)  │
      #   y=1440 └──────────┬──────────────────┬──────────┘
      #                     │  eDP-1 1920x1280 │
      #   y=2720            └──────────────────┘
      #                   x=760              x=2680
      #
      # 760 = (3440 - 1920) / 2, so the laptop panel hangs centred under the
      # ultrawide and the mouse runs straight down into it.
      #
      # 120 Hz, not 144. This Mi Monitor's EDID offers nothing above 120 at
      # 3440x1440 (144 exists only at 2560x1080). Hyprland ACCEPTS `@144` and
      # then reports it back happily, so `hyprctl monitors` shows nothing wrong —
      # but aquamarine then logs a steady stream of "atomic drm request: failed to
      # commit: Device or resource busy", i.e. dropped frames. At 120 that log is
      # clean (measured: 4 failures per 6 s at 144, 0 per 5 s at 120). The link
      # simply does not have the bandwidth.
      monitor = [
        externalMonitor
        laptopMonitor
        ",preferred,auto,1"          # fallback for unknown screens
      ];

      # Without XCURSOR_THEME in the session environment every client looks up
      # "default" and follows ~/.icons/default/index.theme — but which app reads
      # that file first, and when, varies. The result is a desktop showing some
      # leftover theme instead of the configured one. Setting it explicitly
      # removes the guesswork; Hyprland exports these to everything it starts,
      # so compositor and clients agree.

      input = {
        kb_layout = "be";              # Belgian AZERTY
        follow_mouse = 1;
        touchpad = { natural_scroll = true; tap-to-click = true; };
      };

      general = {
        gaps_in = 2;
        gaps_out = 5;
        border_size = 2;
        layout = "dwindle";
        # The active border runs from sky to grain — the same transition the
        # painting makes top to bottom. Inactive windows get the tree shadow so
        # they recede.
        "col.active_border" = "rgba(${raw.sky}ee) rgba(${raw.ochre}ee) 45deg";
        "col.inactive_border" = "rgba(${raw.overlay}aa)";
      };
      # dwindle splits side by side while width > height * multiplier, so on an
      # ultrawide every new window would keep stacking left-to-right. 1.5 sits
      # between the two aspect ratios that matter here: a full-screen window
      # still splits side by side, a half-screen pane splits top/bottom.
      dwindle.split_width_multiplier = 1.5;

      decoration = {
        rounding = 8;
        blur = { enabled = true; size = 6; passes = 2; };
      };

      # hyprpaper and hypridle are DELIBERATELY absent here: services.hyprpaper
      # and services.hypridle (bottom of this file) already create systemd user
      # units that start via hyprland-session.target -> graphical-session.target.
      # exec-once'ing them as well gives a second instance fighting over the same
      # wayland socket.
      # nm-applet and blueman-applet are absent for a different reason: each adds
      # its own systray icon on top of waybar's `network` and `bluetooth`
      # modules, so you end up with duplicate wifi and bluetooth icons. The
      # waybar modules stay (they follow the theme); clicking them still opens
      # the GUIs: network -> networkmanager_dmenu (Wi-Fi picker), bluetooth ->
      # blueman-manager.
      # waybar is deliberately absent here: it runs as its own systemd user
      # service (programs.waybar.systemd in ../desktop/bar.nix) so that a
      # monitor-hotplug crash or battery-module hang auto-restarts it instead
      # of being gone until the next login.
      exec-once = [
        "mako"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        # Watches udisks2 (enabled in ../configuration.nix) and auto-mounts USB
        # drives/SD cards on plug-in. No --tray: its icon didn't match the rest
        # of the bar (see custom/disks above, which replaces it and uses
        # --event-hook here to refresh on every mount/unmount).
        "${pkgs.udiskie}/bin/udiskie --no-tray --event-hook ${diskNotifyHook}"
      ];
    };
  };
}
