################################################################################
#  System configuration for dragonflyg4 (HP Dragonfly G4)
#  Rebuilt from Debian 13 inventory — see ./inventory/ and ./README.md
################################################################################
{ config, pkgs, lib, inputs, ... }:

{
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
  services.xserver.xkb = { layout = "be"; model = "pc105"; };

  #### Networking #############################################################
  networking.networkmanager.enable = true;   # 23 saved WiFi nets — rejoin via nmtui or restore from backup (see README)
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

  #### Audio (PipeWire, like current setup) ###################################
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

  #### Printing + scanning (Brother MFCL2800DW, Ricoh SP325) ###################
  services.printing = {
    enable = true;
    drivers = with pkgs; [ brlaser brgenml1lpr gutenprint cups-filters ];
  };
  services.avahi = { enable = true; nssmdns4 = true; openFirewall = true; };  # network printer discovery
  hardware.sane.enable = true;   # scanner; Brother USB scan may need brscan5 (see README note)

  #### Desktop: Hyprland + SDDM (Wayland) #####################################
  programs.hyprland.enable = true;          # sets up portals + session
  programs.hyprland.xwayland.enable = true; # X11 app compatibility
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Polkit + keyring + dconf needed by a bare WM
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  #### Virtualisation / containers / local LLM ################################
  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.waydroid.enable = true;   # Android-container (KU Leuven authenticator e.a.)
  services.ollama.enable = true;   # geen modellen auto-pullen; later handmatig indien gewenst

  #### Gaming #################################################################
  programs.steam.enable = true;   # pulls 32-bit stack
  programs.steam.remotePlay.openFirewall = true;

  #### Swap + hibernate #######################################################
  # zram = fast compressed RAM swap for daily use.
  # The on-disk SWAP partition (>= RAM, see README partitioning) is the
  # hibernate image target.
  zramSwap.enable = true;
  boot.resumeDevice = "/dev/disk/by-label/SWAP";
  # swapDevices for the SWAP partition is normally written by
  # nixos-generate-config (run `swapon /dev/disk/by-label/SWAP` before
  # generating). If it isn't, uncomment:
  #   swapDevices = [ { device = "/dev/disk/by-label/SWAP"; } ];
  powerManagement.enable = true;
  services.logind.lidSwitch = "suspend-then-hibernate";
  systemd.sleep.extraConfig = "HibernateDelaySec=30min";

  #### Fonts #################################################################
  fonts.packages = with pkgs; [
    noto-fonts noto-fonts-emoji noto-fonts-cjk-sans
    liberation_ttf dejavu_fonts
    nerd-fonts.jetbrains-mono nerd-fonts.fira-code
  ];

  #### Users #################################################################
  users.users.ogryson = {
    isNormalUser = true;
    description = "Olav Gryson";
    shell = pkgs.bash;
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

  #### System-level packages (the rest live in home.nix) ######################
  environment.systemPackages = with pkgs; [
    git vim wget curl
    pciutils usbutils
    sbctl                      # secure boot helper (if needed later)
    networkmanagerapplet
  ];

  #### State version — DO NOT change after first install ######################
  system.stateVersion = "25.11";
}
