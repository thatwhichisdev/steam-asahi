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

      client_complete() {
        [ -x "$steam_runtime/steam" ] \
          && [ -e "$steam_runtime/libSDL3.so.0" ] \
          && [ -e "$steam_runtime/libavcodec.so.62" ]
      }

      safe_symlink() {
        target="$1"
        link="$2"

        if [ -e "$link" ] && [ ! -L "$link" ]; then
          echo "Refusing to replace non-symlink path: $link" >&2
          exit 1
        fi

        ln -sfnT "$target" "$link"
      }

      install_client() {
        echo "Native ARM64 Steam is not installed or incomplete."
        echo "Installing Steam ARM64 public beta..."

        manifest="$(
          curl \
            --fail \
            --silent \
            --show-error \
            --location \
            https://client-update.steamstatic.com/steam_client_publicbeta_linuxarm64
        )"

        cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/steam-asahi"
        mkdir -p "$cache_dir"
        mkdir -p "$steam_root"

        download_component() {
          component="$1"

          archive="$(
            printf '%s\n' "$manifest" \
              | grep -oE "$component\.zip\.[[:xdigit:]]+" \
              | head -n 1 \
              || true
          )"

          if [ -z "$archive" ]; then
            echo "Failed to resolve Steam ARM64 component: $component" >&2
            exit 1
          fi

          archive_path="$cache_dir/$component.zip"
          temporary_path="$archive_path.part"

          echo "Downloading:"
          echo "  https://client-update.steamstatic.com/$archive"

          rm -f "$temporary_path"

          curl \
            --fail \
            --location \
            --show-error \
            --retry 3 \
            --retry-delay 2 \
            --output "$temporary_path" \
            "https://client-update.steamstatic.com/$archive"

          mv -f "$temporary_path" "$archive_path"

          echo "Extracting $component..."

          unzip \
            -q \
            -o \
            "$archive_path" \
            -d "$steam_root"
        }

        download_component "bins_linuxarm64_linuxarm64"
        download_component "codecs_linuxarm64_linuxarm64"
        download_component "sdl3_linuxarm64_linuxarm64"

        if [ ! -f "$steam_runtime/steam" ]; then
          echo "Steam ARM64 client archive did not create $steam_runtime/steam" >&2
          exit 1
        fi

        if [ ! -e "$steam_runtime/libavcodec.so.62" ]; then
          echo "Steam ARM64 codec archive did not provide libavcodec.so.62" >&2
          exit 1
        fi

        if [ ! -e "$steam_runtime/libSDL3.so.0" ]; then
          echo "Steam ARM64 SDL3 archive did not provide libSDL3.so.0" >&2
          exit 1
        fi

        mkdir -p "$steam_root/package"

        printf '%s\n' "publicbeta" > "$steam_root/package/beta"

        chmod -R u+rwX "$steam_runtime"

        for executable in \
          steam \
          steamwebhelper \
          steamwebhelper.sh \
          gldriverquery \
          vulkandriverquery \
          steamsysinfo
        do
          if [ -e "$steam_runtime/$executable" ]; then
            chmod u+x "$steam_runtime/$executable"
          fi
        done

        safe_symlink \
          "$steam_runtime" \
          "$steam_root/steamrt64"

        touch "$steam_root/.steam-enable-steamrt64-client"

        mkdir -p "$HOME/.steam"

        safe_symlink \
          "$steam_root" \
          "$HOME/.steam/steam"

        safe_symlink \
          "$steam_root" \
          "$HOME/.steam/root"

        if [ -e "$steam_root/linuxarm64" ]; then
          safe_symlink \
            "$steam_root/linuxarm64" \
            "$HOME/.steam/sdkarm64"
        fi

        echo "Steam ARM64 installation complete."
      }

      if ! client_complete; then
        install_client
      fi

      restart_count=0

      while true; do
        if ${lib.getExe muvm} \
          --env="NIX_LD=''${NIX_LD:-/run/current-system/sw/share/nix-ld/lib/ld.so}" \
          --env="NIX_LD_LIBRARY_PATH=''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
          --env="LD_LIBRARY_PATH=$steam_runtime:/run/current-system/sw/share/nix-ld/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
          "$steam_runtime/steam" \
          -noverifyfiles \
          "$@"
        then
          status=0
        else
          status=$?
        fi

        if [ "$status" -ne 42 ]; then
          exit "$status"
        fi

        restart_count=$((restart_count + 1))

        if [ "$restart_count" -gt 5 ]; then
          echo "Steam requested more than 5 consecutive restarts; stopping." >&2
          exit 42
        fi

        echo "Steam update completed; restarting inside muvm..."
      done
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
