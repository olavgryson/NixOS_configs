################################################################################
#  User daemons: battery monitor and external-display gamma service.
################################################################################
{ pkgs, lib, config, ... }:

let
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
in
{
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
}
