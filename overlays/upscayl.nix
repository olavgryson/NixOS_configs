# Override Upscayl so the onboarding wizard is dismissed permanently.
#
# Upscayl only persists the `showOnboarding` localStorage flag when the user
# clicks through all four wizard steps to the final "Get Started" button.
# Closing the dialog early (X, Escape, backdrop) or at the broken embedded
# YouTube step leaves the flag unset, so the wizard reappears on every launch.
#
# Fix: make ANY dialog close write `showOnboarding=false`, by patching the
# dialog's onOpenChange handler in the bundled app.asar. The AppImage is
# re-extracted, patched and re-wrapped here so the change survives rebuilds.
final: prev:
let
  appimageContents = prev.appimageTools.extractType2 {
    pname = "upscayl";
    version = prev.upscayl.version;
    src = prev.upscayl.src;
    postExtract = ''
      workdir=$(mktemp -d)
      ${prev.asar}/bin/asar extract "$out/resources/app.asar" "$workdir/app"
      chunk=$(find "$workdir/app" -path '*/chunks/pages/index-*.js' | head -n1)
      ${prev.gnused}/bin/sed -i \
        's|onOpenChange:e=>{o(e)}|onOpenChange:e=>{o(e),localStorage.setItem("showOnboarding",JSON.stringify(!1))}|' \
        "$chunk"
      ${prev.gnugrep}/bin/grep -q 'onOpenChange:e=>{o(e),localStorage' "$chunk" \
        || { echo "upscayl overlay: onboarding patch pattern not found"; exit 1; }
      ${prev.asar}/bin/asar pack "$workdir/app" "$out/resources/app.asar"
      rm -rf "$workdir"
    '';
  };
in
{
  upscayl = prev.appimageTools.wrapAppImage {
    pname = "upscayl";
    version = prev.upscayl.version;
    src = prev.upscayl.src;
    meta = prev.upscayl.meta;
    contents = appimageContents;
    nativeBuildInputs = [ prev.makeWrapper ];
    extraPkgs = pkgs: [ pkgs.vulkan-headers pkgs.vulkan-loader ];
    extraInstallCommands = ''
      install -D ${appimageContents}/upscayl.desktop -t $out/share/applications
      install -D ${appimageContents}/upscayl.png -t $out/icons/hicolor/512x512/apps
      substituteInPlace $out/share/applications/upscayl.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=upscayl'
      wrapProgram $out/bin/upscayl \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
    '';
  };
}
