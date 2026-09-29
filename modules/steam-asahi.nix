{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.steam-asahi;

  defaultPackage = pkgs.callPackage ../pkgs/steam-asahi { };
in
{
  options.programs.steam-asahi = {
    enable = lib.mkEnableOption "native ARM64 Steam on Asahi Linux";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression ''
        pkgs.callPackage <steam-asahi>/pkgs/steam-asahi { }
      '';
      description = "The steam-asahi package to install.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users that should be granted access to KVM for running muvm.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = ''
          programs.steam-asahi is only supported on aarch64-linux.
        '';
      }
    ];

    environment.systemPackages = [
      cfg.package
      pkgs.muvm
    ];

    # Allow generic dynamically linked ARM64 binaries, such as
    # Valve's Steam ARM64 client, to run on NixOS.
    programs.nix-ld.enable = true;

    # Required for accelerated graphics.
    hardware.graphics.enable = true;

    # Steam controller / input device udev rules.
    hardware.steam-hardware.enable = true;

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = lib.mkAfter [ "kvm" ];
    });
  };
}
