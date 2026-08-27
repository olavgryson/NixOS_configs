################################################################################
#  Hyprland keyboard & mouse shortcuts (keybindings).
################################################################################
{ pkgs, lib, config, hostName, ... }:
let
  homeDir = config.home.homeDirectory;
  monitors = import ./desktop/monitors.nix { inherit pkgs hostName; };
  inherit (monitors) laptopMonitor;
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

  # Screenshot of the active window. A separate script because the geometry
  # contains a comma ("x,y WxH") and Hyprland splits bind lines on commas.
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

  # Searchable cheat sheet of every active keybinding. hyprctl reports modmask
  # numbers (bitfield: SHIFT=1 CTRL=4 ALT=8 SUPER=64); jq turns them into names
  # so the list reads like documentation instead of a bitmask dump. Plain
  # dmenu mode: picking an entry just prints it, which we discard.
  # -theme: the runtime palette copy (see ./desktop/theme-switch.nix), so the sheet matches whatever theme is active.
  keybindCheatSheet = pkgs.writeShellScript "keybinding-cheatsheet" ''
    ${pkgs.hyprland}/bin/hyprctl binds -j \
      | ${pkgs.jq}/bin/jq -r '
          def mods($m): [
            (if ($m/64|floor)%2==1 then "SUPER" else empty end),
            (if ($m/4|floor)%2==1  then "CTRL" else empty end),
            (if ($m/8|floor)%2==1  then "ALT"  else empty end),
            (if $m%2==1            then "SHIFT" else empty end)
          ] | join("+");
          [.[] |
            (mods(.modmask)
             + (if .modmask > 0 then "+" else "" end)
             + .key + "  -  "
             + (if .description == ""
                then (.dispatcher + " " + .arg)
                else .description end))]
          | sort | join("\n")' \
      | ${pkgs.rofi}/bin/rofi -dmenu -i -p Keybindings \
          -theme ${homeDir}/.config/theme/rofi.rasi >/dev/null
  '';

  # AI agent terminal in its own special workspace. The client check makes the
  # bind idempotent-ish: if the scratchpad was closed but kitty survived (or
  # vice versa), pressing the key again relaunches or just re-reveals instead
  # of stacking a second instance. togglespecialworkspace then shows/hides it,
  # so the same key both opens and dismisses.
  agentScratchpad = pkgs.writeShellScript "agent-scratchpad" ''
    if ! ${pkgs.hyprland}/bin/hyprctl clients -j \
         | ${pkgs.jq}/bin/jq -e 'any(.[]; .class == "agent-scratchpad")' >/dev/null; then
      ${pkgs.kitty}/bin/kitty --class agent-scratchpad agy &
    fi
    ${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace agent
  '';

  # Cycles the power profile performance -> balanced -> power-saver and wraps
  # around. The waybar `power-profiles-daemon` module follows via DBus, so no
  # signal is needed; the notification is so the switch is visible without the
  # bar.
  cyclePowerProfile = pkgs.writeShellScript "cycle-power-profile" ''
    set -eu
    current=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)
    case "$current" in
      power-saver) next="balanced" ;;
      balanced)    next="performance" ;;
      *)           next="power-saver" ;;
    esac
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$next"
    ${pkgs.libnotify}/bin/notify-send -a "Power Profile" "Power Profile" "<b>$next</b>"
  '';
in
{
  wayland.windowManager.hyprland.settings = {
    # Runs on startup AND on every config reload — see the lidSync comment above.
    exec = [ "${lidSync}" ];

    # ── Modifier scheme, memorable without a cheat sheet ──────────────────
    #   $mod              + arrow = move focus
    #   $mod SHIFT        + arrow = move window (or into a tab group)
    #   $mod CTRL         + arrow = workspace forward/back
    #   $mod ALT          + arrow = switch tab within a group
    #   $mod CTRL SHIFT   + arrow = resize window
    #
    # `bindd` (described binds) carries a human-readable description per bind;
    # the cheat-sheet script above reads those back via `hyprctl binds -j`.
    # Description sits between the key and the dispatcher.
    bindd = [
      # ── Applications ───────────────────────────────────────────────────
      "$mod, Return, Terminal, exec, $term"
      "$mod SHIFT, Return, Terminal (floating), exec, [float; size 900 600] $term"
      "$mod, E, File manager, exec, $files"
      # App launcher on $mod+Space.
      "$mod, Space, App launcher, exec, $menu"
      "$mod SHIFT, R, Run dialog, exec, wofi --show run"
      "$mod, B, Web browser, exec, $browser"      # Zen browser
      "$mod SHIFT, B, Cycle power profile, exec, ${cyclePowerProfile}"
      "$mod SHIFT, P, Private browser window, exec, $browser --private-window" # Zen private
      "$mod, L, Lock screen, exec, hyprlock"
      "$mod, V, Clipboard history, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
      # Log out. Deliberately on SHIFT: on AZERTY, M sits right next to L, so
      # a single missed key on $mod+L (lock) would throw away the session.
      "$mod SHIFT, M, Log out, exit,"

      # ── Windows ────────────────────────────────────────────────────────
      "$mod, W, Close window, killactive,"
      "$mod SHIFT, W, Force close window, forcekillactive,"   # for a hung window
      "$mod, R, Toggle float, togglefloating,"
      "$mod, C, Center window, centerwindow,"
      "$mod, F, Fullscreen, fullscreen, 0"            # true fullscreen
      "$mod SHIFT, F, Maximise (keep bar), fullscreen, 1"     # maximise, waybar stays visible
      # Flipping the split direction is a layoutmsg in dwindle, not a
      # dispatcher — "togglesplit" as a dispatcher does not exist.
      "$mod, X, Toggle split direction, layoutmsg, togglesplit"
      "$mod, P, Pseudo-tile, pseudo,"

      # ── Tabs (Hyprland calls these groups) ─────────────────────────────
      # $mod+G turns the current window into a tab group; drag windows into it
      # afterwards with $mod SHIFT + arrow.
      "$mod, G, Toggle tab group, togglegroup,"
      "$mod ALT, right, Next tab in group, changegroupactive, f"
      "$mod ALT, left, Previous tab in group, changegroupactive, b"

      # ── Focus ──────────────────────────────────────────────────────────
      "$mod, left, Focus left, movefocus, l"
      "$mod, right, Focus right, movefocus, r"
      "$mod, up, Focus up, movefocus, u"
      "$mod, down, Focus down, movefocus, d"

      # ── Move window ────────────────────────────────────────────────────
      # movewindoworgroup instead of movewindow: moves the window across, but
      # drops it into a tab group if the neighbour is one.
      "$mod SHIFT, left, Move window left, movewindoworgroup, l"
      "$mod SHIFT, right, Move window right, movewindoworgroup, r"
      "$mod SHIFT, up, Move window up, movewindoworgroup, u"
      "$mod SHIFT, down, Move window down, movewindoworgroup, d"

      # ── Workspaces ─────────────────────────────────────────────────────
      "$mod CTRL, right, Workspace forward, workspace, e+1"
      "$mod CTRL, left, Workspace back, workspace, e-1"
      "$mod CTRL SHIFT, right, Move to next workspace, movetoworkspace, e+1"
      "$mod CTRL SHIFT, left, Move to previous workspace, movetoworkspace, e-1"
      "$mod, Tab, Previous workspace, workspace, previous"          # jump back and forth
      "$mod, mouse_down, Next workspace (scroll), workspace, e+1"   # $mod + scroll
      "$mod, mouse_up, Previous workspace (scroll), workspace, e-1"
      # New empty workspace — and the same, taking the current window along.
      "$mod, N, Go to empty workspace, workspace, empty"
      "$mod SHIFT, N, Move to empty workspace, movetoworkspace, empty"
      # Scratchpad: one workspace that folds in and out over everything else.
      "$mod, S, Toggle scratchpad, togglespecialworkspace, magic"
      "$mod SHIFT, S, Move to scratchpad, movetoworkspace, special:magic"

      # ── AI agent scratchpad ────────────────────────────────────────────
      "$mod, A, AI agent scratchpad, exec, ${agentScratchpad}"

      # ── Cheat sheet ────────────────────────────────────────────────────
      # Bound twice: on Belgian AZERTY slash needs Shift on some layouts/
      # apps, so both chords hit the same script; harmless duplication.
      "$mod, slash, Keybinding cheat sheet, exec, ${keybindCheatSheet}"
      "$mod SHIFT, slash, Keybinding cheat sheet, exec, ${keybindCheatSheet}"

      # ── Screenshots ────────────────────────────────────────────────────
      ", Print, Screenshot selection, exec, grim -g \"$(slurp)\" - | swappy -f -"   # selection -> edit
      "$mod, Print, Screenshot active window, exec, ${screenshotWindow}"            # active window
      "CTRL, Print, Screenshot selection to clipboard, exec, grim -g \"$(slurp)\" - | wl-copy"
      "SHIFT, Print, Screenshot screen to clipboard, exec, grim - | wl-copy"

      # ── Voice dictation (fully local) ──────────────────────────────────
      # Vosk (streaming): $mod+F5 starts, $mod+F6 stops and types as you go.
      # Whisper (toggle): $mod+F7 records; press again to transcribe and type.
      "$mod, F5, Start dictation (Vosk), exec, ${homeDir}/.local/dict/vosk-begin.sh"
      "$mod, F6, Stop dictation (Vosk), exec, ${homeDir}/.local/dict/vosk-end.sh"
      "$mod, F7, Toggle dictation (Whisper), exec, ${homeDir}/.local/dict/whisper-dict.sh"
    ]
    # Workspace 1..10 on the number row.
    #
    # NOTE: bind on the KEYCODE, not the keysym. `"$mod, 1, ..."` makes Hyprland
    # bind the keysym `1`, but on Belgian AZERTY that key unshifted produces
    # `ampersand` — `1` only exists with Shift, and `hyprctl binds` then reports
    # `key: 1, keycode: 0`, i.e. a bind that never fires. The keycode of the
    # physical key (AE01 = 10 ... AE10 = 19) works regardless of layout or
    # level.
    ++ (builtins.concatLists (builtins.genList (i:
      let
        ws = toString (i + 1);
        key = "code:${toString (i + 10)}";
      in [
        "$mod, ${key}, workspace, ${ws}"
        "$mod SHIFT, ${key}, movetoworkspace, ${ws}"
      ]) 10));

    # Drag/resize windows with the mouse (or touchpad) + $mod.
    bindm = [
      "$mod, mouse:272, movewindow"     # drag with left button = move
      "$mod, mouse:273, resizewindow"   # drag with right button = resize
    ];

    bindel = [
      # Resize from the keyboard; repeats while held.
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
