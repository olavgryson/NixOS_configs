################################################################################
#  home-manager — user ogryson
#  Apps + Hyprland desktop, rebuilt from Debian inventory.
#  Trim packages you don't actually use; this mirrors what was installed.
################################################################################
{ config, pkgs, lib, inputs, ... }:

{
  home.username = "ogryson";
  home.homeDirectory = "/home/ogryson";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  #### Packages ###############################################################
  home.packages = with pkgs; [
    ## --- the thing you want first ---
    claude-code

    ## --- browsers ---
    firefox chromium brave

    ## --- dev tooling ---
    gh lazygit
    nodejs_22 corepack_22 bun
    python313 uv pipx
    php sqlite postgresql redis        # db clients / runtimes (php-mysql, postgresql-client, redis-server)
    docker-compose
    gnumake gcc

    ## --- editors / terminal utils ---
    vscode
    neovim
    tmux
    ripgrep fd fzf bat eza zoxide jq yq
    htop btop fastfetch
    unzip zip p7zip tree file wget curl rsync

    ## --- apps (GUI) ---
    obsidian
    discord
    spotify
    vlc mpv
    obs-studio
    libreoffice-fresh hunspell hunspellDicts.nl_BE hunspellDicts.en_GB
    angryipscanner    # netwerk-scanner (was Flatpak; verifieer attr: nix search nixpkgs angry)

    ## --- wine / gaming extras ---
    wineWowPackages.stable winetricks

    ## --- Hyprland desktop pieces ---
    waybar            # status bar
    wofi rofi-wayland # launchers
    mako libnotify    # notifications
    hyprpaper swww    # wallpaper
    hyprlock hypridle # lock + idle
    grim slurp swappy # screenshots
    wl-clipboard cliphist
    brightnessctl playerctl pamixer pavucontrol
    networkmanagerapplet blueman
    nautilus           # file manager (GTK; replaces Dolphin)
    kitty              # terminal
    xfce.thunar
    nwg-look           # GTK theme settings
    polkit_gnome
  ];

  #### Git (from current global config) #######################################
  programs.git = {
    enable = true;
    userName = "Olav Gryson";
    userEmail = "olav.gryson@gmail.com";
    extraConfig.init.defaultBranch = "main";
  };

  #### Shell QoL (keeps bash, adds modern helpers) ############################
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "eza -la --git";
      cat = "bat -pp";
      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#dragonflyg4";
    };
  };
  programs.zoxide.enable = true;
  programs.fzf.enable = true;

  #### Terminal ###############################################################
  programs.kitty = {
    enable = true;
    settings = { font_family = "JetBrainsMono Nerd Font"; font_size = 12; background_opacity = "0.95"; };
  };

  #### Notifications ##########################################################
  services.mako.enable = true;

  #### Hyprland (declarative) #################################################
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

  #### hypridle (lock + suspend) #############################################
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };
      listener = [
        { timeout = 300; on-timeout = "hyprlock"; }
        { timeout = 600; on-timeout = "systemctl suspend"; }
      ];
    };
  };

  #### hyprpaper (set your own wallpaper path) ###############################
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ ];   # add "~/Pictures/wall.png"
      wallpaper = [ ]; # add ",~/Pictures/wall.png"
    };
  };
}
