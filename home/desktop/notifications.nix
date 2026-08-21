################################################################################
#  Notifications: SwayNC — popups plus a control center with a DND toggle.
#  Replaces mako; notify-send callers (volume/brightness OSD scripts in
#  ../shortcuts.nix) work unchanged, since SwayNC implements the freedesktop
#  Notifications interface.
#
#  Colours are baked from the build-time default palette in ../theme.nix.
#  Ceiling: unlike waybar, this stylesheet does not follow a live theme
#  switch — SwayNC's CSS handling of @import/@define-color could not be
#  verified, and an unparseable stylesheet would leave notifications
#  completely unstyled. A rebuild re-bakes whatever palette is default.
################################################################################
{ pkgs, lib, config, ... }:

let
  theme = import ../../theme.nix { };
  inherit (theme) raw;
in
{
  services.swaync = {
    enable = true;

    settings = {
      # Popups top-right, above fullscreen content.
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";

      notification-width = 420;
      notification-icon-size = 48;
      control-center-width = 500;

      # Same timeouts as before: 6 s default, critical stays until dismissed.
      timeout = 6;
      timeout-low = 5;
      critical-timeout = 0;

      # Control center: title row with a clear-all button, DND toggle, then
      # the notification list. Deliberately nothing else.
      widgets = [
        "title"
        "dnd"
        "notifications"
      ];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear";
        };
        dnd.text = "Do Not Disturb";
      };
    };

    style = ''
      /* Pill language shared with waybar: dark translucent surfaces, rounded
         corners, sky accent, alarm red for critical. */
      .notification {
        background: alpha(#${raw.base}, 0.94);
        border-radius: 14px;
        border: 1px solid alpha(#${raw.overlay}, 0.9);
        padding: 10px;
        margin: 8px;
      }
      .notification-content {
        background: transparent;
      }
      .notification-default-action,
      .notification-action {
        background: transparent;
        border-radius: 10px;
      }
      .notification-default-action:hover,
      .notification-action:hover {
        background: alpha(#${raw.surface}, 0.9);
      }

      .summary {
        color: #${raw.stone};
        font-weight: bold;
      }
      .body {
        color: #${raw.text};
      }
      .app-name {
        color: #${raw.subtle};
        font-size: 9px;
      }
      .time {
        color: #${raw.muted};
        font-size: 9px;
      }
      image {
        color: #${raw.sky};
      }

      /* Urgency levels. */
      .low .notification {
        border-color: alpha(#${raw.overlay}, 0.6);
      }
      .low .summary, .low .body { color: #${raw.subtle}; }
      .critical .notification {
        border: 2px solid #${raw.alarm};
      }
      .critical .summary { color: #${raw.alarm}; }

      /* Control center panel. */
      .control-center {
        background: alpha(#${raw.ink}, 0.96);
        border-radius: 16px;
        border: 1px solid alpha(#${raw.haze}, 0.35);
        margin: 10px;
      }
      .widget-title {
        color: #${raw.stone};
        font-size: 13px;
        padding: 10px 12px 4px;
      }
      .widget-title > button {
        background: alpha(#${raw.surface}, 0.9);
        color: #${raw.text};
        border-radius: 999px;
        padding: 4px 12px;
      }
      .widget-title > button:hover {
        background: #${raw.sky};
        color: #${raw.ink};
      }
      .widget-dnd {
        padding: 8px 12px;
      }
      .widget-dnd > switch {
        background: #${raw.overlay};
        border-radius: 999px;
        min-height: 20px;
        min-width: 38px;
      }
      .widget-dnd > switch:checked {
        background: #${raw.sky};
      }
      .blank-window {
        background: transparent;
      }
    '';
  };
}
