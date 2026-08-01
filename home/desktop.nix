################################################################################
#  Hyprland + Wayland desktop — packages AND configuration.
#  Kept separate from your apps/dev packages (./packages.nix) on request.
################################################################################
{ pkgs, lib, ... }:
let
  # Same image the login screen (../greeter.nix) uses, but rendered per screen
  # size — see the explanation in ../wallpaper.nix. `wallpaper` stays the laptop
  # version because hyprlock uses it too.
  wallpaper = import ../wallpaper.nix { inherit pkgs; };
  wallpaperUltrawide = import ../wallpaper.nix {
    inherit pkgs;
    width = 3440;
    height = 1440;
  };

  # The external monitor's connector name is NOT stable: the USB-C dock speaks
  # DisplayPort MST, and the kernel reassigns the invented name on every replug
  # (it has been DP-6 and DP-7). Match by EDID description instead, which stays
  # the same, so monitor placement and the per-screen wallpaper keep working no
  # matter what the connector happens to be called today. Both Hyprland monitor
  # rules and hyprpaper accept `desc:<description>`.
  externalMonitorDesc = "desc:Xiaomi Corporation Mi Monitor";

  # Locks the session and does not return until hyprlock is actually up.
  #
  # `loginctl lock-session` only fires a D-Bus signal; hyprlock then starts
  # asynchronously. hypridle holds a systemd sleep inhibitor for exactly as long
  # as before_sleep_cmd runs, so if that command returns immediately the machine
  # suspends while the old screen is still the last thing the compositor drew --
  # and that stale frame is what you see for a moment on wake, before hyprlock
  # paints over it. Waiting here keeps the inhibitor held until the locker is on
  # screen, so nothing readable survives the sleep.
  lockBeforeSleep = pkgs.writeShellScript "lock-before-sleep" ''
    ${pkgs.systemd}/bin/loginctl lock-session || true

    # Wait for the hyprlock process (cap at ~3s so a broken locker can never
    # block sleep forever -- suspending late beats not suspending at all).
    for _ in $(seq 1 30); do
      ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && break
      sleep 0.1
    done

    # Existing is not the same as having drawn. Give it one more beat to put the
    # first frame up before the compositor is frozen mid-repaint.
    sleep 0.5
  '';

  # Low battery notification daemon script
  batteryNotifier = pkgs.writers.writePython3Bin "battery-notifier" { doCheck = false; } ''
    import sys
    import time
    import subprocess
    import os

    def send_notification(urgency, title, body, icon="battery"):
        try:
            subprocess.run([
                "${pkgs.libnotify}/bin/notify-send",
                "-u", urgency,
                "-a", "Battery Warning",
                "-i", icon,
                title,
                body
            ], check=False)
        except Exception as e:
            print(f"Error sending notification: {e}", file=sys.stderr)

    def get_battery_info():
        cap_file = "/sys/class/power_supply/BAT0/capacity"
        stat_file = "/sys/class/power_supply/BAT0/status"
        if not os.path.exists(cap_file) or not os.path.exists(stat_file):
            return None, None
        try:
            with open(cap_file, "r") as f:
                capacity = int(f.read().strip())
            with open(stat_file, "r") as f:
                status = f.read().strip()
            return capacity, status
        except Exception as e:
            print(f"Error reading battery: {e}", file=sys.stderr)
            return None, None

    def main():
        warned = {20: False, 15: False, 10: False, 5: False}
        was_charging = False

        while True:
            capacity, status = get_battery_info()
            if capacity is not None and status is not None:
                is_charging = (status == "Charging")
                is_discharging = (status == "Discharging")

                if is_charging:
                    if not was_charging and any(warned.values()):
                        send_notification("low", "⚡ Charger Connected", f"Battery is now charging ({capacity}%).", "battery-charging")
                    for k in warned:
                        warned[k] = False
                    was_charging = True
                elif is_discharging:
                    was_charging = False
                    if capacity <= 5 and not warned[5]:
                        send_notification("critical", "⚔️ Battery Empty (5%)", f"Battery level is at {capacity}%. Connect charger immediately to avoid suspend!", "battery-empty")
                        warned[5] = True
                        warned[10] = True
                        warned[15] = True
                        warned[20] = True
                    elif capacity <= 10 and not warned[10]:
                        send_notification("critical", "⚔️ Critical Battery (10%)", f"Battery level is down to {capacity}%. Please connect your charger!", "battery-caution")
                        warned[10] = True
                        warned[15] = True
                        warned[20] = True
                    elif capacity <= 15 and not warned[15]:
                        send_notification("normal", "🔋 Low Battery (15%)", f"Battery level is down to {capacity}%. Plug in charger soon.", "battery-low")
                        warned[15] = True
                        warned[20] = True
                    elif capacity <= 20 and not warned[20]:
                        send_notification("low", "🔋 Low Battery (20%)", f"Battery level is down to {capacity}%.", "battery-low")
                        warned[20] = True
                else:
                    if capacity > 25:
                        for k in warned:
                            warned[k] = False

            time.sleep(10)

    if __name__ == "__main__":
        main()
  '';


  # One place for the screen definitions, so the monitor lines below and any
  # script that re-enables a panel use the exact same string and the laptop
  # always comes back in the same spot. See the diagram at `monitor =` for
  # where 760x1440 comes from.
  laptopMonitor = "eDP-1,1920x1280@60,760x1440,1";
  externalMonitor = "${externalMonitorDesc},3440x1440@120,0x0,1";

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
    outputs() {
      busctl --user tree rs.wl-gammarelay 2>/dev/null \
        | sed -n 's|.*/outputs/||p' \
        | grep -v '^eDP_1$' || true
    }

    get() {
      first=$(outputs | head -1)
      if [ -n "$first" ]; then
        busctl --user get-property rs.wl-gammarelay "/outputs/$first" \
          rs.wl.gammarelay Brightness 2>/dev/null | awk '{print $2}' || echo 1.0
      else
        v=$(brightnessctl -m 2>/dev/null | cut -d',' -f4 | tr -d '%' || echo 100)
        awk -v x="$v" 'BEGIN{printf "%.2f", x/100}'
      fi
    }

    setall() {
      v=$(awk -v x="$1" 'BEGIN{ if(x<0.1)x=0.1; if(x>1)x=1; printf "%.2f", x }')
      outs=$(outputs)
      if [ -n "$outs" ]; then
        for o in $outs; do
          busctl --user set-property rs.wl-gammarelay "/outputs/$o" \
            rs.wl.gammarelay Brightness d "$v" 2>/dev/null || true
        done
      else
        pct=$(awk -v x="$v" 'BEGIN{printf "%d", x*100}')
        brightnessctl set "$pct%" 2>/dev/null || true
      fi
      pkill -RTMIN+8 waybar 2>/dev/null || true
    }

    case "''${1:-status}" in
      up)   setall "$(awk -v c="$(get)" 'BEGIN{printf "%.2f", c+0.05}')" ;;
      down) setall "$(awk -v c="$(get)" 'BEGIN{printf "%.2f", c-0.05}')" ;;
      set)  setall "$2" ;;
      status)
        cur=$(get)
        pct=$(awk -v c="$cur" 'BEGIN{printf "%d", c*100+0.5}')
        if   [ "$pct" -lt 40 ]; then icon="󰃞"
        elif [ "$pct" -lt 75 ]; then icon="󰃟"
        else                         icon="󰃠"
        fi
        printf '{"text":"%s  %d%%","tooltip":"Display Brightness (%d%%)\\nClick for Sliders per display\\nScroll to adjust active screen","class":"ext-brightness","percentage":%d}\n' \
          "$icon" "$pct" "$pct" "$pct"
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

  # Passed to `udiskie --event-hook`: fires on every mount/unmount so the
  # waybar module above updates immediately instead of on a poll interval.
  diskNotifyHook = pkgs.writeShellScript "disk-notify-hook" ''
    ${pkgs.procps}/bin/pkill -RTMIN+9 waybar 2>/dev/null || true
  '';

  theme = import ../theme.nix { };
  inherit (theme) raw css;

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

  # Op één plek, want de cursor moet op drie manieren gezet worden: via
  # home.pointerCursor (schrijft ~/.icons/default + de GTK-settings) én via
  # XCURSOR_* in Hyprlands omgeving (voor de compositor zelf en alle clients
  # die hun eigen cursor tekenen).
  cursorTheme = "capitaine-cursors";
  cursorSize = 24;

in
{
  #### Desktop packages (only the WM/Wayland stack) ##########################
  home.packages = with pkgs; [
    # waybar komt nu uit programs.waybar (onderaan), niet meer los hier.
    wofi                   # tweede launcher (dmenu-modus voor cliphist)
    # rofi staat hier NIET meer: die komt nu uit programs.rofi (onderaan), met
    # eigen thema. Hem óók hier laten staan geeft een file-collision in
    # home-manager, want beide willen bin/rofi in hetzelfde profiel zetten.
    libnotify              # notify-send (mako itself comes from services.mako)
    hyprlock               # screen locker
    grim slurp swappy      # screenshots (+ annotate)
    wl-clipboard cliphist  # clipboard + history
    brightnessctl playerctl pamixer pavucontrol
    ddcutil                # DDC/CI over i2c — only works on a DIRECT cable, not
                           # through the dock; see the note at brightnessExternal
    wl-gammarelay-rs       # external screen brightness via the gamma ramp
    networkmanagerapplet
    # blueman komt nu uit services.blueman.enable in ../configuration.nix, zodat
    # de GUI en zijn system-service (blueman-mechanism) uit één versie komen.
    nautilus xfce.thunar   # file managers (GTK)
    udiskie                # auto-mounts USB drives on plug-in; status is the custom/disks waybar module
    nwg-look               # GTK theme settings
    papirus-icon-theme     # iconen voor rofi's app-lijst (icon-theme hieronder)
    polkit_gnome           # auth agent
  ];

  #### Statusbalk ############################################################
  # Er stond géén waybar-config, dus waybar viel terug op /etc/xdg/waybar/config.
  # Die default is voor Sway geschreven (sway/workspaces) en zijn batterijregel
  # is  "format-charging": "{capacity}% " met een los Font-Awesome-teken —
  # vandaar je ontbrekende laad-icoon. Hieronder een eigen config met
  # Nerd-Font-iconen die wél in JetBrainsMono Nerd Font zitten.
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 6;

      modules-left = [ "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ "clock" ];
      modules-right = [
        "cpu" "memory" "temperature"
        "power-profiles-daemon"
        "custom/disks" "bluetooth" "custom/brightness" "pulseaudio" "network" "battery"
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
        # Datum + tijd in de balk; klik wisselt naar de lange schrijfwijze.
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

      # Batterij: aparte icoonreeks voor opladen én ontladen, zodat je
      # tijdens het laden een echt laad-icoon ziet in plaats van een leeg vak.
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

      backlight = {
        format = "{icon}  {percent}%";
        format-icons = [ "󰃞" "󰃟" "󰃠" ];
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

      # ── Brightness module (clicks to open multi-display slider popup) ──
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
        tooltip-format-wifi = "{essid}  ({ipaddr})";
        on-click = "nm-connection-editor";
      };

      bluetooth = {
        format = "󰂯";
        format-disabled = "󰂲";
        format-connected = "󰂱  {num_connections}";
        tooltip-format-connected = "{device_enumerate}";
        on-click = "blueman-manager";
      };

      # ── Systeemmeters ──────────────────────────────────────────────────
      # interval staat op 2s: snel genoeg om iets te zien gebeuren, traag
      # genoeg dat de balk zelf geen meetbare CPU kost.
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
        # {percentage} = RAM in gebruik; {used}/{total} in GiB in de tooltip.
        format = "󰍛  {percentage}%";
        states = {
          warning = 75;
          critical = 90;
        };
        tooltip-format = "RAM  {used:0.1f}G / {total:0.1f}G\nSwap  {swapUsed:0.1f}G / {swapTotal:0.1f}G";
        on-click = "kitty -e btop";
      };

      # hwmon-nummers (hwmon17) schuiven per boot, dus wijs coretemp aan via
      # zijn stabiele platform-pad. temp1_input = "Package id 0" = pakket-temp.
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

      # Back in the drawer as of 2026-07-30. It used to wedge the machine: the
      # kernel snapshotted memory, the IPU6 camera driver failed to re-authenticate
      # its firmware, and the image was discarded — leaving everything frozen and
      # powered until the battery ran flat. The IPU6 modules are blacklisted in
      # ../../configuration.nix now, which removes that failure. See
      # docs/hibernation-ipu6.md for the full story and how to verify.
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

    # Kleuren komen uit ../theme.nix (bemonsterd uit de wallpaper). GTK-CSS
    # kent geen `#rrggbbaa`, wél de functie alpha(kleur, factor) — die gebruiken
    # we overal waar iets moet doorschijnen.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      /* De donkere voorgrond van het schilderij, met de horizonnevel als
         haarlijn eronder zodat de balk een rand heeft zonder hard te worden. */
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
      /* Actieve workspace = de lucht: het lichtste vlak op het doek. */
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

      /* Rechterkant als één doorlopend vlak van "kalksteen": de modules zijn
         onderling gescheiden door hun eigen icoonkleur, niet door hokjes. */
      #clock, #battery, #backlight, #pulseaudio, #network, #bluetooth, #power-profiles-daemon, #tray,
      #cpu, #memory, #temperature,
      #custom-power, #custom-lock, #custom-suspend, #custom-hibernate, #custom-reboot, #custom-shutdown,
      #custom-brightness-ext,
      #custom-bright-100, #custom-bright-75, #custom-bright-50, #custom-bright-25 {
        padding: 0 10px;
        margin: 4px 0;
        color: ${css.text};
        background: transparent;
      }

      /* De klok staat in het midden en mag het meeste opvallen. */
      #clock {
        color: ${css.stone};
        padding: 0 14px;
        margin: 4px 4px;
        border-radius: 6px;
        background: alpha(${css.stone}, 0.10);
      }

      #backlight   { color: ${css.ochre}; }
      #pulseaudio  { color: ${css.haze}; }
      #network     { color: ${css.sky}; }
      #bluetooth   { color: ${css.haze}; }
      #cpu, #memory, #temperature { color: ${css.subtle}; }

      #power-profiles-daemon              { color: ${css.ochre}; }
      #power-profiles-daemon.performance  { color: ${css.alarm}; }
      #power-profiles-daemon.balanced     { color: ${css.sky}; }
      #power-profiles-daemon.power-saver  { color: ${css.meadow}; }

      #custom-brightness { color: ${css.ochre}; }

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

      /* Zelfde kleurcode als de batterij, zodat "goud = let op, dakrood =
         nu ingrijpen" overal hetzelfde betekent. */
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

  #### On-screen display (volume / helderheid / media) ########################
  # De waybar-modules tonen volume en helderheid wél, maar die balk zit je niet
  # te lezen als je fullscreen kijkt — en op een fullscreen venster ligt waybar
  # eronder. SwayOSD tekent op de layer-shell *overlay*-laag, dus zijn popup
  # komt óók boven fullscreen video. De toetsen hieronder gaan daarom niet meer
  # rechtstreeks naar pamixer/brightnessctl maar naar swayosd-client: die zet
  # de waarde én toont de popup, zodat de twee nooit uit elkaar lopen.
  services.swayosd = {
    enable = true;
    topMargin = 0.85;   # onderin, uit de weg van ondertitels
    stylePath = pkgs.writeText "swayosd-style.css" ''
      /* Zelfde palet als waybar en mako (../theme.nix): donker vlak uit de
         voorgrond van het schilderij, met de horizonnevel als rand. */
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
      /* Onafgelegde deel van de balk. */
      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${css.overlay};
      }
      /* Gevulde deel — dezelfde luchtkleur als de actieve workspace. */
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

  #### Muiscursor ############################################################
  # Capitaine: een slanke, klassieke pijl met een dunne witte omlijning.
  #
  # Waarom niet Bibata: die vorm is een dikke, moderne blob, en de Amber-variant
  # is fel oranje (#ff8300) — naast een gedempt olieverfdoek uit 1750 leest dat
  # als een waarschuwingsbord. De Ice-variant (wit) verdween dan weer in de
  # lichte lucht van de wallpaper. Capitaine's donkere vulling houdt zich staande
  # op de lucht én op de weide, en de witte rand doet hetzelfde op de donkere
  # balk en terminal.
  home.pointerCursor = {
    # Expliciet aan: vanaf recente home-manager geeft "afleiden uit de rest van
    # het blok" een deprecation-warning.
    enable = true;
    package = pkgs.capitaine-cursors;
    # LET OP: dit is de MAPNAAM in share/icons, niet de `Name=` uit index.theme
    # (die is "Capitaine Cursors", met spatie — daar zoekt XCursor niet op).
    name = cursorTheme;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  #### GTK ###################################################################
  # Dit stond volledig buiten nix om: ~/.config/gtk-{3,4}.0/settings.ini en
  # ~/.gtkrc-2.0 waren nog de KDE-bestanden van de oude Debian-installatie
  # (gtk-theme-name=Breeze, icon-theme=breeze-dark, cursor-theme=breeze_cursors).
  # Geen van die drie bestaat op deze machine, dus GTK-apps vielen terug op de
  # standaard — en, belangrijker, `gtk-cursor-theme-name=breeze_cursors` won het
  # van de instelling hierboven. Dát is waarom nautilus en pavucontrol een andere
  # cursor toonden dan de rest van de desktop.
  #
  # home.pointerCursor.gtk.enable zet alleen `gtk.cursorTheme`; zonder
  # `gtk.enable = true` schrijft home-manager de settings.ini helemaal niet.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Noto Sans";
      size = 10;
    };
  };

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

  #### Programmastarter ($mod+Space) #########################################
  # rofi zat alleen in home.packages, dus hij draaide op het ingebouwde
  # "Default"-thema (grijs/blauw, vierkant). Hier komt hij uit programs.rofi,
  # zodat config én thema meegaan in de rebuild.
  programs.rofi = {
    enable = true;
    terminal = "${pkgs.kitty}/bin/kitty";
    font = "JetBrainsMono Nerd Font 11";

    extraConfig = {
      modes = "drun,run,window";
      show-icons = true;
      # Alleen de programmanaam, niet "Naam (algemene omschrijving)".
      drun-display-format = "{name}";
      icon-theme = "Papirus-Dark";
      display-drun = "  apps";
      display-run = "  run";
      display-window = "  windows";
      # Zonder deze regel staat er "drun" als prompt vóór je typt.
      kb-cancel = "Escape,Super+space";
    };

    # Alleen de naam; het bestand zelf zetten we hieronder in
    # ~/.local/share/rofi/themes/ — dat is de map waar rofi (en home-manager
    # zelf) thema's zoekt.
    #
    # Waarom niet `theme = pkgs.writeText ...`? De rofi-module test met
    # `isAttrs` of je een thema-als-attribuutset meegeeft, en een derivation
    # ís een attribuutset. Hij probeert die dan als rasi te serialiseren en
    # sneuvelt met "Unhandled value type set".
    theme = "bellotto";
  };

  # .rasi wil #rrggbbaa, dus weer de kale hex uit ../theme.nix.
  xdg.dataFile."rofi/themes/bellotto.rasi".text = ''
    * {
      bg:       #${raw.ink}f2;
      bg-alt:   #${raw.surface}b3;
      fg:       #${raw.text}ff;
      fg-dim:   #${raw.subtle}ff;
      accent:   #${raw.sky}ff;
      gold:     #${raw.ochre}ff;
      edge:     #${raw.haze}59;
      urgent:   #${raw.alarm}ff;

      background-color: transparent;
      text-color:       @fg;
      font:             "JetBrainsMono Nerd Font 11";
    }

    window {
      transparency:     "real";
      location:         center;
      anchor:           center;
      width:            640px;
      border:           2px;
      border-radius:    14px;
      border-color:     @edge;
      background-color: @bg;
      padding:          0;
      children:         [ mainbox ];
    }

    mainbox {
      padding:  16px;
      spacing:  12px;
      children: [ inputbar, listview ];
    }

    /* Zoekbalk: hetzelfde afgeronde vlak als de klok in waybar. */
    inputbar {
      spacing:          10px;
      padding:          10px 14px;
      border-radius:    10px;
      background-color: @bg-alt;
      children:         [ prompt, entry ];
    }
    prompt {
      text-color:     @gold;
      vertical-align: 0.5;
    }
    entry {
      placeholder:       "Search…";
      placeholder-color: @fg-dim;
      vertical-align:    0.5;
    }

    listview {
      columns:      1;
      lines:        9;
      scrollbar:    false;
      fixed-height: false;
      spacing:      2px;
    }

    element {
      padding:       8px 12px;
      spacing:       12px;
      border-radius: 8px;
    }
    element normal.normal,
    element alternate.normal { text-color: @fg; }
    element normal.urgent,
    element alternate.urgent { text-color: @urgent; }

    /* Geselecteerde regel = de lucht, met de donkere voorgrond als tekst.
       Zelfde omkering als de actieve workspace in waybar. */
    element selected.normal {
      background-color: @accent;
      text-color:       #${raw.ink}ff;
    }
    element selected.urgent {
      background-color: @urgent;
      text-color:       #${raw.ink}ff;
    }

    element-icon {
      size:           24px;
      vertical-align: 0.5;
    }
    element-text {
      vertical-align: 0.5;
      text-color:     inherit;
    }
  '';

  #### Hyprland (declarative) ################################################
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;        # use the system Hyprland from programs.hyprland
    portalPackage = null;
    settings = {
      "$mod" = "SUPER";
      "$term" = "kitty";
      "$menu" = "rofi -show drun";
      # De zen-flake installeert het binary als `zen-beta`, niet `zen` — met
      # "zen" deed $mod+B dus helemaal niets. Geverifieerd met `command -v`.
      "$browser" = "zen-beta";
      "$files" = "nautilus";

      # ── Screens ─────────────────────────────────────────────────────────
      # The ultrawide sits ABOVE the laptop panel, not beside it. Hyprland has no
      # "above/below" keywords, only coordinates, so the layout is:
      #
      #     x=0                                          x=3440
      #   y=0    ┌────────────────────────────────────────┐
      #          │      external  3440x1440 (desc match)  │
      #   y=1440 └──────────┬──────────────────┬──────────┘
      #                     │  eDP-1 1920x1280 │
      #   y=2720            └──────────────────┘
      #                   x=760              x=2680
      #
      # 760 = (3440 - 1920) / 2, so the laptop panel hangs centred under the
      # ultrawide and the mouse runs straight down into it.
      #
      # 120 Hz, not 144. This Mi Monitor's EDID offers nothing above 120 at
      # 3440x1440 (144 exists only at 2560x1080). Hyprland ACCEPTS `@144` and
      # then reports it back happily, so `hyprctl monitors` shows nothing wrong —
      # but aquamarine then logs a steady stream of "atomic drm request: failed to
      # commit: Device or resource busy", i.e. dropped frames. At 120 that log is
      # clean (measured: 4 failures per 6 s at 144, 0 per 5 s at 120). The link
      # simply does not have the bandwidth.
      monitor = [
        externalMonitor
        laptopMonitor
        ",preferred,auto,1"          # fallback for unknown screens
      ];

      # XCURSOR_THEME stond nergens in de sessie-omgeving. Zonder die variabele
      # zoekt iedere client "default" op en volgt hij ~/.icons/default/index.theme
      # — maar wie dat bestand als eerste leest, en wanneer, verschilt per app.
      # Gevolg: de desktop toonde een heel ander thema (Layan-border, een blauwe
      # druppel uit ~/.icons van vóór NixOS) dan wat er ingesteld stond.
      # Expliciet zetten haalt die gok eruit. Hyprland exporteert deze variabelen
      # naar alles wat het start, dus compositor en clients zitten op één lijn.
      env = [
        "XCURSOR_THEME,${cursorTheme}"
        "XCURSOR_SIZE,${toString cursorSize}"
      ];

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
        # Actieve rand loopt van de lucht naar het koren — dezelfde overgang
        # die het schilderij van boven naar beneden maakt. Inactieve vensters
        # krijgen de boomschaduw, zodat ze wegvallen.
        "col.active_border" = "rgba(${raw.sky}ee) rgba(${raw.ochre}ee) 45deg";
        "col.inactive_border" = "rgba(${raw.overlay}aa)";
      };
      decoration = {
        rounding = 8;
        blur = { enabled = true; size = 6; passes = 2; };
      };

      # hyprpaper en hypridle staan hier BEWUST niet meer bij: services.hyprpaper
      # en services.hypridle (onderaan dit bestand) maken al systemd user-units
      # die via hyprland-session.target -> graphical-session.target starten.
      # Ze hier óók nog eens exec-once'en gaf een tweede instantie die om dezelfde
      # wayland-socket vocht.
      # nm-applet en blueman-applet stonden hier: die zetten élk nog een eigen
      # icoon in de systray, bovenop waybars eigen `network`- en `bluetooth`-
      # module. Vandaar dubbele wifi- en bluetooth-iconen. De waybar-modules
      # blijven (die volgen het thema); de applets zijn eruit. De GUI's bereik
      # je nog steeds door op de module te klikken: network -> nm-connection-
      # editor, bluetooth -> blueman-manager.
      exec-once = [
        "waybar"
        "mako"
        "wl-paste --watch cliphist store"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        # Watches udisks2 (enabled in ../configuration.nix) and auto-mounts USB
        # drives/SD cards on plug-in. No --tray: its icon didn't match the rest
        # of the bar (see custom/disks above, which replaces it and uses
        # --event-hook here to refresh on every mount/unmount).
        "${pkgs.udiskie}/bin/udiskie --no-tray --event-hook ${diskNotifyHook}"
      ];
    };
  };

  #### wl-gammarelay-rs (external monitor brightness) ########################
  # Daemon that owns the gamma ramp and exposes it on DBus. It must run for the
  # waybar brightness module to have anything to talk to; without it the module
  # falls back to reporting 100%.
  #
  # Tied to graphical-session.target, the same way services.hyprpaper and
  # services.hypridle are wired (see the note near exec-once). It needs a live
  # Wayland connection, so it cannot start before the compositor exists.
  systemd.user.services.wl-gammarelay-rs = {
    Unit = {
      Description = "wl-gammarelay-rs — gamma ramp control over DBus";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-gammarelay-rs}/bin/wl-gammarelay-rs run";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  #### battery-notifier (low battery warning daemon) #########################
  systemd.user.services.battery-notifier = {
    Unit = {
      Description = "Low battery notification daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${batteryNotifier}/bin/battery-notifier";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  #### hypridle (lock + suspend) #############################################
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        # See lockBeforeSleep at the top of this file: this waits for the locker
        # to be on screen before the machine is allowed to go down, so the last
        # active window is not briefly readable on wake.
        before_sleep_cmd = "${lockBeforeSleep}";
        # Recommended by hypridle: without this the panel can stay black on wake
        # because the compositor left DPMS off.
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        { timeout = 300;  on-timeout = "loginctl lock-session"; }
        # Plain suspend, NOT suspend-then-hibernate. Hibernation is broken on
        # this hardware: the kernel snapshots memory fine and then a driver
        # fails to come back during the snapshot's resume phase
        #     sof-audio-pci-intel-tgl 0000:00:1f.3: IMR restore failed
        #     intel-ipu6 0000:00:05.0: FW authentication failed(-110)
        #     PM: hibernation: hibernation exit
        # so the image is discarded before a single byte reaches the swap
        # partition. The machine does not power off and does not come back
        # either -- it sits frozen with the session drawing power until the lid
        # is opened, which is what emptied the battery overnight. Verified
        # 2026-07-30 with HibernateMode=shutdown too, so it is not the ACPI S4
        # path: /sys/power/disk showed `platform [shutdown]` and it still
        # aborted, boot id unchanged, 0B written to swap.
        { timeout = 900;  on-timeout = "systemctl suspend"; }
      ];
    };
  };

  #### hyprpaper ############################################################
  # Wallpaper komt uit ../wallpaper.nix — pas die file aan om hem te wisselen;
  # loginscherm, desktop en lockscherm volgen dan automatisch mee.
  #
  # LET OP — de syntax hieronder is die van hyprpaper 0.8.x. Er stond nog de
  # oude:
  #     preload   = [ "${"$"}{wallpaper}" ];
  #     wallpaper = [ ",${"$"}{wallpaper}" ];
  # Die is sinds de herschrijving weg: `preload` bestaat niet meer en
  # `wallpaper` is een blok geworden i.p.v. een "monitor,pad"-regel. hyprpaper
  # klaagt daar niet over, hij negeert het gewoon — vandaar dat de wallpaper
  # nooit verscheen en het logboek alleen zei:
  #     Monitor eDP-1 has no target: no wp will be created
  # (Geverifieerd door beide vormen los te draaien en `hyprctl hyprpaper
  # listactive` te vergelijken.)
  #
  # One render per screen. This used to be a single entry with monitor = "" (all
  # screens) pointing at the 1920x1280 version, so on the 3440x1440 ultrawide
  # hyprpaper had to blow it up 1.8x to cover — and that was the zoomed-in, blurry
  # image. Now every screen gets an image that is already the right size and
  # "cover" only has to confirm what already fits.
  #
  # The external entry matches by EDID description (see externalMonitorDesc above)
  # instead of a connector name like DP-6: the MST dock renames the output on
  # every replug, and a stale name makes the rule fall through to the fallback
  # below, which re-blows the laptop render up to ultrawide — the same zoomed
  # wallpaper again.
  #
  # The empty monitor line stays last as a fallback: it catches a screen not named
  # above (a projector, a second external). Without it that screen stays black
  # with "has no target: no wp will be created".
  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false;
      wallpaper = [
        {
          monitor = "${externalMonitorDesc}";
          path = "${wallpaperUltrawide}";
          fit_mode = "cover";
        }
        {
          monitor = "eDP-1";
          path = "${wallpaper}";
          fit_mode = "cover";
        }
        {
          monitor = "";
          path = "${wallpaper}";
          fit_mode = "cover";
        }
      ];
    };
  };

  #### hyprlock (SUPER+L, en via hypridle na 5 min) ##########################
  # Stond er nog niet: hyprlock zat wel in home.packages en in een keybind,
  # maar zonder config viel hij terug op de kale defaults.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 2;             # 2s om te ontsnappen na per ongeluk locken
        no_fade_in = false;
      };

      # Minder blur en minder dimmen dan eerst (was 2 passes / 0.7): de oude
      # wallpaper was een egale gradient, daar zag je toch niets van. Dit doek
      # heeft een compositie die je wél wil herkennen achter het slot.
      background = [
        {
          path = "${wallpaper}";
          blur_passes = 1;
          blur_size = 4;
          brightness = 0.82;
          contrast = 1.05;
          vibrancy = 0.15;
        }
      ];

      input-field = [
        {
          size = "280, 48";
          position = "0, -40";
          halign = "center";
          valign = "center";
          outline_thickness = 2;
          dots_center = true;
          rounding = 12;
          # RRGGBBAA — 8 hex-tekens, niet meer. Kleuren uit ../theme.nix.
          outer_color = "rgba(${raw.haze}80)";
          inner_color = "rgba(${raw.ink}c8)";
          font_color = "rgb(${raw.text})";
          check_color = "rgba(${raw.ochre}ff)"; # tijdens het controleren
          fail_color = "rgb(${raw.alarm})";
          placeholder_text = "<i>Password…</i>";
          fade_on_empty = false;
        }
      ];

      label = [
        {
          # Klok
          text = "cmd[update:1000] date +'%H:%M'";
          font_size = 88;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(${raw.text})";
          position = "0, 160";
          halign = "center";
          valign = "center";
          # Schaduw, want de lucht op deze wallpaper is licht — zonder dit
          # verdwijnt lichte tekst er deels in.
          shadow_passes = 2;
          shadow_size = 4;
          shadow_color = "rgba(${raw.ink}b0)";
        }
        {
          # Datum
          text = "cmd[update:60000] date +'%A %d %B %Y'";
          font_size = 18;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgba(${raw.stone}dd)";
          position = "0, 80";
          halign = "center";
          valign = "center";
          shadow_passes = 2;
          shadow_size = 3;
          shadow_color = "rgba(${raw.ink}b0)";
        }
      ];
    };
  };
}
