################################################################################
#  Hyprland + Wayland desktop — packages AND configuration.
#  Kept separate from your apps/dev packages (./packages.nix) on request.
################################################################################
{ pkgs, ... }:
{
  #### Desktop packages (only the WM/Wayland stack) ##########################
  home.packages = with pkgs; [
    waybar                 # status bar
    wofi rofi-wayland      # launchers
    libnotify              # notify-send (mako itself comes from services.mako)
    hyprlock               # screen locker
    grim slurp swappy      # screenshots (+ annotate)
    wl-clipboard cliphist  # clipboard + history
    brightnessctl playerctl pamixer pavucontrol
    networkmanagerapplet blueman
    nautilus xfce.thunar   # file managers (GTK)
    nwg-look               # GTK theme settings
    polkit_gnome           # auth agent
  ];

  #### Notifications #########################################################
  services.mako.enable = true;

  #### Hyprland (declarative) ################################################
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;        # use the system Hyprland from programs.hyprland
    portalPackage = null;
    settings = {
      "$mod" = "SUPER";
      "$term" = "kitty";

      monitor = ",preferred,auto,1";   # auto for laptop panel; refine later

      input = {
        kb_layout = "be";              # Belgian AZERTY, like your current setup
        follow_mouse = 1;
        touchpad = { natural_scroll = true; tap-to-click = true; };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };
      decoration = {
        rounding = 8;
        blur = { enabled = true; size = 6; passes = 2; };
      };

      exec-once = [
        "waybar"
        "mako"
        "hyprpaper"
        "hypridle"
        "nm-applet --indicator"
        "blueman-applet"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];

      bind = [
        "$mod, Return, exec, $term"
        "$mod, Q, killactive,"
        "$mod, M, exit,"
        "$mod, E, exec, nautilus"
        "$mod, R, exec, wofi --show drun"
        "$mod, V, togglefloating,"
        "$mod, F, fullscreen,"
        "$mod, L, exec, hyprlock"
        "$mod, B, exec, firefox"
        # focus
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
        # clipboard history
        "$mod, period, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
        # screenshot region -> annotate
        ", Print, exec, grim -g \"$(slurp)\" - | swappy -f -"
      ]
      ++ (builtins.concatLists (builtins.genList (i:
        let ws = toString (i + 1);
        in [
          "$mod, ${ws}, workspace, ${ws}"
          "$mod SHIFT, ${ws}, movetoworkspace, ${ws}"
        ]) 9));

      bindel = [
        ", XF86AudioRaiseVolume, exec, pamixer -i 5"
        ", XF86AudioLowerVolume, exec, pamixer -d 5"
        ", XF86AudioMute, exec, pamixer -t"
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
      bindl = [
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
    };
  };

  #### hypridle (lock + suspend-then-hibernate) #############################
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };
      listener = [
        { timeout = 300;  on-timeout = "loginctl lock-session"; }
        { timeout = 900;  on-timeout = "systemctl suspend-then-hibernate"; }
      ];
    };
  };

  #### hyprpaper (set your own wallpaper path) ##############################
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ ];   # add "~/Pictures/wall.png"
      wallpaper = [ ]; # add ",~/Pictures/wall.png"
    };
  };
}
