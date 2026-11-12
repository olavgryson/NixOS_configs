################################################################################
#  Hyprland keyboard & mouse shortcuts (keybindings).
################################################################################
{ pkgs, lib, config, ... }:
let
  homeDir = config.home.homeDirectory;
  monitors = import ./desktop/monitors.nix { inherit pkgs; };
  inherit (monitors) laptopMonitor enableMonitorLua disableMonitorLua;
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  # Lid closed: turn the laptop panel off, BUT only if another screen remains.
  # Without that check, closing the lid on the road would switch off your only
  # screen and leave you in the dark with a running session. `hyprctl monitors`
  # (without `all`) lists only enabled screens, so counting them is enough.
  lidClose = pkgs.writeShellScript "lid-close" ''
    others=$(${pkgs.hyprland}/bin/hyprctl -j monitors \
      | ${pkgs.jq}/bin/jq '[.[] | select(.name != "eDP-1")] | length')
    if [ "''${others:-0}" -gt 0 ]; then
      ${hyprctl} eval '${disableMonitorLua laptopMonitor.output}'
    fi
  '';

  # Lid opened: panel back. If it was still on (because lidClose above never
  # switched it off) this is a no-op that just re-applies the same layout.
  lidOpen = pkgs.writeShellScript "lid-open" ''
    ${hyprctl} eval '${enableMonitorLua laptopMonitor}'
  '';

  # ── Re-apply the lid state after a config reload ──────────────────────────
  # The `hl.monitor` call that lidClose above evals is RUNTIME state; the
  # monitor list in ./desktop/wm.nix is the config. Hyprland
  # auto-reloads that config whenever the file changes, and `rebuild` changes it
  # on every switch (home-manager repoints ~/.config/hypr/hyprland.lua at a new
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
      ${hyprctl} eval '${disableMonitorLua laptopMonitor.output}'
    fi
  '';

  # Screenshot of the active window. A separate script because the geometry
  # contains a comma ("x,y WxH") that would need escaping inside a bind.
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

  # ── Bind helpers ──────────────────────────────────────────────────────────
  # Hyprland 0.57 binds are Lua: hl.bind("SUPER + Q", <dispatcher>, { opts }).
  # `toLua` quotes a Nix string as a Lua string literal.
  toLua = lib.generators.toLua { };
  mkLuaInline = lib.generators.mkLuaInline;
  term = "kitty";
  menu = "rofi -show drun";
  # The zen flake installs the binary as `zen-beta`, not `zen`; with "zen"
  # the $mod+B bind silently does nothing.
  browser = "zen-beta";
  files = "nautilus";

  exec = cmd: "hl.dsp.exec_cmd(${toLua cmd})";
  bindWith = opts: key: dispatcher: {
    _args = [ key (mkLuaInline dispatcher) ] ++ lib.optional (opts != { }) opts;
  };
  bind = bindWith { };
  # `bindl`: also fires while the screen is locked.
  bindl = bindWith { locked = true; };
  # `bindel`: locked, and repeats while the key is held.
  bindel = bindWith { locked = true; repeating = true; };
  bindm = bindWith { mouse = true; };

  resize = x: y: "hl.dsp.window.resize({ x = ${toString x}, y = ${toString y}, relative = true })";

in
{
  wayland.windowManager.hyprland.settings = {
    # Runs on startup AND on every config reload — see the lidSync comment above.
    on = [
      {
        _args = [
          "hyprland.start"
          (mkLuaInline "function() hl.exec_cmd(${toLua "${lidSync}"}) end")
        ];
      }
      {
        _args = [
          "config.reloaded"
          (mkLuaInline "function() hl.exec_cmd(${toLua "${lidSync}"}) end")
        ];
      }
    ];

    # ── Modifier scheme, memorable without a cheat sheet ──────────────────
    #   SUPER              + arrow = move focus
    #   SUPER SHIFT        + arrow = move window (or into a tab group)
    #   SUPER CTRL         + arrow = workspace forward/back
    #   SUPER ALT          + arrow = switch tab within a group
    #   SUPER CTRL SHIFT   + arrow = resize window
    bind = [
      # ── Applications ───────────────────────────────────────────────────
      (bind "SUPER + Return" (exec term))
      (bind "SUPER + SHIFT + Return" "hl.dsp.exec_cmd(${toLua term}, { float = true, size = \"900 600\" })")
      (bind "SUPER + E" (exec files))
      # App launcher on SUPER+Space.
      (bind "SUPER + Space" (exec menu))
      (bind "SUPER + SHIFT + R" (exec "wofi --show run"))
      (bind "SUPER + B" (exec browser))                                   # Zen browser
      (bind "SUPER + SHIFT + B" (exec "${cyclePowerProfile}"))            # cycle power profile
      (bind "SUPER + SHIFT + P" (exec "${browser} --private-window"))     # Zen browser (private window)
      (bind "SUPER + L" (exec "hyprlock"))
      (bind "SUPER + V" (exec "cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
      # Log out. Deliberately on SHIFT: on AZERTY, M sits right next to L, so
      # a single missed key on SUPER+L (lock) would throw away the session.
      (bind "SUPER + SHIFT + M" "hl.dsp.exit()")

      # ── Windows ────────────────────────────────────────────────────────
      (bind "SUPER + W" "hl.dsp.window.close()")
      (bind "SUPER + SHIFT + W" "hl.dsp.window.kill()")                   # for a hung window
      (bind "SUPER + R" "hl.dsp.window.float({ action = \"toggle\" })")
      (bind "SUPER + C" "hl.dsp.window.center()")
      (bind "SUPER + F" "hl.dsp.window.fullscreen({ mode = \"fullscreen\" })")  # true fullscreen
      (bind "SUPER + SHIFT + F" "hl.dsp.window.fullscreen({ mode = \"maximized\" })") # maximise, waybar stays visible
      # Flipping the split direction is a layout message in dwindle.
      (bind "SUPER + X" "hl.dsp.layout(\"togglesplit\")")
      (bind "SUPER + P" "hl.dsp.window.pseudo()")

      # ── Tabs (Hyprland calls these groups) ─────────────────────────────
      # SUPER+G turns the current window into a tab group; drag windows into it
      # afterwards with SUPER SHIFT + arrow.
      (bind "SUPER + G" "hl.dsp.group.toggle()")
      (bind "SUPER + ALT + right" "hl.dsp.group.next()")
      (bind "SUPER + ALT + left" "hl.dsp.group.prev()")

      # ── Focus ──────────────────────────────────────────────────────────
      (bind "SUPER + left" "hl.dsp.focus({ direction = \"left\" })")
      (bind "SUPER + right" "hl.dsp.focus({ direction = \"right\" })")
      (bind "SUPER + up" "hl.dsp.focus({ direction = \"up\" })")
      (bind "SUPER + down" "hl.dsp.focus({ direction = \"down\" })")

      # ── Move window ────────────────────────────────────────────────────
      # group_aware: moves the window across, but drops it into a tab group if
      # the neighbour is one.
      (bind "SUPER + SHIFT + left" "hl.dsp.window.move({ direction = \"left\", group_aware = true })")
      (bind "SUPER + SHIFT + right" "hl.dsp.window.move({ direction = \"right\", group_aware = true })")
      (bind "SUPER + SHIFT + up" "hl.dsp.window.move({ direction = \"up\", group_aware = true })")
      (bind "SUPER + SHIFT + down" "hl.dsp.window.move({ direction = \"down\", group_aware = true })")

      # ── Workspaces ─────────────────────────────────────────────────────
      (bind "SUPER + CTRL + right" "hl.dsp.focus({ workspace = \"e+1\" })")
      (bind "SUPER + CTRL + left" "hl.dsp.focus({ workspace = \"e-1\" })")
      (bind "SUPER + CTRL + SHIFT + right" "hl.dsp.window.move({ workspace = \"e+1\" })") # Move window to next workspace
      (bind "SUPER + CTRL + SHIFT + left" "hl.dsp.window.move({ workspace = \"e-1\" })")  # Move window to previous workspace
      (bind "SUPER + Tab" "hl.dsp.focus({ workspace = \"previous\" })")  # jump back and forth
      (bind "SUPER + mouse_down" "hl.dsp.focus({ workspace = \"e+1\" })") # SUPER + scroll
      (bind "SUPER + mouse_up" "hl.dsp.focus({ workspace = \"e-1\" })")
      # New empty workspace — and the same, taking the current window along.
      (bind "SUPER + N" "hl.dsp.focus({ workspace = \"empty\" })")
      (bind "SUPER + SHIFT + N" "hl.dsp.window.move({ workspace = \"empty\" })")
      # Scratchpad: one workspace that folds in and out over everything else.
      (bind "SUPER + S" "hl.dsp.workspace.toggle_special(\"magic\")")
      (bind "SUPER + SHIFT + S" "hl.dsp.window.move({ workspace = \"special:magic\" })")

      # ── Screenshots ────────────────────────────────────────────────────
      (bind "Print" (exec ''grim -g "$(slurp)" - | swappy -f -''))        # selection -> edit
      (bind "SUPER + Print" (exec "${screenshotWindow}"))                 # active window
      (bind "CTRL + Print" (exec ''grim -g "$(slurp)" - | wl-copy''))     # selection -> clipboard
      (bind "SHIFT + Print" (exec "grim - | wl-copy"))                    # whole screen -> clipboard

      # ── Voice dictation (fully local) ──────────────────────────────────
      # Whisper large-v3-turbo on the GPU, Dutch, in two modes.
      # SUPER+F5 toggles live mode: text appears per sentence, as you speak.
      # SUPER+F7 records; press again to transcribe the whole take at once.
      # F7 is the accurate one — it gives Whisper the full utterance as
      # context, where live mode only ever sees the last few seconds.
      (bind "SUPER + F5" (exec "${homeDir}/.local/dict/stream-dict.sh"))
      (bind "SUPER + F7" (exec "${homeDir}/.local/dict/whisper-dict.sh"))
    ]
    # Workspace 1..10 on the number row.
    #
    # NOTE: bind on the KEYCODE, not the keysym. `SUPER + 1` makes Hyprland
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
        (bind "SUPER + ${key}" "hl.dsp.focus({ workspace = ${ws} })")
        (bind "SUPER + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${ws} })")
      ]) 10))
    ++ [
      # Drag/resize windows with the mouse (or touchpad) + SUPER.
      (bindm "SUPER + mouse:272" "hl.dsp.window.drag()")     # drag with left button = move
      (bindm "SUPER + mouse:273" "hl.dsp.window.resize()")   # drag with right button = resize

      # Resize from the keyboard; repeats while held.
      (bindel "SUPER + CTRL + SHIFT + right" (resize 40 0))
      (bindel "SUPER + CTRL + SHIFT + left" (resize (-40) 0))
      (bindel "SUPER + CTRL + SHIFT + down" (resize 0 40))
      (bindel "SUPER + CTRL + SHIFT + up" (resize 0 (-40)))

      # Volume and brightness controls with Bellotto theme gallery plaque OSD popups
      (bindel "XF86AudioRaiseVolume" (exec "${volumeControl} up"))
      (bindel "XF86AudioLowerVolume" (exec "${volumeControl} down"))
      (bindel "XF86AudioMute" (exec "${volumeControl} mute"))
      (bindel "XF86AudioMicMute" (exec "${volumeControl} mic-mute"))
      (bindel "XF86MonBrightnessUp" (exec "${brightnessControl} up"))
      (bindel "XF86MonBrightnessDown" (exec "${brightnessControl} down"))

      (bindl "XF86AudioPlay" (exec "swayosd-client --playerctl play-pause"))
      (bindl "XF86AudioNext" (exec "swayosd-client --playerctl next"))
      (bindl "XF86AudioPrev" (exec "swayosd-client --playerctl prev"))

      # ── Lid closed = keep working on the ultrawide ─────────────────────
      # `locked` is the only bind flavour that still fires while the screen is
      # locked; with a plain bind nothing happened once hyprlock was in front.
      # The name "Lid Switch" comes verbatim from `hyprctl devices`.
      #
      # Disabling eDP-1 does the moving by itself: Hyprland shifts the
      # workspaces of a disappearing screen onto a remaining one, windows and
      # all. That is why nothing here has to move windows individually.
      (bindl "switch:on:Lid Switch" (exec "${lidClose}"))
      (bindl "switch:off:Lid Switch" (exec "${lidOpen}"))
    ];
  };
}
