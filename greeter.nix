################################################################################
#  Loginscherm: greetd + ReGreet, draaiend ín een kale Hyprland met hyprpaper.
#
#  WAAROM NIET MEER SDDM
#  ---------------------
#  SDDM's Wayland-greeter draait onder `weston --shell=kiosk`. Weston pikte de
#  I2C-HID Synaptics touchpad (SYNA310F:00) van deze laptop niet op — vandaar
#  dat je een externe muis nodig had op het loginscherm, terwijl dezelfde
#  touchpad in Hyprland wél werkt. Door de greeter in Hyprland zelf te draaien
#  gebruikt het loginscherm exact dezelfde libinput-stack als je desktop.
#
#  WAAROM JE "Reached target Graphical Interface" ZAG
#  --------------------------------------------------
#  De hyprland-package levert TWEE sessiebestanden:
#      hyprland.desktop        -> start-hyprland          (werkt)
#      hyprland-uwsm.desktop   -> uwsm start -e -D ...    (werkt NIET)
#  Die tweede vereist `programs.uwsm.enable = true`, wat alleen aangaat via
#  `programs.hyprland.withUWSM = true` (default: uit). Stond die uit, dan viel
#  `uwsm` weg, stierf de sessie binnen een seconde, en viel je terug op VT1 —
#  waar de laatste console-regel "Reached target Graphical Interface" staat.
#  SDDM onthield bovendien je laatste keuze, dus het bleef mislukken.
#  Hieronder bieden we daarom uitsluitend de wérkende sessie aan.
################################################################################
{ config, pkgs, lib, ... }:

let
  wallpaper = import ./wallpaper.nix { inherit pkgs; };
  # Ook het loginscherm krijgt de ultrawide-render, anders zit je bij het
  # inloggen naar hetzelfde opgeblazen beeld te kijken als op de desktop.
  wallpaperUltrawide = import ./wallpaper.nix {
    inherit pkgs;
    width = 3440;
    height = 1440;
  };
  inherit (import ./theme.nix { }) raw;

  # Match the external monitor by EDID description, NOT by connector name. The
  # USB-C dock speaks DisplayPort MST and the kernel reassigns the invented
  # name on every replug (it has been both DP-6 and DP-7). A name-specific
  # rule silently falls through to the laptop render, which hyprpaper then
  # blows up to cover the ultrawide — the zoomed-in wallpaper.
  externalMonitorDesc = "desc:Xiaomi Corporation Mi Monitor";

  hyprland = config.programs.hyprland.package;

  # Alleen hyprland.desktop doorgeven aan de display manager; de kapotte
  # uwsm-variant filteren we eruit zodat je hem niet meer kúnt kiezen.
  hyprlandSession =
    pkgs.runCommand "hyprland-session"
      {
        passthru.providedSessions = [ "hyprland" ];
      }
      ''
        mkdir -p $out/share/wayland-sessions
        cp ${hyprland}/share/wayland-sessions/hyprland.desktop \
           $out/share/wayland-sessions/hyprland.desktop
      '';

  # hyprpaper voor de greeter-gebruiker. Het pad wijst naar de nix-store,
  # want `greeter` heeft geen toegang tot /home/ogryson.
  # Syntax van hyprpaper 0.8.x — zie de uitleg bij services.hyprpaper in
  # ./home/desktop.nix. De oude `preload`/`wallpaper = ,pad`-vorm wordt
  # zwijgend genegeerd, dus daarmee bleef ook het loginscherm leeg.
  # Zelfde opzet als services.hyprpaper in ./home/desktop.nix: eerst de schermen
  # die we kennen met hun eigen render, dan een lege monitor-regel als vangnet.
  greeterHyprpaperConf = pkgs.writeText "greeter-hyprpaper.conf" ''
    splash = false

    wallpaper {
      monitor  = ${externalMonitorDesc}
      path     = ${wallpaperUltrawide}
      fit_mode = cover
    }

    wallpaper {
      monitor  = eDP-1
      path     = ${wallpaper}
      fit_mode = cover
    }

    wallpaper {
      monitor  =
      path     = ${wallpaper}
      fit_mode = cover
    }
  '';

  #### Lid closed at boot ######################################################
  # The session already handles the lid (see bindl in ./home/shortcuts.nix), but
  # the greeter did not, and a bind only fires on an *event*. Boot with the lid
  # already shut and no event ever happens: Hyprland brings eDP-1 up like any
  # other output, ReGreet opens on it because it is monitor ID 0, and the login
  # field sits on a panel you cannot see. Hence this explicit check of the
  # current state at startup, next to the binds below for lid moves during the
  # login screen itself.
  #
  # The wait loop is for the MST hub: the external screen (whatever the dock
  # calls it today, DP-6 or DP-7) does not appear the instant Hyprland starts,
  # and disabling eDP-1 before the external screen has arrived would
  # leave zero outputs. So poll for a second screen for up to 5 s, and only
  # switch the panel off once one is actually there. On the road (lid shut, no
  # external) the loop times out and eDP-1 simply stays on.
  greeterLidClose = pkgs.writeShellScript "greeter-lid-close" ''
    others() {
      ${lib.getExe' hyprland "hyprctl"} -j monitors \
        | ${lib.getExe pkgs.jq} '[.[] | select(.name != "eDP-1")] | length'
    }

    for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 25); do
      [ "$(others)" -gt 0 ] && break
      ${lib.getExe' pkgs.coreutils "sleep"} 0.2
    done

    if [ "$(others)" -gt 0 ]; then
      ${lib.getExe' hyprland "hyprctl"} keyword monitor "eDP-1,disable"
    fi
  '';

  greeterLidOpen = pkgs.writeShellScript "greeter-lid-open" ''
    ${lib.getExe' hyprland "hyprctl"} keyword monitor "eDP-1,preferred,auto,1"
  '';

  # Startup order matters: settle the monitors *before* ReGreet maps its window,
  # otherwise it is placed on eDP-1 and stays there after the panel is switched
  # off. Sequential in one script, not two exec-once lines, which race.
  # `/proc/acpi/button/lid/*/state` is world-readable, so the greeter user can
  # read it; it reports "closed"/"open" for this laptop's single LID button.
  greeterStartup = pkgs.writeShellScript "greeter-startup" ''
    if ${lib.getExe' pkgs.gnugrep "grep"} -qi closed /proc/acpi/button/lid/*/state 2>/dev/null; then
      ${greeterLidClose}
    fi

    ${lib.getExe pkgs.regreet}
    ${lib.getExe' hyprland "hyprctl"} dispatch exit
  '';

  # Kale Hyprland als greeter-compositor: geen animaties, geen logo, geen
  # keybinds. Start hyprpaper voor de achtergrond en ReGreet voor het
  # loginveld; zodra ReGreet afsluit stopt de compositor en herstart greetd.
  greeterHyprlandConf = pkgs.writeText "greeter-hyprland.conf" ''
    monitor = ,preferred,auto,1

    input {
      kb_layout = be
      kb_model  = pc105
      follow_mouse = 1
      touchpad {
        natural_scroll = true
        tap-to-click   = true
      }
    }

    general {
      gaps_in = 0
      gaps_out = 0
      border_size = 0
    }

    animations { enabled = false }
    decoration { blur { enabled = false } }

    misc {
      disable_hyprland_logo    = true
      disable_splash_rendering = true
      force_default_wallpaper  = 0
    }
    # Note: `misc:vfr` no longer exists (it moved to `debug:vfr` and defaults
    # to on). Keeping it here made Hyprland show a config-error overlay on the
    # login screen, so it is intentionally gone.

    # ReGreet centered and floating, so the wallpaper stays visible around it.
    #
    # Hyprland 0.56 rewrote the rule syntax; both older spellings are rejected:
    #   windowrulev2 = float, class:(regreet)   -> "windowrulev2 is deprecated"
    #   windowrule   = float, class:(regreet)   -> "invalid field float: missing
    #                                              a value"
    # Rules are now comma-separated `field value` pairs, and matchers need the
    # `match:` prefix, mirroring the `match = { ... }` table of the new Lua
    # config. Booleans must be spelled out, hence `float true` over bare `float`.
    windowrule = float true, center true, size 100% 100%, match:class regreet

    # Closing or opening the lid *while* the login screen is up. Same device
    # name and same scripts-with-a-guard idea as the session (./home/
    # shortcuts.nix); "Lid Switch" comes verbatim from `hyprctl devices`.
    # `bindl` is the variant that keeps firing when the compositor is otherwise
    # inert, which is exactly the greeter's state.
    bindl = , switch:on:Lid Switch, exec, ${greeterLidClose}
    bindl = , switch:off:Lid Switch, exec, ${greeterLidOpen}

    exec-once = ${lib.getExe pkgs.hyprpaper} --config ${greeterHyprpaperConf}
    exec-once = ${greeterStartup}
  '';

  # ReGreet zoekt sessiebestanden in $XDG_DATA_DIRS/{wayland-sessions,xsessions}
  # en valt anders terug op /usr/share/... — dat bestaat niet op NixOS, dus dan
  # is de sessie-dropdown leeg en kun je niet inloggen. We wijzen daarom
  # expliciet naar het pad dat de displayManager-module samenstelt.
  # Launch through `start-hyprland` rather than the `Hyprland` binary directly.
  # Hyprland 0.56 paints a "Hyprland was started without start-hyprland" warning
  # over the screen when it is exec'd directly, which used to be the first
  # message on the login screen. The wrapper is a watchdog: it exits as soon as
  # Hyprland exits cleanly (which is what `hyprctl dispatch exit` below does),
  # so greetd's session lifecycle is unchanged. Arguments after `--` go to
  # Hyprland itself.
  greeterLauncher = pkgs.writeShellScript "greeter-launcher" ''
    export XDG_DATA_DIRS="${config.services.displayManager.sessionData.desktops}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    exec ${pkgs.dbus}/bin/dbus-run-session \
      ${lib.getExe' hyprland "start-hyprland"} -- --config ${greeterHyprlandConf}
  '';
in
{
  #### SDDM uitzetten ##########################################################
  # mkForce omdat configuration.nix historisch sddm aanzette; laat die regels
  # daar gerust staan of haal ze weg — deze wint hoe dan ook.
  services.displayManager.sddm.enable = lib.mkForce false;

  #### Alleen de werkende Hyprland-sessie aanbieden ###########################
  services.displayManager.sessionPackages = lib.mkForce [ hyprlandSession ];

  #### ReGreet #################################################################
  programs.regreet = {
    enable = true;

    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    # Zelfde cursor als in de sessie (home/desktop.nix), zodat de pijl niet
    # verspringt op het moment dat je inlogt.
    cursorTheme = {
      name = "capitaine-cursors";
      package = pkgs.capitaine-cursors;
    };
    font = {
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
      size = 14;
    };

    settings = {
      GTK.application_prefer_dark_theme = true;

      # ReGreet tekent de achtergrond óók zelf. hyprpaper hierboven doet het
      # eigenlijke werk; dit is de vangnet-laag voor als het GTK-venster niet
      # doorschijnend blijkt te zijn. Zelfde bestand, dus je ziet hoe dan ook
      # exact dezelfde wallpaper.
      background = {
        path = "${wallpaper}";
        fit = "Cover";
      };
    };

    # Let op: ReGreet 0.4 bouwt zijn UI programmatisch op (relm4, geen .ui-
    # templates), dus er zijn géén stabiele id-selectors zoals #main-box.
    # Alleen generieke GTK4-nodes hieronder — die matchen gegarandeerd.
    # Kleuren uit ./theme.nix, hetzelfde palet als waybar/mako/hyprlock.
    extraCss = ''
      window {
        background-color: alpha(#${raw.ink}, 0.45);
      }
      entry, button {
        border-radius: 8px;
        min-height: 34px;
        border: 1px solid alpha(#${raw.haze}, 0.35);
        color: #${raw.text};
      }
      entry {
        background-color: alpha(#${raw.ink}, 0.85);
      }
      entry:focus {
        border-color: #${raw.sky};
      }
      button:hover {
        background-color: alpha(#${raw.haze}, 0.18);
      }
      label {
        color: #${raw.text};
      }
    '';
  };

  #### greetd: ReGreet in Hyprland i.p.v. de standaard `cage` #################
  # De regreet-module zet dit met mkDefault, dus een gewone toewijzing wint.
  services.greetd.settings.default_session.command = "${greeterLauncher}";

  # Hyprland heeft in de greeter-sessie toegang tot GPU en input nodig.
  users.users.greeter.extraGroups = [
    "video"
    "input"
  ];
}
