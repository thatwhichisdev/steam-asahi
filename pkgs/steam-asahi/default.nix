{
  lib,
  pkgs,
  buildFHSEnv,
  writeShellScript,
  bash,
  coreutils,
  curl,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  lsof,
  makeDesktopItem,
  muvm,
  pciutils,
  procps,
  symlinkJoin,
  unzip,
  util-linux,
  writeShellApplication,
  xdg-user-dirs,
  xz,
  gpuMode ? "drm",
  extraLibraries ? [ ],
}:

let
  runtimeLibraries =
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
    ++ extraLibraries;

  guestEnv = buildFHSEnv {
    name = "steam-asahi-env";
    targetPkgs =
      p:
      runtimeLibraries
      ++ (with p; [
        bash
        coreutils
        curl
        file
        findutils
        gnugrep
        gnused
        gnutar
        gzip
        lsof
        pciutils
        procps
        unzip
        util-linux
        xdg-user-dirs
        xdg-utils
        xz
      ]);
    includeClosures = true;
    runScript = writeShellScript "steam-asahi-guest" ''
      exec "$@"
    '';
    # Match Nixpkgs' Steam environment: avoid an ldconfig symlink loop in
    # nested pressure-vessel containers.
    extraBuildCommands = "cp -f $out/usr/{bin,sbin}/ldconfig";
    profile = ''
      unset GIO_EXTRA_MODULES
      export XDG_DATA_DIRS="/run/opengl-driver/share:/usr/share:''${XDG_DATA_DIRS:-}"
      export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri
      export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d
      export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
      export SDL_JOYSTICK_DISABLE_UDEV=1
    '';
  };

  launcher = writeShellApplication {
    name = "steam-asahi";

    runtimeInputs = [
      bash
      coreutils
      curl
      findutils
      gnugrep
      gnused
      gnutar
      gzip
      # Steam authenticates web-helper IPC connections using lsof.
      lsof
      muvm
      pciutils
      procps
      unzip
      # Valve's steamwebhelper.sh invokes taskset.
      util-linux
      xdg-user-dirs
      xz
    ];

    text = ''
      steam_root="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam"
      steam_runtime="$steam_root/steamrtarm64"

      host_library_path="/usr/lib:''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}:/run/opengl-driver/lib"
      if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
        host_library_path="$host_library_path:$LD_LIBRARY_PATH"
      fi

      run_muvm() {
        ${lib.getExe muvm} \
          --gpu-mode=${lib.escapeShellArg gpuMode} \
          --env="NIX_LD=''${NIX_LD:-/run/current-system/sw/share/nix-ld/lib/ld.so}" \
          --env="NIX_LD_LIBRARY_PATH=''${NIX_LD_LIBRARY_PATH:-/run/current-system/sw/share/nix-ld/lib}" \
          --env="LD_LIBRARY_PATH=$host_library_path" \
          --env="SYSTEM_LD_LIBRARY_PATH=$host_library_path" \
          -- ${lib.getExe guestEnv} "$@"
      }

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

          if run_muvm \
            ${coreutils}/bin/env \
            "LD_LIBRARY_PATH=$steam_runtime:$host_library_path" \
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

        # A bare second invocation can leave the existing client hidden in
        # muvm, where a desktop tray icon may be unavailable. Explicitly ask
        # Steam to show its library window, while preserving caller-supplied
        # URLs and flags (including -shutdown and -silent).
        if [ "$#" -eq 0 ]; then
          set -- steam://open/games
        fi

        # The ARM64 Runtime 4 depot supplies Steam's optional launch service.
        # Use its native tools when installed in the default Steam library.
        runtime_tools="$steam_root/steamapps/common/SteamLinuxRuntime_4-arm64/pressure-vessel/bin"
        if [ -x "$runtime_tools/steam-runtime-launcher-service" ]; then
          export PATH="$PATH:$runtime_tools"
        fi

        # Prefer Valve's bundled libraries, just as during bootstrap. Keep this
        # scoped to Steam so muvm itself runs with the host library environment.
        while true; do
          if run_muvm \
            ${coreutils}/bin/env \
            "LD_LIBRARY_PATH=$steam_runtime:$host_library_path" \
            /bin/bash \
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

  passthru = { inherit runtimeLibraries guestEnv; };

  meta = {
    description = "Native ARM64 Steam launcher for NixOS on Asahi Linux";
    homepage = "https://github.com/thatwhichisdev/steam-asahi";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "steam-asahi";
  };
}
