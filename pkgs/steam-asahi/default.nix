{
  lib,
  coreutils,
  curl,
  gnugrep,
  makeDesktopItem,
  muvm,
  symlinkJoin,
  unzip,
  writeShellApplication,
}:

let
  launcher = writeShellApplication {
    name = "steam-asahi";

    runtimeInputs = [
      coreutils
      curl
      gnugrep
      muvm
      unzip
    ];

    text = ''
      steam_root="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      steam_runtime="$steam_root/steamrtarm64"

      install_client() {
        echo "Native ARM64 Steam is not installed."
        echo "Installing Steam ARM64 public beta..."

        manifest="$(
          curl \
            --fail \
            --silent \
            --show-error \
            --location \
            https://client-update.steamstatic.com/steam_client_publicbeta_linuxarm64
        )"

        archive="$(
          grep \
            -oE \
            'bins_linuxarm64_linuxarm64\.zip\.[[:xdigit:]]+' \
            <<< "$manifest" \
            | head -n 1 \
            || true
        )"

        if [ -z "$archive" ]; then
          echo "Failed to determine the current Steam ARM64 archive." >&2
          exit 1
        fi

        url="https://client-update.steamstatic.com/$archive"

        cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/steam-asahi"
        archive_path="$cache_dir/bins_linuxarm64_linuxarm64.zip"

        mkdir -p "$cache_dir"

        echo "Downloading:"
        echo "  $url"

        curl \
          --fail \
          --location \
          --show-error \
          --output "$archive_path" \
          "$url"

        echo "Installing Steam into:"
        echo "  $steam_root"

        mkdir -p "$steam_root"

        unzip \
          -q \
          -o \
          "$archive_path" \
          -d "$steam_root"

        mkdir -p "$steam_root/package"

        # The native ARM64 Steam client currently lives on the
        # public beta channel.
        printf '%s\n' "publicbeta" > "$steam_root/package/beta"

        chmod -R u+rwX "$steam_runtime"

        # Steam expects the steamrt64 alias.
        ln \
          -sfn \
          "$steam_runtime" \
          "$steam_root/steamrt64"

        touch "$steam_root/.steam-enable-steamrt64-client"

        mkdir -p "$HOME/.steam"

        ln \
          -sfn \
          "$steam_root" \
          "$HOME/.steam/steam"

        ln \
          -sfn \
          "$steam_root" \
          "$HOME/.steam/root"

        if [ -e "$steam_root/linuxarm64" ]; then
          ln \
            -sfn \
            "$steam_root/linuxarm64" \
            "$HOME/.steam/sdkarm64"
        fi

        for executable in \
          steam \
          steamwebhelper \
          steamwebhelper.sh \
          gldriverquery \
          vulkandriverquery \
          steamsysinfo
        do
          if [ -e "$steam_runtime/$executable" ]; then
            chmod +x "$steam_runtime/$executable"
          fi
        done

        if [ -e "$steam_root/steam.sh" ]; then
          chmod +x "$steam_root/steam.sh"
        fi

        echo "Steam ARM64 installation complete."
      }

      if [ ! -x "$steam_runtime/steam" ]; then
        install_client
      fi

      cd "$steam_root"

      exec ${lib.getExe muvm} \
        --env="NIX_LD=''${NIX_LD:-/run/current-system/sw/share/nix-ld/lib/ld.so}" \
        --env="NIX_LD_LIBRARY_PATH=''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
        --env="LD_LIBRARY_PATH=$steam_runtime:/run/current-system/sw/share/nix-ld/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$steam_root/steam.sh" \
        -noverifyfiles \
        "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "steam-asahi";

    desktopName = "Steam (ARM64 / Asahi)";
    comment = "Native ARM64 Steam client running through muvm";

    exec = "${lib.getExe launcher} %U";
    icon = "applications-games";

    terminal = false;

    categories = [
      "Game"
      "Network"
    ];

    mimeTypes = [
      "x-scheme-handler/steam"
      "x-scheme-handler/steamlink"
    ];
  };
in
symlinkJoin {
  name = "steam-asahi";

  paths = [
    launcher
    desktopItem
  ];

  meta = {
    description = "Native ARM64 Steam launcher for NixOS on Asahi Linux";
    homepage = "https://github.com/thatwhichisdev/steam-asahi";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "steam-asahi";
  };
}
