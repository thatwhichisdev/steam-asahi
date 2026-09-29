{
  description = "Native ARM64 Steam for NixOS on Apple Silicon / Asahi Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      steam-asahi = pkgs.callPackage ./pkgs/steam-asahi { };

      moduleConfig =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./modules/steam-asahi.nix
            {
              programs.steam-asahi = {
                enable = true;
                users = [ "steam-test" ];
                extraLibraries = [ pkgs.libnotify ];
              };
              users.users.steam-test.isNormalUser = true;
              system.stateVersion = "26.05";
            }
          ];
        }).config;
    in
    {
      packages.${system} = {
        inherit steam-asahi;
        default = steam-asahi;
      };

      apps.${system} = {
        steam-asahi = {
          type = "app";
          program = nixpkgs.lib.getExe steam-asahi;
          meta.description = steam-asahi.meta.description;
        };

        default = {
          type = "app";
          program = nixpkgs.lib.getExe steam-asahi;
          meta.description = steam-asahi.meta.description;
        };
      };

      nixosModules = rec {
        steam-asahi = import ./modules/steam-asahi.nix;
        default = steam-asahi;
      };

      checks.${system} = {
        inherit steam-asahi;
        # flake check only checks that nixosModules are functions/attribute sets.
        # Also evaluate an enabled module and every declared runtime library.
        module =
          assert moduleConfig.programs.nix-ld.enable;
          assert moduleConfig.hardware.graphics.enable;
          assert moduleConfig.hardware.steam-hardware.enable;
          assert builtins.elem "kvm" moduleConfig.users.users.steam-test.extraGroups;
          assert builtins.elem pkgs.libnotify moduleConfig.programs.nix-ld.libraries;
          assert builtins.elem pkgs.networkmanager moduleConfig.programs.nix-ld.libraries;
          assert moduleConfig.programs.steam-asahi.package.drvPath == steam-asahi.drvPath;
          builtins.deepSeq (map (package: package.drvPath) moduleConfig.programs.nix-ld.libraries) (
            pkgs.runCommand "steam-asahi-module-check" { } "touch $out"
          );
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
