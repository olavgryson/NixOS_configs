################################################################################
#  Login screen: greetd + ReGreet, running inside a bare Hyprland with
#  hyprpaper.
#
#  WHY NOT SDDM
#  ------------
#  SDDM's Wayland greeter runs under `weston --shell=kiosk`, and weston does not
#  pick up this laptop's I2C-HID Synaptics touchpad (SYNA310F:00) — which is why
#  the login screen needed an external mouse while the same touchpad works fine
#  in Hyprland. Running the greeter inside Hyprland means the login screen uses
#  exactly the same libinput stack as the desktop session.
#
#  WHY THE SESSION USED TO DIE ON "Reached target Graphical Interface"
#  -------------------------------------------------------------------
#  The hyprland package ships TWO session files:
#      hyprland.desktop        -> start-hyprland          (works)
#      hyprland-uwsm.desktop   -> uwsm start -e -D ...    (does NOT work)
#  The second requires `programs.uwsm.enable = true`, which only comes on via
#  `programs.hyprland.withUWSM = true` (default: off). With it off, `uwsm` is
#  missing, the session dies within a second and you land back on VT1 — where
#  "Reached target Graphical Interface" is the last console line. A display
#  manager that remembers your last choice then keeps failing. So only the
#  working session is offered below.
################################################################################
{ config, pkgs, lib, ... }:

let
  wallpaper = import ./wallpaper.nix { inherit pkgs; };
  # The login screen gets the ultrawide render too, otherwise hyprpaper blows
  # the laptop-sized image up to cover it and login looks zoomed in and blurry.
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

  # Hand only hyprland.desktop to the display manager; the broken uwsm variant
  # is filtered out so it cannot be selected.
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

  # hyprpaper for the greeter user. The path points into the nix store, because
  # `greeter` has no access to /home/ogryson.
  # hyprpaper 0.8.x syntax — see the note at services.hyprpaper in
  # ./home/desktop.nix. The old `preload`/`wallpaper = ,path` form is silently
  # ignored, which leaves the login screen blank.
  # Same layout as services.hyprpaper in ./home/desktop.nix: first the screens
  # we know with their own render, then an empty monitor line as a fallback.
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

  # Bare Hyprland as the greeter compositor: no animations, no logo, no
  # keybinds. It starts hyprpaper for the background and ReGreet for the login
  # field; once ReGreet exits the compositor stops and greetd restarts.
  greeterHyprlandConf = pkgs.writeText "greeter-hyprland.conf" ''
    monitor = ,preferred,auto,1

    input {
      kb_layout = be
      kb_model  = pc105
      kb_options = caps:digits_row
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

  # ReGreet looks for session files in $XDG_DATA_DIRS/{wayland-sessions,
  # xsessions} and otherwise falls back to /usr/share/... — which does not exist
  # on NixOS, leaving the session dropdown empty and login impossible. So point
  # it explicitly at the path the displayManager module assembles.
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
  #### Keep SDDM off ###########################################################
  # mkForce so that this wins no matter what else in the tree enables it.
  services.displayManager.sddm.enable = lib.mkForce false;

  #### Offer only the working Hyprland session ################################
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
    # Same cursor as the session (home/desktop.nix), so the pointer does not
    # jump the moment you log in.
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

      # ReGreet draws the background itself as well. hyprpaper above does the
      # real work; this is the fallback layer for when the GTK window turns out
      # not to be translucent. Same file, so the wallpaper matches either way.
      background = {
        path = "${wallpaper}";
        fit = "Cover";
      };
    };

    # Note: ReGreet 0.4 builds its UI programmatically (relm4, no .ui
    # templates), so there are no stable id selectors such as #main-box. Only
    # generic GTK4 nodes below — those are guaranteed to match.
    # Colours come from ./theme.nix, the same palette as waybar/mako/hyprlock.
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

  #### greetd: ReGreet in Hyprland instead of the default `cage` ##############
  # The regreet module sets this with mkDefault, so a plain assignment wins.
  services.greetd.settings.default_session.command = "${greeterLauncher}";

  # In the greeter session Hyprland needs access to the GPU and to input.
  users.users.greeter.extraGroups = [
    "video"
    "input"
  ];
}
