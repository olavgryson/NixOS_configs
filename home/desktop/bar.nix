################################################################################
#  Status bar + display OSD: waybar, its helper scripts, the brightness popup and SwayOSD.
################################################################################
{ pkgs, lib, config, ... }:

let
  theme = import ../../theme.nix { };
  inherit (theme) raw css;

  #### External monitor brightness ###########################################
  # WHY NOT ddcutil / DDC-CI, the normal way to dim an external monitor: the Mi
  # Monitor hangs off a dock, and that dock speaks DisplayPort MST. You can see
  # the consequence in /sys/class/drm — the physical ports card1-DP-1..4 each
  # have an i2c bus (i2c-16..19, "AUX USBC1..4"), but nothing is plugged into
  # them. The screen arrives on card1-DP-6, a connector MST invents, and that
  # one has no i2c bus at all. No bus means no DDC/CI: `ddcutil detect` sees
  # only the laptop panel, and probing every bus by hand returns "No monitor
  # detected". That is a property of the dock, not something software can switch
  # on. Plug the monitor straight into a USB-C port and it becomes DP-1..4 WITH
  # a bus, and ddcutil works — which is why ddcutil is still in home.packages.
  #
  # What does work: the compositor's gamma ramp. wl-gammarelay-rs speaks the
  # wlr-gamma-control protocol and sets a per-output curve; Hyprland supports it.
  # Be clear about what this is — it dims the IMAGE, not the backlight. The lamp
  # in the monitor keeps burning just as bright, so black does not get blacker
  # and no power is saved. Fine for taking the edge off in the evening; if you
  # want the actual backlight down, the button on the monitor (or a direct
  # cable, see above) is the only real route.
  #
  # DBus quirk: object paths cannot contain "-", so output DP-6 is exposed as
  # /outputs/DP_6. Hence the underscore names coming out of `busctl tree`.
  brightnessExternal = pkgs.writeShellScript "brightness-external" ''
    set -eu
    PATH=${lib.makeBinPath [
      pkgs.systemd      # busctl
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
      pkgs.procps       # pkill, to nudge waybar into refreshing
      pkgs.coreutils
    ]}

    # Every output except the laptop panel. Written this way so a different or
    # a second external screen just works, without hardcoding DP-6.
    # This module handles ONLY external outputs: the laptop panel has its own
    # waybar `backlight` module (brightnessctl), so there is no brightnessctl
    # fallback here. With no external screen the status is empty and the module
    # disappears from the bar.
    outputs() {
      busctl --user tree rs.wl-gammarelay 2>/dev/null \
        | sed -n 's|.*/outputs/||p' \
        | grep -v '^eDP_1$' || true
    }

    # Brightness of the first external output, as a float in [0,1]. Exits 1
    # when there is no external screen at all.
    get() {
      first=$(outputs | head -1)
      [ -n "$first" ] || return 1
      busctl --user get-property rs.wl-gammarelay "/outputs/$first" \
        rs.wl.gammarelay Brightness 2>/dev/null | awk '{print $2}'
    }

    setall() {
      v=$(awk -v x="$1" 'BEGIN{ if(x<0.1)x=0.1; if(x>1)x=1; printf "%.2f", x }')
      for o in $(outputs); do
        busctl --user set-property rs.wl-gammarelay "/outputs/$o" \
          rs.wl.gammarelay Brightness d "$v" 2>/dev/null || true
      done
      pkill -RTMIN+8 waybar 2>/dev/null || true
    }

    case "''${1:-status}" in
      up)   setall "$(awk -v c="$(get || echo 0)" 'BEGIN{printf "%.2f", c+0.05}')" ;;
      down) setall "$(awk -v c="$(get || echo 0)" 'BEGIN{printf "%.2f", c-0.05}')" ;;
      set)  setall "$2" ;;
      status)
        if cur=$(get); then
          pct=$(awk -v c="$cur" 'BEGIN{printf "%d", c*100+0.5}')
          if   [ "$pct" -lt 40 ]; then icon="󰃞"
          elif [ "$pct" -lt 75 ]; then icon="󰃟"
          else                         icon="󰃠"
          fi
          printf '{"text":"%s  %d%%","tooltip":"External Display Brightness (%d%%)\\nClick for Sliders per display\\nScroll to adjust","class":"ext-brightness","percentage":%d}\n' \
            "$icon" "$pct" "$pct" "$pct"
        else
          printf '{"text":"","tooltip":""}\n'
        fi
        ;;
    esac
  '';
  # ── Removable-media status (waybar module, replaces udiskie's tray icon) ──
  # udiskie's own tray icon is a themed bitmap that doesn't match the rest of
  # the bar (all Nerd Font glyphs, no image icons — see network/bluetooth/
  # battery above). This reports mounted removable drives the same way
  # custom/brightness reports brightness: JSON on stdout, refreshed by signal
  # rather than polling.
  diskStatus = pkgs.writeShellScript "disk-status" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.util-linux pkgs.gnugrep pkgs.gawk pkgs.coreutils ]}

    removable=$(lsblk -rno RM,MOUNTPOINT,LABEL,NAME | awk '$1=="1" && $2!=""')
    count=$(printf '%s\n' "$removable" | grep -c . || true)

    if [ "$count" -eq 0 ]; then
      printf '{"text":"","tooltip":""}\n'
    else
      # "\\n" here is a literal backslash+n awk emits into the string, i.e. the
      # newline escape JSON itself wants — not an actual newline character.
      list=$(printf '%s\n' "$removable" \
        | awk '{ lbl = ($3 == "" ? $4 : $3); printf "%s (%s)\\n", lbl, $2 }')
      printf '{"text":"󱊞  %s","tooltip":"Mounted:\\n%sClick to safely eject all","class":"disks"}\n' \
        "$count" "$list"
    fi
  '';
  # ── Voice dictation dot (waybar module) ─────────────────────────────────
  # Emits a red dot (theme alarm colour) while a dictation session is
  # recording, nothing otherwise. The module polls this script every second
  # (interval), so the dot tracks the recording state without any signal.
  dictationIndicator = pkgs.writeShellScript "dictation-indicator" ''
    set -eu
    if [ -f "${config.home.homeDirectory}/.local/dict/.active" ]; then
      printf '<span color="#${raw.alarm}">\342\227\217</span>'
    fi
  '';

  # ── Timer / alarm CLI ────────────────────────────────────────────────────
  # One `timer` command drives the bar module AND the alarm. State lives in two
  # places on purpose:
  #   XDG_RUNTIME_DIR/timer-$UID   volatile countdown (end, total, pid) — wiped
  #                                on reboot, so a stale timer after a restart
  #                                is cleaned up by `status`, not misread.
  #   ~/.config/timer/sound        persistent on/off flag — survives reboots.
  # The alarm is a background watcher started by `start`. It sleeps in 1s ticks
  # and reads wall time, so a wake from suspend mid-timer still fires.
  # Sound is three sox synth beeps straight out of the PipeWire pulse sink — no
  # audio file to ship or keep around.
  timerScript = pkgs.writeShellScriptBin "timer" ''
    set -eu
    PATH=${lib.makeBinPath [
      pkgs.coreutils    # date, sleep, cat, rm, echo, mkdir
      pkgs.gawk         # awk (math + progress bar)
      pkgs.libnotify    # notify-send
      pkgs.sox          # play (the beep)
    ]}

    STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/timer-$UID"
    CONF_DIR="$HOME/.config/timer"

    now()  { date +%s; }
    mmss() { awk -v s="$1" 'BEGIN{ printf "%d:%02d", s/60, s%60 }'; }

    running() {
      [ -f "$STATE_DIR/end" ] || return 1
      [ "$(now)" -lt "$(cat "$STATE_DIR/end")" ]
    }

    sound_on() { [ "$(cat "$CONF_DIR/sound" 2>/dev/null || echo on)" = "on" ]; }
    set_sound() { mkdir -p "$CONF_DIR"; echo "$1" > "$CONF_DIR/sound"; }

    spawn_alarm() {
      (
        while :; do
          sleep 1
          [ -f "$STATE_DIR/end" ] || exit 0          # timer was stopped
          [ "$(now)" -ge "$(cat "$STATE_DIR/end")" ] || continue
          rm -f "$STATE_DIR/end" "$STATE_DIR/total" "$STATE_DIR/pid"
          if sound_on; then
            play -q -n synth 0.3 sine 880 || true
            play -q -n synth 0.3 sine 880 || true
            play -q -n synth 0.3 sine 880 || true
          fi
          notify-send -u critical -a "Timer" "Timer done" "Time's up!"
          exit 0
        done
      ) >/dev/null 2>&1 &
      echo $! > "$STATE_DIR/pid"
    }

    start() {
      secs="$1"
      mkdir -p "$STATE_DIR"
      # Kill a previous alarm (pid reuse is checked via kill -0, not assumed).
      if [ -f "$STATE_DIR/pid" ] && kill -0 "$(cat "$STATE_DIR/pid")" 2>/dev/null; then
        kill "$(cat "$STATE_DIR/pid")"
      fi
      echo "$secs" > "$STATE_DIR/total"
      echo "$(( $(now) + secs ))" > "$STATE_DIR/end"
      spawn_alarm
      notify-send -a "Timer" "Timer started" "$(mmss "$secs") - click the bar icon to stop"
    }

    stop() {
      if [ -f "$STATE_DIR/pid" ] && kill -0 "$(cat "$STATE_DIR/pid")" 2>/dev/null; then
        kill "$(cat "$STATE_DIR/pid")"
      fi
      rm -f "$STATE_DIR/end" "$STATE_DIR/total" "$STATE_DIR/pid"
      notify-send -a "Timer" "Timer stopped"
    }

    # JSON for the waybar module. Running: progress bar + time left. Idle: the
    # empty text makes the module disappear from the bar (same trick as
    # custom/brightness without an external screen).
    status() {
      if running; then
        total=$(cat "$STATE_DIR/total")
        left=$(( $(cat "$STATE_DIR/end") - $(now) ))
        done=$(( total - left ))
        pct=$(awk -v d="$done" -v t="$total" 'BEGIN{ printf "%d", d/t*100 }')
        bar=$(awk -v p="$pct" 'BEGIN{ n=int(p/10+0.5); s=""; for(i=0;i<10;i++) s=s (i<n?"█":"░"); print s }')
        snd=$(sound_on && echo on || echo off)
        printf '{"text":"󰥔 %s %s %d%%","tooltip":"Timer - %s left\\nLeft-click: stop\\nRight-click: sound on/off (now %s)","class":"running","percentage":%d}\n' \
          "$(mmss "$left")" "$bar" "$pct" "$(mmss "$left")" "$snd" "$pct"
      else
        # Idle: drop stale state left by a reboot or a crashed alarm process.
        rm -f "$STATE_DIR/end" "$STATE_DIR/total"
        [ -f "$STATE_DIR/pid" ] && { kill -0 "$(cat "$STATE_DIR/pid")" 2>/dev/null || rm -f "$STATE_DIR/pid"; }
        printf '{"text":"","tooltip":""}\n'
      fi
    }

    toggle_sound() {
      if sound_on; then set_sound off; else set_sound on; fi
      notify-send -a "Timer" "Timer sound" "Notification sound $(sound_on && echo on || echo off)"
    }

    # Accept "MINUTES" (e.g. 25, or 1.5) or "M:SS" (e.g. 1:30).
    parse_secs() {
      case "$1" in
        *:*) awk -F: -v m="''${1%:*}" -v s="''${1##*:}" 'BEGIN{ printf "%d", m*60 + s }' ;;
        *)   awk -v m="$1" 'BEGIN{ printf "%d", m*60 }' ;;
      esac
    }

    case "''${1:-}" in
      start)  [ -n "''${2:-}" ] || { echo "usage: timer start MINUTES|M:SS"; exit 1; }
              start "$(parse_secs "$2")" ;;
      stop)   stop ;;
      status) status ;;
      sound)  toggle_sound ;;
      *) echo "usage: timer {start MINUTES|M:SS | stop | status | sound}"; exit 1 ;;
    esac
  '';

  pythonForGtk = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

  brightnessPopover = pkgs.stdenv.mkDerivation {
    name = "brightness-popover";
    nativeBuildInputs = [ pkgs.wrapGAppsHook3 pkgs.gobject-introspection ];
    buildInputs = [ pythonForGtk pkgs.gtk3 pkgs.gtk-layer-shell pkgs.hyprland pkgs.brightnessctl pkgs.systemd ];
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      cat << 'EOF' > $out/bin/brightness-popover
#!${pythonForGtk}/bin/python3
import json
import os
import subprocess
import sys
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GLib, GtkLayerShell  # noqa: E402

LOCK_FILE = f"/tmp/brightness-popover-{os.getuid()}.lock"

def check_single_instance():
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            os.kill(pid, 15)
            os.remove(LOCK_FILE)
            sys.exit(0)
        except (ValueError, OSError):
            pass
    with open(LOCK_FILE, "w") as f:
        f.write(str(os.getpid()))

def cleanup():
    if os.path.exists(LOCK_FILE):
        try:
            os.remove(LOCK_FILE)
        except OSError:
            pass

def get_monitors():
    try:
        res = subprocess.run(["${pkgs.hyprland}/bin/hyprctl", "monitors", "-j"], capture_output=True, text=True, check=True)
        return json.loads(res.stdout)
    except Exception as e:
        print(f"Error fetching monitors: {e}")
        return []

def get_brightness(monitor):
    name = monitor.get("name", "")
    if name == "eDP-1" or "laptop" in monitor.get("description", "").lower():
        try:
            res = subprocess.run(["${pkgs.brightnessctl}/bin/brightnessctl", "-m"], capture_output=True, text=True, check=True)
            parts = res.stdout.strip().split(",")
            if len(parts) >= 4:
                return float(parts[3].replace("%", ""))
        except Exception:
            pass
        return 100.0
    else:
        out_name = name.replace("-", "_")
        try:
            res = subprocess.run([
                "${pkgs.systemd}/bin/busctl", "--user", "get-property", "rs.wl-gammarelay",
                f"/outputs/{out_name}", "rs.wl.gammarelay", "Brightness"
            ], capture_output=True, text=True, check=True)
            val_str = res.stdout.strip().split()[-1]
            return round(float(val_str) * 100.0, 1)
        except Exception:
            return 100.0

def set_brightness(monitor, pct):
    name = monitor.get("name", "")
    pct_clamped = max(5.0, min(100.0, pct))
    if name == "eDP-1" or "laptop" in monitor.get("description", "").lower():
        try:
            subprocess.run(["${pkgs.brightnessctl}/bin/brightnessctl", "set", f"{int(pct_clamped)}%"], check=False)
        except Exception:
            pass
    else:
        out_name = name.replace("-", "_")
        val = pct_clamped / 100.0
        try:
            subprocess.run([
                "${pkgs.systemd}/bin/busctl", "--user", "set-property", "rs.wl-gammarelay",
                f"/outputs/{out_name}", "rs.wl.gammarelay", "Brightness", "d", f"{val:.2f}"
            ], check=False)
            subprocess.run(["pkill", "-RTMIN+8", "waybar"], check=False)
        except Exception:
            pass

# Nightlight = wl-gammarelay colour temperature. The global object "/" applies
# to every output at once; the default (daylight) is 6500K.
NIGHTLIGHT_TEMP = 4500
NORMAL_TEMP = 6500

def get_temperature():
    try:
        res = subprocess.run([
            "${pkgs.systemd}/bin/busctl", "--user", "get-property", "rs.wl-gammarelay",
            "/", "rs.wl.gammarelay", "Temperature"
        ], capture_output=True, text=True, check=True)
        return int(res.stdout.strip().split()[-1])
    except Exception:
        return NORMAL_TEMP

def set_temperature(temp):
    try:
        subprocess.run([
            "${pkgs.systemd}/bin/busctl", "--user", "set-property", "rs.wl-gammarelay",
            "/", "rs.wl.gammarelay", "Temperature", "q", str(temp)
        ], check=False)
    except Exception:
        pass

CSS = """
window {
    background-color: transparent;
}
.popover-card {
    background-color: ${css.base};
    border: 1px solid ${css.overlay};
    border-radius: 14px;
    padding: 16px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6);
}
.header-title {
    color: ${css.text};
    font-weight: bold;
    font-size: 15px;
}
.monitor-card {
    background-color: ${css.surface};
    border: 1px solid ${css.overlay};
    border-radius: 10px;
    padding: 12px;
    margin-top: 10px;
}
.monitor-title {
    color: ${css.text};
    font-weight: bold;
    font-size: 13px;
}
.nightlight-row {
    background-color: ${css.surface};
    border: 1px solid ${css.overlay};
    border-radius: 10px;
    padding: 12px;
    margin-top: 10px;
}
.nightlight-row switch {
    background-color: ${css.overlay};
    border-radius: 999px;
    min-height: 20px;
    min-width: 38px;
}
.nightlight-row switch:checked {
    background-color: ${css.sky};
}
.monitor-sub {
    color: ${css.subtle};
    font-size: 11px;
}
.active-badge {
    background-color: ${css.stone};
    color: ${css.ink};
    font-weight: bold;
    font-size: 10px;
    border-radius: 4px;
    padding: 2px 6px;
}
.pct-label {
    color: ${css.stone};
    font-weight: bold;
    font-size: 14px;
    min-width: 48px;
}
scale trough {
    background-color: ${css.overlay};
    border-radius: 6px;
    min-height: 8px;
}
scale highlight {
    background-color: ${css.stone};
    border-radius: 6px;
    min-height: 8px;
}
scale slider {
    background-color: ${css.text};
    border-radius: 50%;
    min-width: 18px;
    min-height: 18px;
    margin: -5px 0;
}
button.preset-btn {
    background-color: ${css.overlay};
    color: ${css.text};
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 11px;
    border: none;
}
button.preset-btn:hover {
    background-color: ${css.stone};
    color: ${css.ink};
}
"""

class BrightnessPopover(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 34)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 140)

        self.apply_css()
        
        self.leave_timer_id = None
        self.add_events(Gdk.EventMask.LEAVE_NOTIFY_MASK | Gdk.EventMask.ENTER_NOTIFY_MASK)
        self.connect("leave-notify-event", self.on_mouse_leave)
        self.connect("enter-notify-event", self.on_mouse_enter)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        main_box.get_style_context().add_class("popover-card")
        self.add(main_box)

        hdr_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hdr_icon = Gtk.Label(label="☀️")
        hdr_title = Gtk.Label(label="Display Brightness")
        hdr_title.get_style_context().add_class("header-title")
        hdr_box.pack_start(hdr_icon, False, False, 0)
        hdr_box.pack_start(hdr_title, False, False, 0)
        
        close_btn = Gtk.Button(label="✕")
        close_btn.get_style_context().add_class("preset-btn")
        close_btn.connect("clicked", lambda w: self.close_app())
        hdr_box.pack_end(close_btn, False, False, 0)
        main_box.pack_start(hdr_box, False, False, 0)

        monitors = get_monitors()
        if not monitors:
            lbl = Gtk.Label(label="No active displays detected.")
            lbl.get_style_context().add_class("monitor-sub")
            main_box.pack_start(lbl, False, False, 10)
        else:
            for mon in monitors:
                card = self.create_monitor_card(mon)
                main_box.pack_start(card, False, False, 0)

        night_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        night_row.get_style_context().add_class("nightlight-row")
        night_lbl = Gtk.Label(label="☾  Nightlight")
        night_lbl.get_style_context().add_class("monitor-title")
        night_lbl.set_xalign(0)
        night_switch = Gtk.Switch()
        night_switch.set_active(get_temperature() < 6000)
        night_switch.connect("state-set", self.on_night_toggle)
        night_row.pack_start(night_lbl, True, True, 0)
        night_row.pack_end(night_switch, False, False, 0)
        main_box.pack_start(night_row, False, False, 0)

        self.connect("key-press-event", self.on_key_press)
        self.show_all()

    def apply_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def create_monitor_card(self, mon):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.get_style_context().add_class("monitor-card")

        top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        is_laptop = mon.get("name", "") == "eDP-1" or "laptop" in mon.get("description", "").lower()
        icon_str = "󰌢" if is_laptop else "󰍹"
        
        icon_lbl = Gtk.Label(label=icon_str)
        
        desc = mon.get("description", mon.get("name", "Unknown Monitor"))
        desc_clean = desc.replace("Corporation", "").replace("Incorporated", "").strip()
        title_text = f"{desc_clean} ({mon.get('name')})"
        
        title_lbl = Gtk.Label(label=title_text)
        title_lbl.get_style_context().add_class("monitor-title")
        title_lbl.set_xalign(0)

        top_row.pack_start(icon_lbl, False, False, 0)
        top_row.pack_start(title_lbl, True, True, 0)

        if mon.get("focused", False):
            badge = Gtk.Label(label="ACTIVE")
            badge.get_style_context().add_class("active-badge")
            top_row.pack_end(badge, False, False, 0)

        card.pack_start(top_row, False, False, 0)

        slider_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        
        curr_val = get_brightness(mon)
        
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 10.0, 100.0, 1.0)
        scale.set_value(curr_val)
        scale.set_draw_value(False)
        
        pct_lbl = Gtk.Label(label=f"{int(curr_val)}%")
        pct_lbl.get_style_context().add_class("pct-label")

        def on_scale_changed(sc):
            val = sc.get_value()
            pct_lbl.set_text(f"{int(val)}%")
            set_brightness(mon, val)

        scale.connect("value-changed", on_scale_changed)

        slider_row.pack_start(scale, True, True, 0)
        slider_row.pack_start(pct_lbl, False, False, 0)
        card.pack_start(slider_row, False, False, 0)
        return card

    def on_night_toggle(self, switch, state):
        set_temperature(NIGHTLIGHT_TEMP if state else NORMAL_TEMP)

    def on_mouse_leave(self, widget, event):
        if event.detail == Gdk.NotifyType.INFERIOR:
            return False
        if self.leave_timer_id is None:
            self.leave_timer_id = GLib.timeout_add(1000, self.on_leave_timer)
        return False

    def on_mouse_enter(self, widget, event):
        if self.leave_timer_id is not None:
            GLib.source_remove(self.leave_timer_id)
            self.leave_timer_id = None
        return False

    def on_leave_timer(self):
        self.leave_timer_id = None
        self.close_app()
        return False

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close_app()
            return True
        return False

    def close_app(self):
        if self.leave_timer_id is not None:
            GLib.source_remove(self.leave_timer_id)
            self.leave_timer_id = None
        cleanup()
        Gtk.main_quit()

def main():
    check_single_instance()
    win = BrightnessPopover()
    Gtk.main()
    cleanup()

if __name__ == "__main__":
    main()
EOF
      chmod +x $out/bin/brightness-popover
    '';
  };
in
{
  # The timer CLI used by the custom/timer module below.
  home.packages = [ timerScript ];

  #### Status bar ############################################################
  # Without a config here, waybar falls back to /etc/xdg/waybar/config. That
  # default is written for Sway (sway/workspaces) and its battery line uses a
  # loose Font Awesome glyph, which renders as an empty box. Everything below
  # sticks to Nerd Font glyphs that exist in JetBrainsMono Nerd Font.
  #
  # waybar 0.15.0 crashes (SIGSEGV) in the GTK Gdk::Monitor add/remove handler
  # when a monitor is hotplugged, and its battery module can wedge in a kernel
  # ACPI read on the dock's power event. Either way the process dies or hangs
  # and `exec-once` never relaunches it. Running it as a user service with
  # Restart=on-failure brings the bar back automatically.
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;

      modules-left = [ "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ "clock" "custom/timer" "custom/dictation" ];
      modules-right = [
        "cpu" "memory" "temperature"
        "power-profiles-daemon"
        "custom/disks" "bluetooth" "backlight" "custom/brightness" "pulseaudio" "network" "battery"
        "group/power"
      ];

      "hyprland/workspaces" = {
        format = "{name}";
        on-click = "activate";
        sort-by-number = true;
      };
      "hyprland/window" = {
        format = "{title}";
        max-length = 60;
        separate-outputs = true;
      };

      clock = {
        # Date + time in the bar; click switches to the long form.
        format = "{:%a %d %b  %H:%M}";
        format-alt = "{:%A %d %B %Y  %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
        calendar = {
          mode = "month";
          format = {
            today = "<b>{}</b>";
          };
        };
      };

      # Battery: separate icon set for charging and discharging, so charging
      # shows a real charging glyph instead of an empty box.
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon}  {capacity}%";
        format-charging = "{icon}  {capacity}%";
        format-plugged = "󰚥  {capacity}%";
        format-icons = {
          charging = [ "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅" ];
          default = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        };
        tooltip-format = "{timeTo}  ({power}W)";
      };

      # Laptop panel backlight (brightnessctl). The external monitor is the
      # custom/brightness module next to it (gamma-ramp based), so the two
      # screens each get their own percentage when both are connected.
      backlight = {
        format = "{icon}  {percent}%";
        format-icons = [ "󰃞" "󰃟" "󰃠" ];
        on-click = "${brightnessPopover}/bin/brightness-popover";
        on-scroll-up = "brightnessctl set +5%";
        on-scroll-down = "brightnessctl set 5%-";
      };

      # ── Removable media (click to safely eject everything mounted) ──
      "custom/disks" = {
        exec = "${diskStatus}";
        return-type = "json";
        interval = "once";
        signal = 9;
        on-click = "${pkgs.udiskie}/bin/udiskie-umount --all --detach --eject";
        tooltip = true;
      };

      # ── External-monitor brightness (clicks to open slider popup) ──
      # Only present while an external screen is connected (see brightnessExternal).
      "custom/brightness" = {
        exec = "${brightnessExternal} status";
        return-type = "json";
        interval = "once";
        signal = 8;
        on-click = "${brightnessPopover}/bin/brightness-popover";
        on-scroll-up = "${brightnessExternal} up";
        on-scroll-down = "${brightnessExternal} down";
        tooltip = true;
      };

      # ── Voice dictation recording dot (macOS style) ─────────────────────
      # A small red dot while a dictation session is recording. Polls every
      # second; the exec emits nothing when idle, so the module collapses.
      "custom/dictation" = {
        exec = "${dictationIndicator}";
        interval = 1;
        format = "{}";
        escape = false;
        tooltip = false;
      };

      # ── Timer / alarm ────────────────────────────────────────────────────
      # `timer start 25` (or `timer start 1:30`) starts a countdown; this module
      # shows progress + time left while it runs and hides itself when idle.
      # Left-click stops it, right-click toggles the completion sound.
      "custom/timer" = {
        exec = "${timerScript}/bin/timer status";
        return-type = "json";
        interval = 1;
        format = "{}";
        escape = false;
        tooltip = true;
        on-click = "${timerScript}/bin/timer stop";
        on-click-right = "${timerScript}/bin/timer sound";
      };

      pulseaudio = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟  muted";
        format-icons.default = [ "󰕿" "󰖀" "󰕾" ];
        on-click = "pavucontrol";
        on-scroll-up = "pamixer -i 5";
        on-scroll-down = "pamixer -d 5";
      };

      network = {
        format-wifi = "󰤨  {signalStrength}%";
        format-ethernet = "󰈀  wired";
        format-disconnected = "󰤭  offline";
        # Without format-disabled the module renders "{ifname}" (empty once the
        # radio is off and the interface is dropped) and hides itself entirely,
        # leaving no way to turn Wi-Fi back on from the bar. Keep it visible:
        # clicking still opens the picker, whose "Enable Wi-Fi" restores it.
        format-disabled = "󰖪  wifi off";
        tooltip-format-wifi = "{essid}  ({ipaddr})";
        tooltip-format-disabled = "Wi-Fi is off — click to enable";
        # Wi-Fi picker: lists nearby networks + saved connections. Use the
        # "Edit connections…" entry (nm-connection-editor) for profile editing.
        on-click = "networkmanager_dmenu";
      };

      bluetooth = {
        format = "󰂯";
        format-disabled = "󰂲";
        # Controller powered off in blueman-manager (state "off") must keep the
        # icon too, so bluetooth can be re-enabled from the bar.
        format-off = "󰂲";
        format-connected = "󰂱  {num_connections}";
        tooltip-format-connected = "{device_enumerate}";
        on-click = "blueman-manager";
      };

      # ── System meters ──────────────────────────────────────────────────
      # interval is 2s: fast enough to see something happen, slow enough that
      # the bar itself costs no measurable CPU.
      cpu = {
        interval = 2;
        format = "󰻠  {usage}%";
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip = true;
        on-click = "kitty -e btop";
      };

      memory = {
        interval = 2;
        # {percentage} = RAM in use; {used}/{total} in GiB in the tooltip.
        format = "󰍛  {percentage}%";
        states = {
          warning = 75;
          critical = 90;
        };
        tooltip-format = "RAM  {used:0.1f}G / {total:0.1f}G\nSwap  {swapUsed:0.1f}G / {swapTotal:0.1f}G";
        on-click = "kitty -e btop";
      };

      # hwmon numbers (hwmon17) shift between boots, so point at coretemp via
      # its stable platform path. temp1_input = "Package id 0" = package temp.
      temperature = {
        interval = 2;
        hwmon-path-abs = "/sys/devices/platform/coretemp.0/hwmon";
        input-filename = "temp1_input";
        critical-threshold = 85;
        format = "{icon}  {temperatureC}°C";
        format-critical = "󰸁  {temperatureC}°C";
        format-icons = [ "󰔏" "󰔐" "󰸁" ];
        tooltip = false;
      };

      power-profiles-daemon = {
        format = "{icon}  {profile}";
        tooltip-format = "Power profile: {profile}\nDriver: {driver}";
        tooltip = true;
        format-icons = {
          default = "";
          performance = "";
          balanced = "󰾅";
          power-saver = "󰌪";
        };
      };

      "group/power" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 300;
          children-class = "not-power";
          transition-left-to-right = false;
        };
        modules = [
          "custom/power"
          "custom/lock"
          "custom/suspend"
          "custom/hibernate"
          "custom/reboot"
          "custom/shutdown"
        ];
      };

      "custom/power" = {
        format = "";
        tooltip = true;
        tooltip-format = "Power menu";
      };

      "custom/lock" = {
        format = "";
        tooltip = true;
        tooltip-format = "Lock screen (hyprlock)";
        on-click = "hyprlock";
      };

      "custom/suspend" = {
        format = "󰤄";
        tooltip = true;
        tooltip-format = "Sleep (suspend)";
        on-click = "systemctl suspend";
      };

      # Hibernation on this machine used to wedge it: the kernel snapshotted
      # memory, the IPU6 camera driver failed to re-authenticate its firmware,
      # the image was discarded, and everything sat frozen and powered until the
      # battery ran flat. The IPU6 modules are blacklisted in
      # ../configuration.nix, which removes that failure — but a successful
      # hibernate has not been observed since. The button is here to test with;
      # nothing else in the config triggers hibernation automatically.
      # See docs/hibernation-ipu6.md for the diagnosis and how to verify.
      "custom/hibernate" = {
        format = "󰤁";
        tooltip = true;
        tooltip-format = "Hibernate (suspend to disk)";
        on-click = "systemctl hibernate";
      };

      "custom/reboot" = {
        format = "󰜉";
        tooltip = true;
        tooltip-format = "Restart (reboot)";
        on-click = "systemctl reboot";
      };

      "custom/shutdown" = {
        format = "";
        tooltip = true;
        tooltip-format = "Power off (poweroff)";
        on-click = "systemctl poweroff";
      };

      tray.spacing = 10;
    };

    # Colours come from ../theme.nix (sampled from the wallpaper). GTK CSS has
    # no `#rrggbbaa`, but it does have alpha(colour, factor) — used everywhere
    # something needs to be translucent.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      /* The dark foreground of the painting, with the horizon haze as a hair
         line under it, so the bar has an edge without being harsh. */
      window#waybar {
        background: alpha(${css.ink}, 0.86);
        color: ${css.text};
        border-bottom: 1px solid alpha(${css.haze}, 0.22);
      }

      #workspaces { margin-left: 4px; }
      #workspaces button {
        padding: 0 10px;
        margin: 4px 2px;
        border-radius: 6px;
        color: ${css.subtle};
        background: transparent;
      }
      #workspaces button:hover {
        background: alpha(${css.haze}, 0.12);
        color: ${css.text};
      }
      /* Active workspace = the sky: the lightest area on the canvas. */
      #workspaces button.active {
        color: ${css.ink};
        background: ${css.sky};
      }
      #workspaces button.urgent {
        color: ${css.ink};
        background: ${css.alarm};
      }

      #window {
        color: ${css.subtle};
        padding: 0 10px;
      }

      /* The right-hand side is one continuous "limestone" band: modules are
         separated by their own icon colour, not by boxes. */
      #clock, #battery, #backlight, #pulseaudio, #network, #bluetooth, #power-profiles-daemon, #tray,
      #cpu, #memory, #temperature,
      #custom-timer,
      #custom-power, #custom-lock, #custom-suspend, #custom-hibernate, #custom-reboot, #custom-shutdown,
      #custom-brightness-ext,
      #custom-bright-100, #custom-bright-75, #custom-bright-50, #custom-bright-25 {
        padding: 0 10px;
        margin: 4px 0;
        color: ${css.text};
        background: transparent;
      }

      /* The clock is centred and is allowed to stand out most. */
      #clock {
        color: ${css.stone};
        padding: 0 14px;
        margin: 4px 4px;
        border-radius: 6px;
        background: alpha(${css.stone}, 0.10);
      }

      #backlight { color: ${css.ochre}; }
      #custom-brightness { color: ${css.sky}; }
      #pulseaudio  { color: ${css.haze}; }
      #network     { color: ${css.sky}; }
      #bluetooth   { color: ${css.haze}; }
      #cpu, #memory, #temperature { color: ${css.subtle}; }

      /* Timer: sky while counting down. */
      #custom-timer { color: ${css.sky}; }

      #power-profiles-daemon              { color: ${css.ochre}; }
      #power-profiles-daemon.performance  { color: ${css.alarm}; }
      #power-profiles-daemon.balanced     { color: ${css.sky}; }
      #power-profiles-daemon.power-saver  { color: ${css.meadow}; }

      #custom-power     { color: ${css.alarm}; }
      #custom-lock      { color: ${css.stone}; }
      #custom-suspend   { color: ${css.sky}; }
      #custom-hibernate { color: ${css.haze}; }
      /* Reboot sits next to shutdown, so it gets ochre rather than alarm red:
         the destructive-looking one should be the one that actually powers off. */
      #custom-reboot    { color: ${css.ochre}; }
      #custom-shutdown  { color: ${css.alarm}; }

      #pulseaudio.muted        { color: ${css.muted}; }
      #network.disconnected    { color: ${css.muted}; }
      #bluetooth.disabled      { color: ${css.muted}; }

      #battery          { color: ${css.meadow}; }
      #battery.charging { color: ${css.meadow}; }
      #battery.warning  { color: ${css.ochre}; }
      #battery.critical { color: ${css.alarm}; }

      /* Same colour code as the battery, so "gold = pay attention, roof red =
         act now" means the same thing everywhere. */
      #cpu.warning, #memory.warning     { color: ${css.ochre}; }
      #cpu.critical, #memory.critical   { color: ${css.alarm}; }
      #temperature.critical             { color: ${css.alarm}; }

      tooltip {
        background: alpha(${css.base}, 0.96);
        border: 1px solid alpha(${css.haze}, 0.35);
        border-radius: 8px;
      }
      tooltip label { color: ${css.text}; }
    '';
  };

  #### On-screen display (volume / brightness / media) ########################
  # The waybar modules do show volume and brightness, but nobody reads the bar
  # while watching something fullscreen — and waybar sits below a fullscreen
  # window anyway. SwayOSD draws on the layer-shell *overlay* layer, so its
  # popup appears on top of fullscreen video too. Media keys therefore go to
  # swayosd-client rather than straight to pamixer/brightnessctl: it sets the
  # value AND shows the popup, so the two can never drift apart.
  services.swayosd = {
    enable = true;
    topMargin = 0.85;   # near the bottom, out of the way of subtitles
    stylePath = pkgs.writeText "swayosd-style.css" ''
      /* Same palette as waybar and mako (../theme.nix): dark area from the
         foreground of the painting, with the horizon haze as the border. */
      window#osd {
        border-radius: 14px;
        border: 2px solid alpha(${css.haze}, 0.45);
        background: alpha(${css.ink}, 0.94);
      }
      window#osd #container { margin: 16px; }

      window#osd image,
      window#osd label {
        color: ${css.text};
      }

      window#osd progressbar:disabled,
      window#osd image:disabled { opacity: 0.5; }

      window#osd progressbar,
      window#osd segmentedprogress {
        min-height: 8px;
        border-radius: 999px;
        background: transparent;
        border: none;
      }
      /* Unfilled part of the bar. */
      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${css.overlay};
      }
      /* Filled part — the same sky colour as the active workspace. */
      window#osd progress,
      window#osd segment.active {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${css.sky};
      }
      window#osd segment { margin-left: 8px; }
      window#osd segment:first-child { margin-left: 0; }
    '';
  };
}
