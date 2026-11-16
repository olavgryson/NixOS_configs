################################################################################
#  Belgian eID login in Chromium-based browsers.
#  Chromium reads PKCS#11 modules from the user's NSS database; the eID module
#  is registered there on every activation so its store path stays current.
#  pcscd and eid-mw themselves are enabled in configuration.nix.
################################################################################
{ pkgs, lib, ... }:
{
  home.activation.beidNssModule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    db="sql:$HOME/.pki/nssdb"
    mkdir -p "$HOME/.pki/nssdb"
    modutil=${pkgs.nss.tools}/bin/modutil
    $modutil -dbdir "$db" -force -delete "Belgium eID" >/dev/null 2>&1 || true
    $modutil -dbdir "$db" -force -add "Belgium eID" \
      -libfile ${pkgs.eid-mw}/lib/libbeidpkcs11.so >/dev/null
  '';
}
