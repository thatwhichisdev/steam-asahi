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

To test changes from a local checkout after the NixOS module has been enabled:

```shell
nix flake check
nix run .
```

`nix run .` uses the launcher in this checkout. An already installed
`steam-asahi` command continues to use the version from your last system rebuild.
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
Steam through the compatibility runtime if Valve introduces new dependencies.

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
the user. Game launch and a fresh bootstrap installation remain untested.

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
