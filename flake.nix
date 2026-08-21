{
  description =
    "Olav's NixOS config — HP Dragonfly G4 (dragonflyg4) + HP ProBook 650 G2 (probook650), Hyprland desktop";

  inputs = {
    # Unstable gives the freshest Hyprland + Wayland stack. Pin to a release
    # (e.g. nixos-25.11) later if you want more stability over newness.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen browser ships via its own flake (moves fast, not via nixpkgs).
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Antigravity CLI + IDE: nixpkgs lags weeks behind Google's near-daily
    # releases, so take them from this auto-updating (3x/week) flake instead.
    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      # One host template: both machines share every module and differ only in
      # their generated hardware-configuration.nix. `hostName` is threaded
      # through to the system modules AND the home-manager modules, so anything
      # machine-specific (monitor layout, rebuild alias, host-only packages)
      # can branch on it instead of living in duplicated files.
      mkHost = hostName: hardwareModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hostName; };
          modules = [
            hardwareModule               # machine-specific, generated (see README)
            ./configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # Without this a rebuild stops with "Existing file ... is in the way"
              # as soon as home-manager wants to manage a file that already exists
              # by hand. With a backup extension it renames the old file to
              # <name>.hm-bak and carries on, so nothing is lost.
              home-manager.backupFileExtension = "hm-bak";
              home-manager.users.ogryson = import ./home.nix;
              home-manager.extraSpecialArgs = { inherit inputs hostName; };
            }
          ];
        };
    in {
      nixosConfigurations.dragonflyg4 = mkHost "dragonflyg4" ./hardware-configuration.nix;
      nixosConfigurations.probook650  = mkHost "probook650"  ./hardware-probook650.nix;
    };
}
