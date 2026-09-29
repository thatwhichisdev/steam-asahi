{
  lib,
  bash,
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
      bash
      coreutils
      curl
      gnugrep
      muvm
      unzip
    ];

    text = ''
      steam_root="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      steam_runtime="$steam_root/steamrtarm64"
      steam_manifest="$steam_root/package/steam_client_publicbeta_linuxarm64"

      bootstrap_complete() {
        [ -f "$steam_runtime/steam" ] \
          && [ -e "$steam_runtime/libSDL3.so.0" ] \
          && [ -e "$steam_runtime/libavcodec.so.62" ]
      }

      client_complete() {
        chmod u+x "$steam_runtime/steam"

        bootstrap_complete \
          && [ -f "$steam_root/steam.sh" ] \
          && [ -f "$steam_manifest" ]
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

      ensure_layout() {
        mkdir -p "$steam_root/package"
        mkdir -p "$HOME/.steam"

        printf '%s\n' "publicbeta" > "$steam_root/package/beta"

        safe_symlink \
          "$steam_runtime" \
          "$steam_root/steamrt64"

        touch "$steam_root/.steam-enable-steamrt64-client"

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
      }

      install_bootstrap() {
        echo "Native ARM64 Steam bootstrap is not installed or incomplete."
        echo "Installing Steam ARM64 public beta bootstrap..."

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
          url="https://client-update.steamstatic.com/$archive"

          echo "Downloading $component..."
          echo "  $url"

          rm -f "$temporary_path"

          curl \
            --fail \
            --location \
            --show-error \
            --retry 3 \
            --retry-delay 2 \
            --output "$temporary_path" \
            "$url"

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
          echo "Steam ARM64 bootstrap did not provide $steam_runtime/steam" >&2
          exit 1
        fi

        if [ ! -e "$steam_runtime/libavcodec.so.62" ]; then
          echo "Steam ARM64 codec payload did not provide libavcodec.so.62" >&2
          exit 1
        fi

        if [ ! -e "$steam_runtime/libSDL3.so.0" ]; then
          echo "Steam ARM64 SDL payload did not provide libSDL3.so.0" >&2
          exit 1
        fi

        chmod -R u+rwX "$steam_runtime"
        chmod u+x "$steam_runtime/steam"

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

        ensure_layout

        echo "Steam ARM64 bootstrap installation complete."
      }

      complete_client_install() {
        echo "Completing Steam ARM64 client installation..."

        attempt=0

        while ! client_complete; do
          attempt=$((attempt + 1))

          if [ "$attempt" -gt 3 ]; then
            echo "Steam ARM64 client installation did not complete after 3 attempts." >&2
            exit 1
          fi

          echo "Running Steam bootstrap update pass $attempt..."

          if ${lib.getExe muvm} \
            --env="NIX_LD=''${NIX_LD:-/run/current-system/sw/share/nix-ld/lib/ld.so}" \
            --env="NIX_LD_LIBRARY_PATH=''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
            --env="LD_LIBRARY_PATH=$steam_runtime:/run/opengl-driver/lib" \
            -- \
            "$steam_runtime/steam" \
            -forcesteamupdate \
            -forcepackagedownload \
            -exitsteam
          then
            status=0
          else
            status=$?
          fi

          if client_complete; then
            break
          fi

          echo "Steam bootstrap update pass exited with status $status."

          if [ "$status" -ne 0 ] && [ "$status" -ne 42 ]; then
            echo "Steam bootstrap updater failed." >&2
            exit "$status"
          fi

          if [ "$attempt" -lt 3 ]; then
            echo "Full client is not installed yet; retrying..."
            sleep 1
          fi
        done

        ensure_layout

        echo "Steam ARM64 client installation complete."
      }

      run_client() {
        restart_count=0

        cd "$steam_root"

        while true; do
          if ${lib.getExe muvm} \
            --env="STEAM_RUNTIME=1" \
            --env="NIX_LD=''${NIX_LD:-/run/current-system/sw/share/nix-ld/lib/ld.so}" \
            --env="NIX_LD_LIBRARY_PATH=''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
            -- \
            ${lib.getExe bash} \
            "$steam_root/steam.sh" \
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

          echo "Steam requested a client restart; restarting..."
        done
      }

      if ! bootstrap_complete; then
        install_bootstrap
      fi

      ensure_layout

      if ! client_complete; then
        complete_client_install
      fi

      run_client "$@"
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
