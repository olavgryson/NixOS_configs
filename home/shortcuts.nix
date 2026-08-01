################################################################################
#  Hyprland keyboard & mouse shortcuts (keybindings).
################################################################################
{ pkgs, lib, ... }:
let
  # Lid closed: turn the laptop panel off, BUT only if another screen remains.
  # Without that check, closing the lid on the road would switch off your only
  # screen and leave you in the dark with a running session. `hyprctl monitors`
  # (without `all`) lists only enabled screens, so counting them is enough.
  lidClose = pkgs.writeShellScript "lid-close" ''
    others=$(${pkgs.hyprland}/bin/hyprctl -j monitors \
      | ${pkgs.jq}/bin/jq '[.[] | select(.name != "eDP-1")] | length')
    if [ "''${others:-0}" -gt 0 ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1,disable"
    fi
  '';

  laptopMonitor = "eDP-1,1920x1280@60,760x1440,1";

  # Lid opened: panel back. If it was still on (because lidClose above never
  # switched it off) this is a no-op that just re-applies the same layout.
  lidOpen = pkgs.writeShellScript "lid-open" ''
    ${pkgs.hyprland}/bin/hyprctl keyword monitor "${laptopMonitor}"
  '';

  # ── Re-apply the lid state after a config reload ──────────────────────────
  # `hyprctl keyword monitor "eDP-1,disable"` from lidClose above is RUNTIME
  # state; the `monitor =` list in ./desktop.nix is the config. Hyprland
  # auto-reloads that config whenever the file changes, and `rebuild` changes it
  # on every switch (home-manager repoints ~/.config/hypr/hyprland.conf at a new
  # store path). The reload re-applies `eDP-1,1920x1280@60,760x1440,1` verbatim,
  # so the panel comes back even with the lid shut — and Hyprland hands the
  # workspaces that had fallen onto the external ultrawide straight back to it.
  # Result: a window sitting on a screen you cannot see, until you cycle the lid
  # by hand.
  #
  # This runs via `exec` (not `exec-once`): exec fires again on every reload,
  # which is exactly the moment the state gets clobbered. It reconciles config
  # back to reality — lid shut and another screen present means the panel goes
  # off again, and the workspaces follow it back to the ultrawide.
  #
  # Same wait loop as the greeter (see ./../greeter.nix): at session start the
  # external screen arrives over MST a moment after Hyprland (its name changes
  # per plug, too), and disabling eDP-1 before it is
  # there would leave zero outputs. On the road the loop times out and the panel
  # simply stays on.
  lidSync = pkgs.writeShellScript "lid-sync" ''
    ${pkgs.gnugrep}/bin/grep -qi closed /proc/acpi/button/lid/*/state 2>/dev/null || exit 0

    others() {
      ${pkgs.hyprland}/bin/hyprctl -j monitors \
        | ${pkgs.jq}/bin/jq '[.[] | select(.name != "eDP-1")] | length'
    }

    for _ in $(${pkgs.coreutils}/bin/seq 1 25); do
      [ "$(others)" -gt 0 ] && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    if [ "$(others)" -gt 0 ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1,disable"
    fi
  '';

  # Screenshot van het actieve venster. Als los script omdat de geometrie een
  # komma bevat ("x,y BxH") en Hyprland zijn bind-regels op komma's splitst.
  screenshotWindow = pkgs.writeShellScript "screenshot-window" ''
    geom=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    grim -g "$geom" - | swappy -f -
  '';

  # Volume control script sending Bellotto gallery-style OSD notifications with percentage
  volumeControl = pkgs.writeShellScript "volume-control" ''
    action="$1"
    case "$action" in
      up)
        ${pkgs.pamixer}/bin/pamixer --unmute --increase 2 --set-limit 100
        ;;
      down)
        ${pkgs.pamixer}/bin/pamixer --decrease 2
        ;;
      mute)
        ${pkgs.pamixer}/bin/pamixer --toggle-mute
        ;;
      mic-mute)
        ${pkgs.pamixer}/bin/pamixer --default-source --toggle-mute
        ;;
    esac

    if [ "$action" = "mic-mute" ]; then
      is_muted=$(${pkgs.pamixer}/bin/pamixer --default-source --get-mute)
      if [ "$is_muted" = "true" ]; then
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:mic -h int:value:0 -a "Microphone" "Microphone" "<b>Muted (0%)</b>" -i microphone-sensitivity-muted
      else
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:mic -h int:value:100 -a "Microphone" "Microphone" "<b>Active (100%)</b>" -i audio-input-microphone
      fi
    else
      vol=$(${pkgs.pamixer}/bin/pamixer --get-volume)
      is_muted=$(${pkgs.pamixer}/bin/pamixer --get-mute)
      if [ "$is_muted" = "true" ]; then
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:volume -h int:value:0 -a "Volume" "Volume" "<b>Muted (0%)</b>" -i audio-volume-muted
      else
        icon="audio-volume-high"
        if [ "$vol" -lt 33 ]; then
          icon="audio-volume-low"
        elif [ "$vol" -lt 66 ]; then
          icon="audio-volume-medium"
        fi
        ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:volume -h int:value:"$vol" -a "Volume" "Volume" "<b>''${vol}%</b>" -i "$icon"
      fi
    fi
  '';

  # Brightness control script sending Bellotto gallery-style OSD notifications with percentage
  brightnessControl = pkgs.writeShellScript "brightness-control" ''
    action="$1"
    ext_out=$(${pkgs.systemd}/bin/busctl --user tree rs.wl-gammarelay 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's|.*/outputs/||p' | ${pkgs.gnugrep}/bin/grep -v '^eDP_1$' | ${pkgs.coreutils}/bin/head -1 || true)
    
    if [ -n "$ext_out" ]; then
      cur=$(${pkgs.systemd}/bin/busctl --user get-property rs.wl-gammarelay "/outputs/$ext_out" rs.wl.gammarelay Brightness 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}' || echo 1.0)
      if [ "$action" = "up" ]; then
        nval=$(${pkgs.gawk}/bin/awk -v c="$cur" 'BEGIN{v=c+0.05; if(v>1)v=1; printf "%.2f", v}')
      else
        nval=$(${pkgs.gawk}/bin/awk -v c="$cur" 'BEGIN{v=c-0.05; if(v<0.1)v=0.1; printf "%.2f", v}')
      fi
      ${pkgs.systemd}/bin/busctl --user set-property rs.wl-gammarelay "/outputs/$ext_out" rs.wl.gammarelay Brightness d "$nval" 2>/dev/null || true
      val=$(${pkgs.gawk}/bin/awk -v c="$nval" 'BEGIN{printf "%d", c*100+0.5}')
      ${pkgs.procps}/bin/pkill -RTMIN+8 waybar 2>/dev/null || true
    else
      case "$action" in
        up)   ${pkgs.brightnessctl}/bin/brightnessctl set +5% ;;
        down) ${pkgs.brightnessctl}/bin/brightnessctl set 5%- -m ;;
      esac
      val=$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.coreutils}/bin/cut -d',' -f4 | ${pkgs.coreutils}/bin/tr -d '%')
    fi

    ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:brightness -h int:value:"''${val:-0}" -a "Brightness" "Brightness" "<b>''${val:-0}%</b>" -i display-brightness
  '';
in
{
  wayland.windowManager.hyprland.settings = {
    # Runs on startup AND on every config reload — see the lidSync comment above.
    exec = [ "${lidSync}" ];

    # ── Modifier-schema, zodat je het kunt onthouden zonder spiekbriefje ──
    #   $mod              + pijl  = focus verplaatsen
    #   $mod SHIFT        + pijl  = venster verplaatsen (of in een tabgroep)
    #   $mod CTRL         + pijl  = workspace vooruit/achteruit
    #   $mod ALT          + pijl  = tab wisselen bínnen een groep
    #   $mod CTRL SHIFT   + pijl  = venster van formaat veranderen
    bind = [
      # ── Programma's ────────────────────────────────────────────────────
      "$mod, Return, exec, $term"
      "$mod SHIFT, Return, exec, [float; size 900 600] $term"
      "$mod, E, exec, $files"
      # Programmastarter staat op $mod+Space (was $mod+R, en was wofi).
      "$mod, Space, exec, $menu"
      "$mod SHIFT, R, exec, wofi --show run"
      "$mod, B, exec, $browser"      # Zen browser
      "$mod SHIFT, B, exec, $browser --private-window" # Zen browser (private window)
      "$mod SHIFT, P, exec, $browser --private-window" # Zen browser (private window)
      "$mod, L, exec, hyprlock"
      "$mod, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
      # Afmelden zat op $mod+M. Op AZERTY ligt M pal naast L, dus één toets
      # mis bij $mod+L (vergrendelen) gooide je hele sessie weg. Nu met SHIFT.
      "$mod SHIFT, M, exit,"

      # ── Vensters ───────────────────────────────────────────────────────
      "$mod, W, killactive,"
      "$mod SHIFT, W, forcekillactive,"   # voor een vastgelopen venster
      "$mod, R, togglefloating,"
      "$mod, C, centerwindow,"
      "$mod, F, fullscreen, 0"            # echt volledig scherm
      "$mod SHIFT, F, fullscreen, 1"      # maximaliseren, waybar blijft zichtbaar
      # Splitsrichting omdraaien is in dwindle géén dispatcher maar een
      # layoutmsg — "togglesplit" als dispatcher bestaat niet.
      "$mod, X, layoutmsg, togglesplit"
      "$mod, P, pseudo,"

      # ── Tabs (Hyprland noemt dit groepen) ──────────────────────────────
      # $mod+G maakt van het huidige venster een tabgroep; sleep er daarna
      # vensters in met $mod SHIFT + pijl.
      "$mod, G, togglegroup,"
      "$mod ALT, right, changegroupactive, f"
      "$mod ALT, left, changegroupactive, b"

      # ── Focus ──────────────────────────────────────────────────────────
      "$mod, left, movefocus, l"
      "$mod, right, movefocus, r"
      "$mod, up, movefocus, u"
      "$mod, down, movefocus, d"

      # ── Venster verplaatsen ────────────────────────────────────────────
      # movewindoworgroup i.p.v. movewindow: schuift het venster op, maar
      # laat het ín een tabgroep vallen als de buurman er een is.
      "$mod SHIFT, left, movewindoworgroup, l"
      "$mod SHIFT, right, movewindoworgroup, r"
      "$mod SHIFT, up, movewindoworgroup, u"
      "$mod SHIFT, down, movewindoworgroup, d"

      # ── Workspaces ─────────────────────────────────────────────────────
      "$mod CTRL, right, workspace, e+1"
      "$mod CTRL, left, workspace, e-1"
      "$mod, Tab, workspace, previous"          # heen en weer springen
      "$mod, mouse_down, workspace, e+1"        # $mod + scrollen
      "$mod, mouse_up, workspace, e-1"
      # Nieuwe, lege workspace — en hetzelfde mét het huidige venster erbij.
      "$mod, N, workspace, empty"
      "$mod SHIFT, N, movetoworkspace, empty"
      # Scratchpad: één workspace die je over alles heen in/uit klapt.
      "$mod, S, togglespecialworkspace, magic"
      "$mod SHIFT, S, movetoworkspace, special:magic"

      # ── Screenshots ────────────────────────────────────────────────────
      ", Print, exec, grim -g \"$(slurp)\" - | swappy -f -"   # selectie -> bewerken
      "$mod, Print, exec, ${screenshotWindow}"                # actief venster
      "CTRL, Print, exec, grim -g \"$(slurp)\" - | wl-copy"   # selectie -> klembord
      "SHIFT, Print, exec, grim - | wl-copy"                  # heel scherm -> klembord
    ]
    # Workspace 1..10 op de cijferrij.
    #
    # LET OP — dit stond fout in je oude config. Er stond "$mod, 1, ...", dus
    # Hyprland bond op het keysym `1`. Op Belgisch AZERTY geeft die toets
    # onbeschud `ampersand`; `1` krijg je pas mét Shift. `hyprctl binds`
    # bevestigde het: `key: 1, keycode: 0`. Binden op de keycode van de
    # fysieke toets (AE01 = 10 ... AE10 = 19) werkt ongeacht layout of niveau.
    ++ (builtins.concatLists (builtins.genList (i:
      let
        ws = toString (i + 1);
        key = "code:${toString (i + 10)}";
      in [
        "$mod, ${key}, workspace, ${ws}"
        "$mod SHIFT, ${key}, movetoworkspace, ${ws}"
      ]) 10));

    # Venster slepen/schalen met de muis (of touchpad) + $mod.
    bindm = [
      "$mod, mouse:272, movewindow"     # linkerknop slepen = verplaatsen
      "$mod, mouse:273, resizewindow"   # rechterknop slepen = schalen
    ];

    bindel = [
      # Formaat wijzigen met het toetsenbord; herhaalt zolang je indrukt.
      "$mod CTRL SHIFT, right, resizeactive, 40 0"
      "$mod CTRL SHIFT, left, resizeactive, -40 0"
      "$mod CTRL SHIFT, down, resizeactive, 0 40"
      "$mod CTRL SHIFT, up, resizeactive, 0 -40"

      # Volume and brightness controls with Bellotto theme gallery plaque OSD popups
      ", XF86AudioRaiseVolume, exec, ${volumeControl} up"
      ", XF86AudioLowerVolume, exec, ${volumeControl} down"
      ", XF86AudioMute, exec, ${volumeControl} mute"
      ", XF86AudioMicMute, exec, ${volumeControl} mic-mute"
      ", XF86MonBrightnessUp, exec, ${brightnessControl} up"
      ", XF86MonBrightnessDown, exec, ${brightnessControl} down"
    ];

    bindl = [
      ", XF86AudioPlay, exec, swayosd-client --playerctl play-pause"
      ", XF86AudioNext, exec, swayosd-client --playerctl next"
      ", XF86AudioPrev, exec, swayosd-client --playerctl prev"

      # ── Lid closed = keep working on the ultrawide ─────────────────────
      # `bindl` (l = lock) is the only bind type that still fires while the
      # screen is locked; with a plain `bind` nothing happened once hyprlock was
      # in front. The name "Lid Switch" comes verbatim from `hyprctl devices`.
      #
      # Disabling eDP-1 does the moving by itself: Hyprland shifts the
      # workspaces of a disappearing screen onto a remaining one, windows and
      # all. That is why nothing here has to move windows individually.
      ", switch:on:Lid Switch, exec, ${lidClose}"
      ", switch:off:Lid Switch, exec, ${lidOpen}"
    ];
  };
}
