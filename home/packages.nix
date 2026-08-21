################################################################################
#  User packages — apps, dev tooling, CLI/terminal tools.
#  (Hyprland/Wayland desktop packages live in ./desktop.nix.)
#  home.packages merges across modules, so this list is desktop-free on purpose.
################################################################################
{ pkgs, inputs, hostName, lib, ... }:
let
  # idea-oss has no cached binary on some nixpkgs snapshots and then compiles
  # from source, which OOMs the small-RAM machines. Keep it on the big laptop
  # only; re-enable per host if a snapshot with a cached build lands.
  bigMachine = hostName == "dragonflyg4";
in
{
  home.packages = with pkgs;
    [
    ## --- the thing you want first ---
    # claude-code: nixpkgs lags behind Claude's release cadence (ships 2.1.234
    # while upstream is at 2.1.237), so pin the tarball ourselves. To bump:
    # `nix-prefetch-url --type sha256 <releases-url>/<version>/linux-x64/claude`
    # and update version+sha256 here.
    (claude-code.overrideAttrs (old: {
      version = "2.1.237";
      src = pkgs.fetchurl {
        url = "https://downloads.claude.ai/claude-code-releases/2.1.237/linux-x64/claude";
        sha256 = "05irzfmk91s58z9gbgkf8nwfnmqng2a4jqfndz7r71hhy1km35vk";
      };
    }))
    codex                              # OpenAI Codex, terminal coding agent
    opencode                           # AI coding agent, terminal
    github-copilot-cli                 # GitHub Copilot, terminal
    inputs.antigravity-nix.packages.${pkgs.system}.google-antigravity-cli  # agy, latest via auto-update flake
    # gemini-cli: removed. Google cut this client off from Gemini Code Assist
    # for individuals — "Sign in with Google" fails and points at Antigravity.
    # Only a paid Gemini API key or Vertex AI still authenticates, so it buys
    # nothing over antigravity-cli above.

    ## --- browsers ---
    firefox
    chromium                                              # drives the web-app launchers (--app=)
    librewolf                                             # extra hardened Firefox fork
    inputs.zen-browser.packages.${pkgs.system}.default    # Zen

    ## --- dev tooling ---
    gh lazygit
    nodejs_22 corepack_22 bun
    python313 uv
    # pipx 1.14.0's test suite is broken against the new pytest (parametrize
    # signature); the tool itself works, so build it with tests disabled.
    (pipx.overridePythonAttrs (o: { doCheck = false; doInstallCheck = false; }))
    php sqlite postgresql redis        # db clients / runtimes (php-mysql, postgresql-client, redis-server)
    docker-compose
    gnumake gcc cmake                  # build toolchain
    sox                                # audio synth/play — timer alarm beep

    ## --- editors / IDEs ---
    vscode
    neovim
    tmux
    inputs.antigravity-nix.packages.${pkgs.system}.google-antigravity-ide  # Google's AI editor, latest via auto-update flake

    ## --- terminal / CLI tools ---
    ripgrep fd fzf bat eza zoxide jq yq glib
    glow                               # render .md in the terminal
    htop btop fastfetch fetch ncdu
    gocryptfs sshfs                    # encrypted FUSE fs + remote ssh mounts
    gnupg pass                         # GnuPG + password-store
    nmap                               # network scanner (CLI)
    imagemagick pandoc                 # image convert + document convert
    pdftk qpdf poppler-utils           # PDF tools (merge, shuffle, split)
    unzip zip p7zip tree file wget curl rsync

    ## --- apps (GUI) ---
    # Obsidian ignores the system dark-mode preference (its Chromium build never
    # queries gtk-application-prefer-dark-theme), so force Chromium's own switch.
    (pkgs.writeShellScriptBin "obsidian" ''
      exec ${pkgs.obsidian}/bin/obsidian --force-dark-mode "$@"
    '')
    discord
    spotify
    vlc                                # mpv is not here: see programs.mpv below
    obs-studio
    libreoffice-fresh hunspell hunspellDicts.nl_NL hunspellDicts."en_GB-ise"
    angryipscanner                     # network scanner GUI
    handy                              # local Whisper push-to-talk dictation, fully offline
    upscayl                            # AI image upscaler GUI

    ## --- creative / 3D / making ---
    blender
    f3d                                # fast 3D viewer (glTF/glb, obj, stl)
    # Slicer + .3mf handler (see desktop/packages.nix). Orca Slicer (a Bambu
    # Studio fork) opens the BambuStudio-format 3MF files it exports, which
    # f3d's Assimp importer and PrusaSlicer both reject. Do NOT switch to
    # bambu-studio: not in the binary cache on this flake's locked nixpkgs, so
    # it compiles wxWidgets from source and OOMs this laptop.
    orca-slicer
    # DISABLED: source compile on this snapshot, too slow / OOM.
    # krita
    # bambu-studio                     # Bambu Lab 3D printer slicer

    ## --- wine / gaming extras ---
    # wineWowPackages.stable           # DISABLED: source compile, see above
    winetricks
  ]
  # IntelliJ IDEA (open-source build; idea-community discontinued). Big
  # machine only — see `bigMachine` above.
  ++ lib.optionals bigMachine [ jetbrains.idea-oss ];

  ## --- mpv: hardware video decoding on the Iris Xe (VAAPI/iHD) -------------
  #  mpv defaults to hwdec=no, so 1080p HEVC was decoded entirely on the CPU
  #  (~43% of a core instead of ~17%). auto-safe picks vaapi and falls back
  #  cleanly if it is ever unavailable. This installs mpv itself, which is why
  #  it is not in home.packages above (the two would collide in the profile).
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
    };
  };

  # Obsidian is installed via the wrapper above, which is all that lands in the
  # profile — obsidian's own obsidian.desktop + icon never get there, so the
  # launcher would not find it. Restore the entry here, following webapps.nix.
  xdg.desktopEntries."obsidian" = {
    name = "Obsidian";
    comment = "Knowledge base";
    exec = "obsidian %u";
    icon = "${pkgs.obsidian}/share/icons/hicolor/512x512/apps/obsidian.png";
    terminal = false;
    categories = [ "Office" ];
    mimeType = [ "x-scheme-handler/obsidian" ];
  };
}
