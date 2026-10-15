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
    # devin: Cognition Devin, terminal coding agent. Upstream releases prebuilt
    # static binaries with man pages. To bump: check static.devin.ai/cli/current/manifest.json.
    (stdenv.mkDerivation rec {
      pname = "devin";
      version = "3000.11.3";
      src = fetchurl {
        url = "https://static.devin.ai/cli/${version}/devin-${version}-x86_64-unknown-linux.tar.gz";
        sha256 = "0zhm2pidy6w340g0jkvmlw36h23bgvbhinq0w7ls7whvq09v3cw3";
      };
      sourceRoot = ".";
      dontBuild = true;
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin share $out/
        chmod +x $out/bin/devin
        runHook postInstall
      '';
      meta = {
        description = "Cognition Devin, terminal coding agent";
        homepage = "https://devin.ai/cli";
        mainProgram = "devin";
      };
    })
    # opencode: upstream releases move fast, so pin the binary tarball
    # directly. To bump: update version + sha256 (served from opencode.ai/files/bin).
    (stdenv.mkDerivation rec {
      pname = "opencode";
      version = "2.0.18";
      src = fetchurl {
        url = "https://opencode.ai/files/bin/${version}/opencode-linux-x64.tar.gz";
        sha256 = "0plk6w793jdgc6w14qw471q0mkyfay06pip4wgnkl212gxxpw9b2";
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
    # cline: autonomous coding agent CLI (https://cline.bot/cli).
    # Upstream bundles precompiled standalone binaries via npm.
    (stdenv.mkDerivation rec {
      pname = "cline";
      version = "3.0.65";
      src = fetchurl {
        url = "https://registry.npmjs.org/@cline/cli-linux-x64/-/cli-linux-x64-${version}.tgz";
        sha256 = "04qdj02c0vw0lfr3wmf4gvvqszh20gm4r8qdk35rzrvav76xqk5a";
      };
      nativeBuildInputs = [ autoPatchelfHook makeBinaryWrapper ];
      buildInputs = [ stdenv.cc.cc.lib ];
      sourceRoot = ".";
      dontStrip = true;
      installPhase = ''
        install -Dm755 package/bin/cline $out/bin/cline
        wrapProgram $out/bin/cline \
          --prefix PATH : ${lib.makeBinPath [ ripgrep git ]}
      '';
      meta = {
        description = "Autonomous coding agent CLI for the terminal";
        homepage = "https://cline.bot/cli";
        mainProgram = "cline";
      };
    })
    github-copilot-cli                 # GitHub Copilot, terminal
    # mistral-vibe: Mistral AI terminal coding agent (vibe CLI, vibe-acp).
    # Disables checkPhase because upstream interactive UI/sandbox tests fail in Nix build environment.
    (mistral-vibe.overridePythonAttrs (o: { doCheck = false; doInstallCheck = false; }))
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
    ansible
    gnumake gcc cmake                  # build toolchain
    sox                                # audio synth/play — timer alarm beep

    ## --- editors / IDEs ---
    vscode
    code-cursor                        # Cursor AI code editor
    neovim
    tmux
    inputs.antigravity-nix.packages.${pkgs.system}.google-antigravity-ide  # Google's AI editor, latest via auto-update flake

    ## --- terminal / CLI tools ---
    ripgrep fd fzf bat eza zoxide jq yq glib
    # Helper to jump to a tab by 0-based index in the active Herdr workspace.
    # Required for AZERTY keyboards where top row keys produce & é " ' ( § è ! ç à
    # instead of digits 1..9, so Herdr's built-in 1..9 range keybinding does not match.
    (pkgs.writeShellScriptBin "herdr-focus-tab" ''
      exec ${pkgs.python3}/bin/python3 - "$@" <<'PYEOF'
import sys, os, subprocess, json

def main():
    if len(sys.argv) < 2:
        return
    try:
        idx = int(sys.argv[1])
    except ValueError:
        return

    bin_path = os.environ.get("HERDR_BIN_PATH", "herdr")
    ws = os.environ.get("HERDR_ACTIVE_WORKSPACE_ID")

    if not ws:
        try:
            snap = subprocess.check_output([bin_path, "api", "snapshot"], stderr=subprocess.DEVNULL)
            ws = json.loads(snap).get("result", {}).get("snapshot", {}).get("focused_workspace_id")
        except Exception:
            pass

    cmd = [bin_path, "tab", "list"]
    if ws:
        cmd.extend(["--workspace", ws])

    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        data = json.loads(out)
        tabs = data.get("result", {}).get("tabs", [])
        if 0 <= idx < len(tabs):
            tab_id = tabs[idx].get("tab_id")
            if tab_id:
                subprocess.run([bin_path, "tab", "focus", tab_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

if __name__ == "__main__":
    main()
PYEOF
    '')
    glow                               # render .md in the terminal
    htop btop fastfetch fetch ncdu
    gocryptfs sshfs                    # encrypted FUSE fs + remote ssh mounts
    gnupg pass                         # GnuPG + password-store
    nmap                               # network scanner (CLI)
    imagemagick pandoc                 # image convert + document convert
    pdftk qpdf poppler-utils           # PDF tools (merge, shuffle, split)
    timg zathura                       # terminal PDF/image viewer and lightweight document viewer
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
    cisco-packet-tracer_9              # Cisco network simulation tool
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
