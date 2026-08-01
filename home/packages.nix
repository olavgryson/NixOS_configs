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
    opencode                           # AI coding agent, terminal
    github-copilot-cli                 # GitHub Copilot, terminal
    antigravity-cli                    # Google Antigravity, terminal (Go TUI agent client)
    # gemini-cli: removed. Google cut this client off from Gemini Code Assist for
    # individuals — "Sign in with Google" now fails and points at Antigravity.
    # Only a paid Gemini API key or Vertex AI still authenticates, so it buys
    # nothing over antigravity-cli above.

    ## --- browsers ---
    firefox
    chromium                                              # kept: drives the web-app launchers (--app=)
    librewolf                                             # extra hardened Firefox fork
    inputs.zen-browser.packages.${pkgs.system}.default    # Zen (replaces Brave)

    ## --- dev tooling ---
    gh lazygit
    nodejs_22 corepack_22 bun
    python313 uv
    # pipx 1.14.0's testsuite is stuk met de nieuwe pytest (parametrize-signatuur);
    # de tool zelf werkt prima, dus we bouwen 'm met tests uit.
    (pipx.overridePythonAttrs (o: { doCheck = false; doInstallCheck = false; }))
    php sqlite postgresql redis        # db clients / runtimes (php-mysql, postgresql-client, redis-server)
    docker-compose
    gnumake gcc cmake                  # build toolchain

    ## --- editors / IDEs ---
    vscode
    neovim
    jetbrains.idea-oss                 # IntelliJ IDEA (open-source build; idea-community discontinued)
    tmux
    antigravity-ide                    # Google's AI editor — now in nixpkgs, no more manual packaging

    ## --- terminal / CLI tools (detected on your Debian box) ---
    ripgrep fd fzf bat eza zoxide jq yq
    htop btop fastfetch fetch ncdu
    gocryptfs sshfs                    # encrypted FUSE fs + remote ssh mounts
    gnupg pass                         # GnuPG + password-store (your password manager)
    nmap                               # network scanner (CLI)
    imagemagick pandoc                 # image convert + document convert
    unzip zip p7zip tree file wget curl rsync

    ## --- apps (GUI) ---
    obsidian
    discord
    spotify
    vlc                                # mpv staat niet hier: zie programs.mpv onderaan
    obs-studio
    libreoffice-fresh hunspell hunspellDicts.nl_NL hunspellDicts."en_GB-ise"
    angryipscanner                     # network scanner GUI (was Flatpak)
    handy                              # local Whisper push-to-talk dictation, fully offline
    upscayl                            # AI image upscaler GUI

    ## --- creative / 3D / making ---
    blender
    # TIJDELIJK UITGEZET (compileren van bron in deze verse unstable-snapshot,
    # nog niet gecached -> te traag/OOM). Later terugzetten met één nixos-rebuild,
    # of wanneer de binary cache is bijgewerkt. Alternatief voor bambu: orca-slicer.
    # krita
    # bambu-studio                     # Bambu Lab 3D-printer slicer

    ## --- wine / gaming extras ---
    # wineWowPackages.stable           # TIJDELIJK UITGEZET (bron-compile, zie boven)
    winetricks
  ];

  ## --- mpv: hardware video decoding op de Iris Xe (VAAPI/iHD) ---------------
  #  mpv's default is hwdec=no, dus 1080p HEVC werd volledig op de CPU gedecodeerd
  #  (~43% van een core i.p.v. ~17%). auto-safe kiest vaapi en valt netjes terug
  #  als dat ooit niet beschikbaar is. Installeert mpv zelf, vandaar niet in
  #  home.packages hierboven (anders botsen de twee in het profiel).
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
    };
  };
}
