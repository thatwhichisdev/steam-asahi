# Steam Asahi

Native ARM64 Steam integration for NixOS running on Apple Silicon with [Asahi
Linux](https://asahilinux.org).

## Motivation

Running Steam on Apple Silicon Linux has traditionally required running the
x86_64 Steam client through an emulation or translation layer such as FEX.

Valve provides a native ARM64 Steam client through its public beta channel.
ARM64 Proton distributions can provide translation for x86 or x86_64 Windows
games; the client launcher and the game compatibility environment are separate
pieces. This repository currently installs only the client.

The [Ubuntu Asahi](https://github.com/UbuntuAsahi) project provides a working
implementation of this setup through
[steam-arm64](https://github.com/UbuntuAsahi/steam-arm64).

This project adapts that approach for NixOS and exposes it as a reusable Nix
flake and NixOS module.

# Overview

`steam-asahi` installs and launches Valve's native ARM64 Steam client on NixOS
running on Apple Silicon.

The Steam client is downloaded directly from Valve's ARM64 public beta channel
and stored in the user's standard Steam data directory.

The project uses [`muvm`](https://github.com/AsahiLinux/muvm) to run Steam
inside an ARM64 KVM microVM with a 4 KiB page size. This is required because
Apple Silicon systems normally use a larger host page size, while Steam and many
games expect a conventional 4 KiB Linux environment.

`muvm` is not used for CPU architecture emulation. The Steam client itself runs
natively as ARM64 code.

Inside muvm, the launcher enters a native ARM64 FHS environment built by
Nixpkgs. This supplies standard `/bin`, `/usr/bin`, and library paths plus an
`ld.so.cache`. Steam's pressure-vessel game containers need this layout even
when the client alone can run with nix-ld. Vulkan and EGL discovery explicitly
includes the host Asahi driver under `/run/opengl-driver`.

## Architecture

```text
NixOS / Apple Silicon
        │
        ▼
      muvm
 ARM64 KVM microVM
   4 KiB pages
        │
        ▼
 ARM64 FHS environment
        │
        ▼
 Native ARM64 Steam
        │
        ▼
   Proton ARM64
        │
        ├── ARM64 Windows applications
        │
        └── x86 / x86_64 Windows applications
             └── translation provided by Proton
```

The project intentionally does not run the Steam client itself through FEX,
Box64, or another x86 compatibility layer.

Architecture translation may still be required when running existing x86 or
x86_64 Windows games. The chosen ARM64 Proton distribution must provide the
necessary translator and Steam Runtime. For example, the Ubuntu Asahi wrapper
also installs an ARM64 GE-Proton build containing FEX and requests Steam Runtime
4.0. This flake does not yet automate those steps or support native x86 Linux
games through a configured FEX root filesystem.

## Components

The flake provides:

  | component                        | description                                       |
  | -------------------------------- | ------------------------------------------------- |
  | `steam-asahi`                    | launcher for the native ARM64 Steam client        |
  | `nixosModules.default`           | NixOS module for configuring the required runtime |
  | `packages.aarch64-linux.default` | standalone launcher package                       |
  | `apps.aarch64-linux.default`     | application exposed through `nix run`             |

The NixOS module also configures the system pieces required by Steam, including:

- `muvm`
- KVM access
- accelerated graphics
- Steam hardware rules
- `nix-ld`
- native ARM64 runtime libraries required by the Steam client

Steam itself remains mutable and self-updating under:

```text
~/.local/share/Steam
```

Nix manages the launcher and host runtime instead of attempting to package
Steam's self-updating client into the Nix store.

# Getting Started

## Prerequisites

This project is intended for:

- NixOS
- `aarch64-linux`
- Apple Silicon running Asahi Linux
- working Asahi GPU acceleration
- KVM support
- Nix flakes

A working NixOS Apple Silicon installation can be configured using
[nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon).

## Installation

Add `steam-asahi` as an input to your NixOS flake:

```nix
{
  inputs.steam-asahi = {
    url = "github:thatwhichisdev/steam-asahi";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Import the NixOS module:

```nix
{
  inputs,
  ...
}:
{
  imports = [
    inputs.steam-asahi.nixosModules.default
  ];

  programs.steam-asahi = {
    enable = true;

    users = [
      "your-user"
    ];
  };
}
```

Rebuild the system:

```shell
sudo nixos-rebuild switch --flake .#<host>
```

Or with [`nh`](https://github.com/nix-community/nh):

```shell
nh os switch -H <host>
```

## Running

Launch Steam with:

```shell
steam-asahi
```

On the first launch, the wrapper downloads Valve's native ARM64 Steam client
from the public beta channel and installs it under:

```text
~/.local/share/Steam
```

Subsequent launches reuse the existing Steam installation.

Launching without arguments explicitly opens the Library window
(`steam://open/games`), including when Steam is already running with all its
windows closed. This also applies to the desktop launcher and does not require
a tray icon. Explicit URLs or flags such as `-shutdown` and `-silent` are passed
through unchanged. A tray icon is not currently provided by this integration.

To test changes from a local checkout after the NixOS module has been enabled:

```shell
nix flake check
nix run .
```

`nix run .` uses the launcher in this checkout. An already installed
`steam-asahi` command continues to use the version from your last system rebuild.
Fully exit Steam before testing a different launcher: a second launch can
forward its request to the existing client. For a GitHub flake input, publish
the intended revision and update that input in the NixOS configuration before
rebuilding; rebuilding an unchanged lock file keeps the older launcher.
The standalone package still requires the module's host setup (or equivalent
KVM, graphics, and nix-ld configuration).

The client remains responsible for updating itself in the same way as a normal
Steam installation.

# Configuration

The NixOS module currently exposes the following options:

```nix
programs.steam-asahi = {
  enable = true;

  users = [
    "your-user"
  ];

  gpuMode = "drm";

  extraLibraries = with pkgs; [
    # Additional native ARM64 runtime libraries.
  ];
};
```

`users` controls which users receive the required KVM access.

`extraLibraries` can be used to expose additional native ARM64 libraries to
Steam through both the FHS environment and nix-ld if Valve introduces new
dependencies. With a custom `package`, pass any additional FHS libraries to
that package separately.

`gpuMode` selects muvm's `drm`, `venus`, or `software` mode. The default is
`drm` for Asahi acceleration. It applies to the module's default package; when
supplying a custom `package`, configure that package's GPU mode separately.

# Troubleshooting

The launcher includes `lsof` because Steam uses it to identify the processes
behind localhost IPC connections. Without it, the web helper can start and load
JavaScript while the main client rejects its connections, leaving the UI unable
to finish starting. Installing libraries through `extraLibraries` does not add
commands to `PATH`.

If login succeeds but the main window keeps spinning, check for
`RefreshPlatformData: failed to load platform app` and repeated
`appdatacache.cpp: !bSharedKVSymbols` assertions. These messages alone are not
proof of a corrupt cache. In the tested ARM64 client, the SteamRT version of
`steamclient.so` directly requires `libnm.so.0`. A linker probe inside muvm
failed without that library and resolved all dependencies after it was added.
The module now includes `networkmanager` for its native client library; this
does not enable the NetworkManager service. Rebuild the NixOS configuration to
apply this library change: updating only the launcher with `nix run .` is not
enough on a system with the older module configuration.

Normal launches now give the SteamRT directory priority over host libraries,
matching bootstrap. The launcher also supplies `xdg-user-dir` via
`xdg-user-dirs`. An authenticated test with the corrected launcher and the
native NetworkManager library supplied in its library path completed post-login
UI initialization in about 2.6 seconds; the user confirmed the main window loaded.

Inspect logs under `${XDG_DATA_HOME:-$HOME/.local/share}/Steam/logs`, especially:

- `transport_client.txt` and `transport_steamui.txt`: rejected local connections.
- `webhelper_js.txt` and `webhelper.txt`: UI initialization and login window creation.
- `steamwebhelper.log` and `cef_log.txt`: browser and library errors.
- `connection_log.txt`: connectivity to Steam servers.

Interpret startup warnings in context:

| Message | Meaning for the native client |
| --- | --- |
| FEX / Box64 not found | muvm's optional x86 emulator setup failed. ARM64 Steam can still run; x86 games need a separate compatibility setup. |
| No IPv6 nameserver / IPv6 network unreachable | The guest cannot use those IPv6 routes. In the tested setup Steam connected to its servers over IPv4. |
| `steamrtarm32` driver queries missing | The client attempted 32-bit ARM probes. Do not replace these with symlinks to 64-bit binaries. They did not prevent the tested login UI from loading. |
| RADV / `vdrm_device_connect` errors | Driver probing errors alone do not establish that the Apple GPU failed. Check `steamsysinfo.txt`; the reported Apple GPU was selected in the supplied output. |
| CPU frequency, PCI, XOpenIM, XRandR warnings | These did not prevent the tested login UI from loading. Display or input problems would require further investigation. |

The launcher retains the upstream ARM64 wrapper's `-noverifyfiles` workaround.
Its bootstrap completeness checks are not a full integrity check of the Steam
installation. Downloads and client updates remain mutable upstream content,
outside `flake.lock`.

## Game runtime startup

Use an ARM64 Proton version in the game's Compatibility settings. Steam manages
the Proton and Steam Linux Runtime depots; the launcher does not install or
patch them. Proton Experimental (ARM64) requires Steam Linux Runtime 4.0 for
ARM64 (app ID 4185400).

The earlier minimal filesystem setup could fail before Proton started with
`bwrap: execvp true: No such file or directory`, or with `libGL.so.1` missing
when the launch scripts reset their library environment. The launcher now uses
Nixpkgs' FHS environment and linker cache instead of a few `/bin` symlinks.
When ARM64 Runtime 4 is installed in the default Steam library, its tools are
also added to PATH for `steam-runtime-launcher-service`.

The bundled Vulkan loader needs the Asahi driver's manifest directory in its
search path. The FHS profile supplies it through `XDG_DATA_DIRS`; this avoids
replacing Valve's bundled libraries or hard-coding a single GPU driver.

Validation: an isolated 4 KiB muvm test detected the Apple M1 Max with
`VK_KHR_surface` and `VK_KHR_xlib_surface`, and the installed ARM64 Runtime 4
ran `/usr/bin/true` successfully. These checks establish container startup and
driver discovery, not compatibility with every game.

### Slay the Spire 2

Tested on 2026-09-30 with the Windows build, Proton 11.0 (ARM64), and an
Apple M1 Max. Set the game's Steam Launch Options to:

```text
DOTNET_EnableWriteXorExecute=0 %command% --rendering-driver vulkan
```

Vulkan avoids the Direct3D 12 `swap_chain_resize` error seen in the earlier
test. Vulkan alone still left a black window: graphics and audio initialized,
but the main thread consumed one CPU core without progressing beyond .NET
startup. Debugger samples found translated CoreCLR callback-initialization
code. Disabling .NET's separate writable/executable code mappings let the
game load its intro and main-menu assets; the user confirmed working menus
and gameplay.
This supports a .NET/FEX generated-code mapping issue, but does not establish
which upstream component needs a fix. See the [.NET 9 configuration definition](https://github.com/dotnet/runtime/blob/v9.0.7/src/coreclr/inc/clrconfigvalues.h)
for `EnableWriteXorExecute`.

Keep this workaround per game; the launcher does not disable W^X globally.
OpenGL and `DOTNET_EnableHWIntrinsic=0` did not resolve the startup stall.
For diagnostics, add `PROTON_LOG=1` before `%command%` to write
`~/steam-2868840.log`; remove it after testing to avoid ongoing verbose logs.

### FTL: Faster Than Light

The Windows build (Steam app ID 212680, build 4710954) reached Wine under
Proton Experimental (ARM64), but displayed `Unable to load function:
(KERNEL32.dll)`. With `PROTON_LOG=+module`, Wine reported an empty function
name during `BASSMIX.dll` initialization. `KERNEL32.dll` itself loaded
successfully. Enabling `FEX_SMCCHECKS=2` instead caused an access violation
while initializing `BASS.dll`; disabling FEX block merging and disk caching
did not resolve the original error.

A test with the audio vendor's current **32-bit Windows** libraries passed
audio initialization and reached the menu with music, confirmed by the user:

- [BASS 2.4.18](https://www.un4seen.com/files/bass24.zip): use the archive's
  top-level `bass.dll`.
- [BASSmix 2.4.13](https://www.un4seen.com/files/bassmix24.zip): use the
  archive's top-level `bassmix.dll`.

To reproduce this workaround, close FTL, back up both original DLLs from its
installation directory, then replace them with those top-level files.
The `x64/` files and native ARM64 DLLs are not suitable for this 32-bit game.
Clear the diagnostic Launch Options before playing. This is a local game
workaround, not a global Wine DLL override or an automatic launcher action.
Steam updates or file verification may restore the older bundled libraries.
The revised FHS launcher is still required: relaunching the old installed
`steam-asahi` returned to exit code 127 before Proton started, even with these
DLLs. After fully exiting that client and running `nix run .`, a normal Steam
launch with empty Launch Options reached `Running Game!` and received Steam
stats successfully; the user confirmed normal gameplay with empty Launch Options.

The tested replacement DLL SHA-256 hashes are:

```text
ce5e97630cf4e1ef12a9afad785683414b7504efc443766333360ad2ed142eba  bass.dll
4ccefb281fe22dfaa79b1a70537036665a21bd770a0431146c339b516bce5758  bassmix.dll
```

The vendor URLs can change as releases are updated. The original files from
the 2026-09-30 local test are preserved in FTL's installation directory under
`.steam-asahi-original-audio-20260930/`. To undo that test, close FTL and copy
those two DLLs back over the replacements. Save files were not changed by
the library replacement.

# Status

This project should currently be considered experimental.

Validation on 2026-09-29: the launcher built, `nix flake check` passed (including
an enabled NixOS module and its library list), and a short launch test reached
the sign-in window according to Steam's browser logs. The previous localhost
connection rejections disappeared after adding the missing runtime tools.
The user subsequently confirmed successful account sign-in and a hardware
survey, followed by a main-window loading stall. The missing `libnm.so.0`
dependency described above was then identified and fixed. A subsequent
authenticated test completed main UI initialization, confirmed by the logs and
the user. On 2026-09-30, Slay the Spire 2 successfully launched with Proton 11.0
(ARM64) and the per-game options above, with menus and gameplay confirmed by
the user. FTL also worked through Steam with empty Launch Options after its
audio DLL replacement. Reopening the hidden Steam window through
`steam://open/games` was confirmed and is now the launcher's default action.
A fresh bootstrap installation and extended gameplay remain untested.

Valve's native ARM64 Steam and Proton support is still relatively new, and the
runtime requirements may change as the client is updated.

Compatibility also depends heavily on individual games. Running the Steam client
natively on ARM64 does not imply that every existing x86 or x86_64 game will
work.

# Licensing

The code in this project is licensed under the MIT license. Check
[LICENSE.md](LICENSE.md) for further details.

Parts of the implementation are based on work from the Ubuntu Asahi
`steam-arm64` project and retain the corresponding MIT attribution.
