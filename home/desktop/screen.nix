################################################################################
#  Lock, idle and wallpaper: hypridle, hyprlock, hyprpaper.
################################################################################
{ pkgs, lib, config, hostName, ... }:

let
  monitors = import ./monitors.nix { inherit pkgs hostName; };
  inherit (monitors) wallpaper wallpaperUltrawide externalMonitorDesc;
  theme = import ../../theme.nix { };
  inherit (theme) raw;

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

  # Reads the AC line (1 = charger plugged). Exits 0 when on AC power.
  onAc = pkgs.writeShellScript "on-ac" ''
    [ "$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/AC/online)" = "1" ]
  '';
in
{
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
        # Skip lock and suspend while on AC power, so a long-running command
        # left unattended on the desk cannot stall behind a sleep/lock.
        # `/sys/class/power_supply/AC/online` is 1 when the charger is plugged.
        { timeout = 300;  on-timeout = "${onAc} || loginctl lock-session"; }
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
        { timeout = 900;  on-timeout = "${onAc} || systemctl suspend"; }
      ];
    };
  };
  # the login screen, desktop and lock screen all follow.
  #
  # NOTE — the syntax below is hyprpaper 0.8.x. The pre-rewrite form
  #     preload   = [ "${"$"}{wallpaper}" ];
  #     wallpaper = [ ",${"$"}{wallpaper}" ];
  # is gone: `preload` no longer exists and `wallpaper` is a block instead of a
  # "monitor,path" line. hyprpaper does not complain about the old form, it
  # simply ignores it — the wallpaper never appears and the only trace in the
  # log is:
  #     Monitor eDP-1 has no target: no wp will be created
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
      wallpaper =
        lib.optionals (externalMonitorDesc != null) [
          {
            monitor = "${externalMonitorDesc}";
            path = "${wallpaperUltrawide}";
            fit_mode = "cover";
          }
        ] ++ [
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
  # Configured here rather than only installed: without a config hyprlock falls
  # back to bare defaults.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 2;             # 2s to escape after locking by accident
        no_fade_in = false;
      };

      # Light blur and dimming on purpose: this wallpaper has a composition
      # worth recognising behind the lock screen, unlike a flat gradient.
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
          # RRGGBBAA — 8 hex characters, no more. Colours from ../theme.nix.
          outer_color = "rgba(${raw.haze}80)";
          inner_color = "rgba(${raw.ink}c8)";
          font_color = "rgb(${raw.text})";
          check_color = "rgba(${raw.ochre}ff)"; # while the password is checked
          fail_color = "rgb(${raw.alarm})";
          placeholder_text = "<i>Password…</i>";
          fade_on_empty = false;
        }
      ];

      label = [
        {
          # Clock
          text = "cmd[update:1000] date +'%H:%M'";
          font_size = 88;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(${raw.text})";
          position = "0, 160";
          halign = "center";
          valign = "center";
          # Shadow, because the sky in this wallpaper is light — without it
          # light text partly disappears into it.
          shadow_passes = 2;
          shadow_size = 4;
          shadow_color = "rgba(${raw.ink}b0)";
        }
        {
          # Date
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
