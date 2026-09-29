{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.steam-asahi;

  defaultPackage = pkgs.callPackage ../pkgs/steam-asahi {
    gpuMode = cfg.gpuMode;
  };
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
        Additional native ARM64 host libraries made available to Steam
        through nix-ld.

        Do not add libraries already bundled by Steam, such as FFmpeg or
        SDL, unless required for a specific compatibility workaround.
      '';
    };

    gpuMode = lib.mkOption {
      type = lib.types.enum [
        "drm"
        "venus"
        "software"
      ];

      default = "drm";

      description = ''
        GPU virtualization mode used by muvm.
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

    # Required for accelerated Asahi graphics.
    hardware.graphics.enable = true;

    # Steam controller and other Steam hardware udev rules.
    hardware.steam-hardware.enable = true;

    # Valve's binaries use conventional Linux ELF interpreter paths.
    #
    # Keep this list limited to host libraries. Steam's own runtime must
    # provide its bundled libraries first; injecting alternatives for those
    # libraries can cause ABI mismatches.
    programs.nix-ld = {
      enable = true;

      libraries =
        with pkgs;
        [
          # Steam diagnostics / driver query
          SDL2

          # Chromium / steamwebhelper
          nss
          nspr
          dbus
          cups
          expat
          alsa-lib
          ibus
          at-spi2-core

          # SteamRT's steamclient.so directly links against libnm.so.0.
          # This supplies the client library, not a NetworkManager daemon.
          networkmanager

          # GLib / GTK
          glib
          gtk2
          gdk-pixbuf

          # Graphics / video acceleration
          libglvnd
          libdrm
          libgbm
          libva
          vulkan-loader

          # Audio
          pipewire
          libpulseaudio
          openal

          # Fonts / text rendering
          fontconfig
          freetype
          cairo
          pango

          # X11
          libx11
          libxcb
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxtst
          libice
          libsm

          # Wayland
          wayland
          libxkbcommon
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
