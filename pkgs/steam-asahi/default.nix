{
  lib,
  bash,
  coreutils,
  curl,
  gnugrep,
  makeDesktopItem,
  muvm,
  pciutils,
  symlinkJoin,
  unzip,
  util-linux,
  writeShellApplication,
}:

let
  initScript = writeShellApplication {
    name = "steam-asahi-init";

    runtimeInputs = [
      coreutils
      util-linux
      pciutils
    ];

    text = ''
      fhs_root="/run/steam-asahi-fhs"

      mkdir -p "$fhs_root/bin"
      mkdir -p "$fhs_root/usr"

      # NixOS has no /bin/bash. Steam's ARM64 web helper expects it.
      cp -a /bin/. "$fhs_root/bin/" 2>/dev/null || true

      ln -sfn ${bash}/bin/bash "$fhs_root/bin/bash"
      ln -sfn ${bash}/bin/sh "$fhs_root/bin/sh"

      # Preserve anything already available under /usr and provide the
      # conventional paths Steam/CEF/PressureVessel expect.
      cp -a /usr/. "$fhs_root/usr/" 2>/dev/null || true

      mkdir -p "$fhs_root/usr/bin"
      mkdir -p "$fhs_root/usr/share"
      mkdir -p "$fhs_root/usr/lib"

      ln -sfn ${coreutils}/bin/env "$fhs_root/usr/bin/env"

      # Apple Silicon has no conventional PCI bus. Steam only uses lspci
      # diagnostically, so avoid noisy failures.
      cat > "$fhs_root/bin/lspci" <<'EOF'
      #!${bash}/bin/sh
      for device in /sys/bus/pci/devices/*; do
        if [ -e "$device" ]; then
          exec ${pciutils}/bin/lspci "$@"
        fi
      done
      exit 0
      EOF

      chmod +x "$fhs_root/bin/lspci"

      ln -sfn "$fhs_root/bin/lspci" "$fhs_root/usr/bin/lspci"

      # Expose NixOS graphics metadata through conventional FHS paths.
      #
      # Libraries live under /run/opengl-driver on NixOS, but software
      # running inside Steam Runtime / PressureVessel also searches the
      # usual /usr/share locations.
      for metadata in vulkan glvnd egl; do
        source="/run/opengl-driver/share/$metadata"
        target="$fhs_root/usr/share/$metadata"

        if [ -e "$source" ]; then
          rm -rf -- "''${target:?}"
          ln -s "$source" "$target"
        fi
      done

      # PressureVessel validates Vulkan ICD/layer metadata against its
      # override tree, so expose the host metadata there as well.
      overrides="$fhs_root/usr/lib/pressure-vessel/overrides/share/vulkan"

      mkdir -p "$overrides"

      for subdir in icd.d explicit_layer.d implicit_layer.d; do
        source="/run/opengl-driver/share/vulkan/$subdir"

        if [ -d "$source" ]; then
          mkdir -p "$overrides/$subdir"

          for json in "$source"/*.json; do
            if [ -e "$json" ]; then
              ln -sfn "$json" "$overrides/$subdir/"
            fi
          done
        fi
      done

      # /bin and /usr are inherited read-only from the NixOS host.
      # Overlay our small writable FHS compatibility trees inside the VM.
      mount --bind "$fhs_root/bin" /bin
      mount --bind "$fhs_root/usr" /usr
    '';
  };

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

      bootstrap_complete() {
        [ -f "$steam_runtime/steam" ] \
          && [ -e "$steam_runtime/libSDL3.so.0" ] \
          && [ -e "$steam_runtime/libavcodec.so.62" ]
      }

      client_complete() {
        bootstrap_complete \
          && [ -f "$steam_root/steam.sh" ] \
          && [ -f "$steam_root/public/steambootstrapper_english.txt" ]
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

          # The installed filesystem is the source of truth.
          #
          # Steam's bootstrap updater may terminate with a non-zero status after
          # successfully applying an update and honoring -exitsteam.
          if client_complete; then
            echo "Steam ARM64 client update completed."
            break
          fi

          echo "Steam bootstrap update pass exited with status $status."

          case "$status" in
            0|42|254)
              ;;
            *)
              echo "Steam bootstrap updater failed." >&2
              exit "$status"
              ;;
          esac

          if [ "$attempt" -lt 3 ]; then
            echo "Full client is not installed yet; retrying..."
            sleep 1
          fi
        done

        chmod u+x "$steam_runtime/steam"

        if [ -f "$steam_root/steam.sh" ]; then
          chmod u+x "$steam_root/steam.sh"
        fi

        ensure_layout

        echo "Steam ARM64 client installation complete."
      }

      run_client() {
        restart_count=0

        cd "$steam_root"

        while true; do
          if ${lib.getExe muvm} \
            --gpu-mode=drm \
            --execute-pre ${lib.getExe initScript} \
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
