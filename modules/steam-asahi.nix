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

    extraLibraries = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs; [
          libnotify
        ]
      '';
      description = ''
        Additional native ARM64 libraries exposed to the Steam runtime.
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

    hardware.graphics.enable = true;
    hardware.steam-hardware.enable = true;

    programs.nix-ld = {
      enable = true;

      libraries =
        with pkgs;
        [
          # Steam UI
          sdl3

          # GLib / GTK2
          glib
          gtk2
          gdk-pixbuf

          # OpenGL
          libglvnd

          # Audio
          pipewire
          libpulseaudio

          # X11
          xorg.libX11
          xorg.libXext
          xorg.libXfixes
          xorg.libXi
          xorg.libXrandr
          xorg.libXrender
          xorg.libXtst
        ]
        ++ [
          config.hardware.graphics.package
        ]
        ++ config.hardware.graphics.extraPackages
        ++ cfg.extraLibraries;
    };

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = lib.mkAfter [ "kvm" ];
    });
  };
}
