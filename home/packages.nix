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
    # Kimi Code — official installer drops the self-updating binary to
    # ~/.kimi-code/bin (nix can't track it), so just expose that on PATH.
    # The installer's binary is built for a generic glibc layout; repatch its
    # interpreter to ours each run (updates overwrite it) so NixOS can exec it.
    (pkgs.writeShellScriptBin "kimi" ''
      BIN="$HOME/.kimi-code/bin/kimi"
      [ -e "$BIN" ] || { echo "kimi not found: $BIN — re-run the installer"; exit 1; }
      INTERP="$(${pkgs.patchelf}/bin/patchelf --print-interpreter "${pkgs.bash}/bin/bash")"
      ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERP" \
        --set-rpath "${pkgs.gcc.cc.lib}/lib" "$BIN"
      exec "$BIN" "$@"
    '')
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

    ## --- editors / IDEs ---
    vscode
    neovim
    jetbrains.idea-oss                 # IntelliJ IDEA (open-source build; idea-community discontinued)
    tmux
    antigravity-ide                    # Google's AI editor

    ## --- terminal / CLI tools ---
    ripgrep fd fzf bat eza zoxide jq yq
    htop btop fastfetch fetch ncdu
    gocryptfs sshfs                    # encrypted FUSE fs + remote ssh mounts
    gnupg pass                         # GnuPG + password-store
    nmap                               # network scanner (CLI)
    imagemagick pandoc                 # image convert + document convert
    unzip zip p7zip tree file wget curl rsync

    ## --- apps (GUI) ---
    obsidian
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
    # DISABLED: not in the binary cache on the current unstable snapshot, so
    # they compile from source (too slow / OOM). Re-enable with one rebuild once
    # the cache has caught up. Alternative for bambu-studio: orca-slicer.
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
}
