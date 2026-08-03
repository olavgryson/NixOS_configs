################################################################################
#  Notifications (mako), Pirna Bellotto style.
################################################################################
{ pkgs, lib, config, ... }:

let
  theme = import ../../theme.nix { };
  inherit (theme) raw;

in
{
  #### Notifications (Pirna Bellotto Classical Theme) #########################
  # Notification popups styled after Bernardo Bellotto's "Pirna" oil painting.
  # Uses sunlit sandstone gold border accents, canvas dark transparency, and
  # Pango markup ornaments for a classic gallery plaque feel.
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 6000;
      layer = "overlay";
      anchor = "top-right";
      margin = "14";
      padding = "14,18";
      width = 420;
      height = 200;
      border-size = 2;
      border-radius = 12;
      font = "JetBrainsMono Nerd Font 10";

      # Color palette sampled from Bellotto's Pirna (../theme.nix)
      background-color = "#${raw.ink}f4";
      text-color = "#${raw.text}";
      border-color = "#${raw.stone}dd";
      progress-color = "over #${raw.stone}cc";
      icons = true;
      max-icon-size = 48;
      icon-border-radius = 8;

      # Pango markup format string giving notifications an elegant gallery plaque layout
      format = "<span size=\"x-small\" foreground=\"#${raw.sky}\">⚜  <b>%a</b></span>\\n<span font_weight=\"bold\" size=\"11000\" foreground=\"#${raw.stone}\">%s</span>\\n<span size=\"9500\" foreground=\"#${raw.text}\">%b</span>";

      # Low urgency (subtle parchment grey/green haze)
      "urgency=low" = {
        background-color = "#${raw.base}f0";
        border-color = "#${raw.overlay}ee";
        default-timeout = 4000;
        format = "<span size=\"x-small\" foreground=\"#${raw.muted}\">📜  %a</span>\\n<span font_weight=\"bold\" size=\"10500\" foreground=\"#${raw.subtle}\">%s</span>\\n<span size=\"9500\" foreground=\"#${raw.subtle}\">%b</span>";
      };

      # Critical urgency (terracotta alarm red, stays until dismissed)
      "urgency=critical" = {
        background-color = "#1a0e0bf8";
        border-color = "#${raw.alarm}";
        default-timeout = 0;
        format = "<span size=\"x-small\" foreground=\"#${raw.alarm}\">⚔️  <b>%a</b>  •  <small>CRITICAL</small></span>\\n<span font_weight=\"bold\" size=\"11000\" foreground=\"#${raw.stone}\">%s</span>\\n<span size=\"9500\" foreground=\"#${raw.text}\">%b</span>";
      };

      # Fast & sleek OSD popup styling for Volume, Brightness, and Microphone
      "app-name=Volume" = {
        default-timeout = 1500;
        width = 340;
        height = 140;
        format = "<span size=\"x-small\" foreground=\"#${raw.sky}\">🔊  <b>Volume</b></span>\\n<span font_weight=\"bold\" size=\"12000\" foreground=\"#${raw.stone}\">%b</span>";
      };

      "app-name=Brightness" = {
        default-timeout = 1500;
        width = 340;
        height = 140;
        format = "<span size=\"x-small\" foreground=\"#${raw.stone}\">☀️  <b>Brightness</b></span>\\n<span font_weight=\"bold\" size=\"12000\" foreground=\"#${raw.stone}\">%b</span>";
      };

      "app-name=Microphone" = {
        default-timeout = 1500;
        width = 340;
        height = 140;
        format = "<span size=\"x-small\" foreground=\"#${raw.terra}\">🎙️  <b>Microphone</b></span>\\n<span font_weight=\"bold\" size=\"12000\" foreground=\"#${raw.stone}\">%b</span>";
      };
    };
  };
}
