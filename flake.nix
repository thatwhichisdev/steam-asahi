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
        };

        default = {
          type = "app";
          program = nixpkgs.lib.getExe steam-asahi;
        };
      };

      nixosModules = rec {
        steam-asahi = import ./modules/steam-asahi.nix;
        default = steam-asahi;
      };

      checks.${system} = {
        inherit steam-asahi;
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
