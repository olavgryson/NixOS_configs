################################################################################
#  User packages — apps, dev tooling, CLI/terminal tools.
#  (Hyprland/Wayland desktop packages live in ./desktop.nix.)
#  home.packages merges across modules, so this list is desktop-free on purpose.
################################################################################
{ pkgs, inputs, ... }:
{
  home.packages = with pkgs; [
    ## --- the thing you want first ---
    # claude-code comes from nixpkgs, which tracks Claude's release cadence.
    # Do NOT pin the tarball with overrideAttrs: upstream changes the binary
    # format without notice and a pinned fetchurl then stops unpacking.
    claude-code                        # Anthropic Claude, terminal coding agent
    codex                              # OpenAI Codex, terminal coding agent
    # opencode: upstream releases move fast, so pin the binary tarball
    # directly. To bump: update version + sha256 from github releases.
    (stdenv.mkDerivation rec {
      pname = "opencode";
      version = "1.18.21";
      src = fetchurl {
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
        sha256 = "12mkjnljc15bk4qhwivb79ymphhwshald418lf8mgfqkfvnw646r";
      };
      nativeBuildInputs = [ autoPatchelfHook makeBinaryWrapper ];
      buildInputs = [ stdenv.cc.cc.lib ];
      sourceRoot = ".";
      dontStrip = true;
      installPhase = ''
        install -Dm755 opencode $out/bin/opencode
        wrapProgram $out/bin/opencode \
          --prefix PATH : ${lib.makeBinPath [ ripgrep ]} \
          --set OPENCODE_DISABLE_AUTOUPDATE true
      '';
      meta = {
        description = "AI coding agent built for the terminal";
        homepage = "https://github.com/anomalyco/opencode";
        mainProgram = "opencode";
      };
    })
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
    # jetbrains.idea-oss                 # DISABLED: source compile on current snapshot
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
    gnome-calculator                    # GUI calculator
    spotify
    vlc                                # mpv is not here: see programs.mpv below
    obs-studio
    libreoffice-stable hunspell hunspellDicts.nl_NL hunspellDicts."en_GB-ise"
    angryipscanner                     # network scanner GUI
    # Dictation stack (~/.local/dict, bound to $mod+F5 and $mod+F7).
    # whisper-cpp-vulkan, not plain whisper-cpp: the Iris Xe GPU runs
    # large-v3-turbo ~2.7x realtime where the CPU backend needs 8x realtime,
    # and the CPU backend's repacked-quant path returns token soup for the
    # q5_0 large models — same file transcribes correctly on Vulkan.
    whisper-cpp-vulkan                 # whisper-cli, GPU-accelerated
    wtype                              # types the transcript into the focused window
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
  ];

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
