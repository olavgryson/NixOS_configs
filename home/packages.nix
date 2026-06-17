################################################################################
#  User packages — apps, dev tooling, CLI/terminal tools.
#  (Hyprland/Wayland desktop packages live in ./desktop.nix.)
#  home.packages merges across modules, so this list is desktop-free on purpose.
################################################################################
{ pkgs, inputs, ... }:
{
  home.packages = with pkgs; [
    ## --- the thing you want first ---
    claude-code

    ## --- browsers ---
    firefox
    chromium                                              # kept: drives the web-app launchers (--app=)
    librewolf                                             # extra hardened Firefox fork
    inputs.zen-browser.packages.${pkgs.system}.default    # Zen (replaces Brave)

    ## --- dev tooling ---
    gh lazygit
    nodejs_22 corepack_22 bun
    python313 uv pipx
    php sqlite postgresql redis        # db clients / runtimes (php-mysql, postgresql-client, redis-server)
    docker-compose
    gnumake gcc cmake                  # build toolchain

    ## --- editors / IDEs ---
    vscode
    neovim
    jetbrains.idea-community           # IntelliJ IDEA Community (free) — confirmed
    tmux
    # antigravity (Google's AI editor) is NOT in nixpkgs — packaged separately
    # from the official download on the new machine (see README "Antigravity").

    ## --- terminal / CLI tools (detected on your Debian box) ---
    ripgrep fd fzf bat eza zoxide jq yq
    htop btop fastfetch ncdu
    gocryptfs sshfs                    # encrypted FUSE fs + remote ssh mounts
    gnupg pass                         # GnuPG + password-store (your password manager)
    nmap                               # network scanner (CLI)
    imagemagick pandoc                 # image convert + document convert
    unzip zip p7zip tree file wget curl rsync

    ## --- apps (GUI) ---
    obsidian
    discord
    spotify
    vlc mpv
    obs-studio
    libreoffice-fresh hunspell hunspellDicts.nl_BE hunspellDicts.en_GB
    angryipscanner                     # network scanner GUI (was Flatpak)

    ## --- creative / 3D / making ---
    blender
    krita
    bambu-studio                       # Bambu Lab 3D-printer slicer

    ## --- wine / gaming extras ---
    wineWowPackages.stable winetricks
  ];
}
