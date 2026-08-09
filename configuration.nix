################################################################################
#  System configuration for dragonflyg4 (HP Dragonfly G4)
################################################################################
{ config, pkgs, lib, inputs, ... }:

let
  # One fixed, argument-less rebuild command. Deliberately a script rather than
  # a sudoers rule with loose arguments, for two reasons:
  #   1. A sudoers rule like `nixos-rebuild switch --flake /path#dragonflyg4`
  #      does not work: '#' starts a comment in sudoers, so the flake attribute
  #      would silently disappear and the rule would never match.
  #   2. With no arguments there is nothing to vary — no other flake path, no
  #      subcommand other than `switch`.
  nixosRebuildSwitch = pkgs.writeShellScript "nixos-rebuild-switch" ''
    exec /run/current-system/sw/bin/nixos-rebuild switch \
      --flake /home/ogryson/nixos-config#dragonflyg4
  '';
in

{
  imports = [
    ./greeter.nix   # login screen: greetd + ReGreet inside Hyprland
  ];

  #### Boot / firmware ########################################################
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;   # keep ESP from overflowing
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;     # good Raptor Lake support

  #### Nix #####################################################################
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nixpkgs.config.allowUnfree = true;   # spotify, vscode, discord, steam, obsidian...
  # IntelliJ IDEA (idea-oss) is flagged insecure over a CVE in the bundled
  # JetBrains runtime. Allowed by name, so it survives version bumps.
  nixpkgs.config.allowInsecurePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "idea-oss" ];

  #### Identity / locale ######################################################
  networking.hostName = "dragonflyg4";
  time.timeZone = "Europe/Brussels";
  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "nl_BE.UTF-8";
    LC_MONETARY = "nl_BE.UTF-8";
    LC_PAPER = "nl_BE.UTF-8";
  };
  console.keyMap = "be-latin1";
  services.xserver.xkb = { layout = "be"; model = "pc105"; options = "caps:digits_row"; };

  #### Networking #############################################################
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;

  #### Graphics (Intel Iris Xe / Raptor Lake) #################################
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # iHD — Raptor Lake VAAPI
      vpl-gpu-rt           # QSV / oneVPL
      libvdpau-va-gl
    ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  #### Audio (PipeWire) #######################################################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  #### Bluetooth ##############################################################
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # blueman in home.packages alone gives you the GUI but not the system side:
  # blueman-mechanism (the D-Bus system service) and its polkit rules. Without
  # those two, blueman-manager may not power the adapter on, may not
  # rfkill-unblock and cannot start a scan — the "no devices found" symptom.
  services.blueman.enable = true;

  # systemd-rfkill persists the block state in /var/lib/systemd/rfkill/ and
  # restores it on every boot. So one press of the airplane-mode key blocks
  # bluetooth permanently; powerOnBoot above cannot undo that, since it only
  # powers the adapter on and does not lift the rfkill block.
  systemd.services.bluetooth-rfkill-unblock = {
    description = "Lift the bluetooth rfkill block after boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-rfkill.service" "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/rfkill unblock bluetooth";
    };
  };

  #### Printing + scanning (Brother MFCL2800DW, Ricoh SP325) ###################
  services.printing = {
    enable = true;
    drivers = with pkgs; [ brlaser brgenml1lpr gutenprint cups-filters ];
  };
  services.avahi = { enable = true; nssmdns4 = true; openFirewall = true; };  # network printer discovery
  hardware.sane.enable = true;   # scanner; Brother USB scan may need brscan5

  #### Fingerprint reader (Synaptics 06cb:0104) ###############################
  # fprintd + libfprint's synaptics driver. Enabling the service is enough:
  # `security.pam.services.*.fprintAuth` defaults to services.fprintd.enable,
  # so every PAM consumer (login screen, sudo, polkit, hyprlock) gets the
  # reader as a `sufficient` step with the password still as fallback.
  # Enrol per user, once: `fprintd-enroll` (repeat with -f for more fingers),
  # check with `fprintd-list $USER`.
  services.fprintd.enable = true;

  #### Desktop: Hyprland (Wayland) ############################################
  programs.hyprland.enable = true;          # sets up portals + session
  programs.hyprland.xwayland.enable = true; # X11 app compatibility
  # The login screen lives in ./greeter.nix (greetd + ReGreet).
  # LEAVE withUWSM OFF unless you adapt ./greeter.nix too — see the note there.

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Polkit + keyring + dconf needed by a bare WM
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  # SwayOSD (the volume/brightness popup, see home/desktop.nix) writes
  # brightness straight to /sys/class/backlight — root-only until this udev
  # rule chgrps the knob to `video`. brightnessctl did not need this because it
  # goes through logind over D-Bus; swayosd does not.
  # `video` is already in extraGroups below.
  services.udev.packages = [ pkgs.swayosd ];

  # Brightness on the EXTERNAL screen travels a completely different path than the
  # laptop panel's. /sys/class/backlight exists only for the internal panel, where
  # the GPU drives the LED driver directly. A monitor on DisplayPort has its own
  # electronics and only listens to DDC/CI: commands over the little i2c channel
  # that rides along in the DP cable, the same bus the EDID is read over.
  #
  # This enables the i2c-dev module, creates /dev/i2c-* and grants group `i2c`
  # access to them (ogryson is already in that group, see extraGroups below).
  # Without this, /dev/i2c-* does not exist and ddcutil says "No displays found".
  #
  # NOTE: this is necessary but not sufficient on the current setup — the dock
  # speaks DP-MST and never exposes a bus for the connector the monitor lands on.
  # See the long note at brightnessExternal in home/desktop.nix.
  hardware.i2c.enable = true;

  #### Virtualisation / containers / local LLM ################################
  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  services.ollama.enable = true;   # no models auto-pulled; pull manually when needed

  #### Gaming #################################################################
  programs.steam.enable = true;   # pulls 32-bit stack
  programs.steam.remotePlay.openFirewall = true;

  #### Swap + hibernate #######################################################
  # zram = fast compressed RAM swap for daily use.
  # The on-disk SWAP partition (>= RAM, see README) is the hibernate image
  # target.
  zramSwap.enable = true;
  boot.resumeDevice = "/dev/disk/by-label/SWAP";
  # swapDevices for the SWAP partition is normally written by
  # nixos-generate-config (run `swapon /dev/disk/by-label/SWAP` before
  # generating). If it isn't, uncomment:
  #   swapDevices = [ { device = "/dev/disk/by-label/SWAP"; } ];
  # The IPU6 MIPI camera stack is kept out of the kernel entirely, because it is
  # what breaks hibernation. After the memory snapshot the driver has to
  # re-authenticate its firmware with the CSE, times out, and takes the whole
  # hibernation attempt down with it:
  #     intel-ipu6 0000:00:05.0: Unexpected magic number 0xffffffeb
  #     intel-ipu6 0000:00:05.0: FW authentication failed(-110)
  #     PM: hibernation: hibernation exit      <- image discarded, 0B written
  #
  # Nothing is lost by removing it: the camera does not work on this host anyway.
  # The kernel side loads and binds the hi556 sensor, but that only produces ~32
  # raw ISYS /dev/video* nodes that no application can open. A usable camera
  # needs `hardware.ipu6.enable = true` (v4l2-relayd + icamerasrc), which is not
  # set here -- and enabling it would not help hibernation, since a working
  # pipeline still has to survive that same firmware re-authentication.
  #
  # If the webcam is ever wanted back, the trade is explicit: either give up
  # hibernation again, or try unloading these modules from
  # powerManagement.powerDownCommands instead of blacklisting them (note
  # intel_ipu6_isys currently sits at refcount 3, so `modprobe -r` may refuse).
  boot.blacklistedKernelModules = [
    "intel_ipu6_isys"
    "intel_ipu6"
    "ipu_bridge"
    "hi556" # camera sensor driver, useless without the IPU6 above
  ];

  powerManagement.enable = true;

  # Log the battery level on either side of every sleep. With hibernation
  # unavailable (see below), how much plain s2idle suspend actually costs per
  # hour is what decides whether the laptop survives a night unplugged, and
  # that was never measured -- every previous overnight drain was the failed
  # hibernate sitting there powered, not suspend itself. Both hooks land in one
  # unit on 26.11 (ExecStart before sleep, ExecStop on resume), so read the
  # pairs back with:  journalctl -u sleep-actions
  powerManagement.powerDownCommands = ''
    echo "battery before sleep: $(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity)% ($(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status))"
  '';
  powerManagement.powerUpCommands = ''
    echo "battery after resume: $(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/capacity)% ($(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT0/status))"
  '';
  services.power-profiles-daemon.enable = true;

  #### Power Management & UPower Daemon #######################################
  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 10;
    percentageAction = 5;
    criticalPowerAction = "Suspend";
    allowRiskyCriticalPowerAction = true;
  };

  # NB: `services.logind.lidSwitch` and `.lidSwitchDocked` still exist as aliases
  # but emit an evaluation warning as of 26.11; these are the current names.
  # Plain suspend on lid close. This was "suspend-then-hibernate", which is what
  # killed the battery every night: 30 min after the lid closed the machine tried
  # to hibernate, the attempt aborted in the driver layer without ever writing an
  # image (see the long note at the hypridle listener in home/desktop.nix), and
  # it then sat frozen and powered until morning. Do not put it back until
  # `systemctl hibernate` is verified to actually power the machine off.
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  # Lid closed WITH an external screen attached: do not sleep, keep working.
  # logind calls that "docked" and counts "more than one display connected" as
  # docked too, so this covers the ultrawide with or without a docking station.
  # "ignore" is already the upstream default, but it is spelled out here because
  # the line above otherwise reads as "lid closed = always sleep", which is exactly
  # the behaviour we do not want.
  services.logind.settings.Login.HandleLidSwitchDocked = "ignore";

  # Sleep tuning. Both settings below work around firmware behaviour on this
  # machine that was killing the battery overnight; see the diagnosis in each.
  systemd.sleep.settings.Sleep = {
    # After 30 min of plain suspend, move the session to disk and power off.
    HibernateDelaySec = "30min";

    # HibernateMode is the value systemd writes to /sys/power/disk. The default
    # is "platform", which hands the S4 transition to the ACPI firmware -- and
    # this firmware botches it. The kernel takes the memory snapshot fine, then:
    #     ACPI: PM: Preparing to enter system sleep state S4
    #     ACPI: PM: Waking up from system sleep state S4
    #     PM: hibernation: Basic memory bitmaps freed
    #     PM: hibernation: hibernation exit
    # It wakes straight back out of S4, so the image is NEVER written to the
    # resume device and hibernation aborts. Worse, the machine does not come
    # back either: it sits in a shallow, power-hungry state with all tasks
    # frozen until the lid is opened, by which time the battery is flat and the
    # session is unusable (stale lockscreen clock, dead input, needs a forced
    # power-off). No hibernate image has ever been written on this host.
    #
    # "shutdown" skips ACPI S4 completely: the kernel writes the image to
    # boot.resumeDevice itself and then does an ordinary poweroff.
    HibernateMode = "shutdown";

    # DO NOT set MemorySleepMode = "deep" here. The firmware advertises real S3
    # (ACPI: PM: (supports S0 S3 S4 S5), and `deep` is listed in
    # /sys/power/mem_sleep), and s2idle is a battery hog by comparison, so S3
    # looks like an easy win -- but it does not wake up on this machine. Tested
    # 2026-07-30: the kernel logged
    #     PM: suspend entry (deep)
    # and that was the last line ever written. The fans spin back up on a power
    # button press, the panel stays black, input is dead and only a forced
    # power-off recovers it. Leave suspend on the kernel default (s2idle) and
    # rely on HibernateDelaySec above to get off the battery overnight.
  };

  #### Removable media (USB drives, SD cards) #################################
  # Hyprland is a bare compositor with no session daemon watching udisks2, so
  # without this, plugging in a USB drive creates the block device but nothing
  # mounts it — udisksd wasn't even running (`systemctl status udisks2` showed
  # "could not be found"). udisks2 is the daemon that actually claims and
  # mounts removable media; gvfs is what lets Nautilus/Thunar (home/desktop.nix)
  # show and browse those mounts via GIO. udiskie (home/desktop.nix) is the
  # piece that watches udisks2 and triggers the automount on plug-in itself.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  #### External backup disk ###################################################
  # Kingston SV300S37A240G, 240G, ext4, label `backup`.
  #
  # Mounted on demand instead of at boot. With a plain `nofail` +
  # device-timeout, every boot without the disk plugged in still waited for it
  # and then printed four red lines on the console:
  #     Timed out waiting for device /dev/disk/by-uuid/8b16bf94-...
  #     Dependency failed for File System Check on /dev/disk/by-uuid/8b16bf94-...
  #     Dependency failed for /mnt/backup.
  # `noauto` + `x-systemd.automount` moves the mount to first access: nothing
  # happens at boot, and touching /mnt/backup mounts the disk if it is there.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/8b16bf94-9d1d-4923-8b0d-75f4921ea144";
    fsType = "ext4";
    options = [
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.device-timeout=5s"
      "noatime"
    ];
  };

  #### Fonts #################################################################
  fonts.packages = with pkgs; [
    noto-fonts noto-fonts-color-emoji noto-fonts-cjk-sans
    liberation_ttf dejavu_fonts
    nerd-fonts.jetbrains-mono nerd-fonts.fira-code
  ];

  #### Users #################################################################
  users.users.ogryson = {
    isNormalUser = true;
    description = "Olav Gryson";
    shell = pkgs.bash;
    # TEMPORARY — change on first boot with `passwd`. Root stays locked
    # (install with --no-root-passwd); administration goes through sudo (wheel).
    initialPassword = "changeme";
    extraGroups = [
      "wheel"          # sudo
      "networkmanager"
      "audio" "video" "render"
      "docker" "libvirt" "kvm"
      "lp" "scanner"   # printing / scanning
      "dialout" "plugdev" "i2c"
      "ollama"
    ];
  };

  # Passwordless sudo for exactly one command: the rebuild script above.
  # Everything else still asks for a password (wheel).
  # WARNING: that script builds from /home/ogryson/nixos-config, a directory the
  # user can write to. Anyone who can write there can therefore run arbitrary
  # code as root through this rule. In practice this is not a "rebuild only"
  # privilege but full passwordless root.
  security.sudo.extraRules = [
    {
      users = [ "ogryson" ];
      commands = [
        {
          command = "${nixosRebuildSwitch}";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  #### System-level packages (the rest live in home.nix) ######################
  environment.systemPackages = with pkgs; [
    git vim wget curl
    pciutils usbutils
    sbctl                      # secure boot helper (if needed later)
    networkmanagerapplet
    # Short name for the passwordless rebuild command above.
    (writeShellScriptBin "rebuild" ''
      exec sudo ${nixosRebuildSwitch}
    '')
  ];

  #### State version — DO NOT change after first install ######################
  system.stateVersion = "25.11";
}
