# Steam Asahi

Native ARM64 Steam integration for NixOS running on Apple Silicon with [Asahi
Linux](https://asahilinux.org).

## Motivation

Running Steam on Apple Silicon Linux has traditionally required running the
x86_64 Steam client through an emulation or translation layer such as FEX.

Valve now provides a native ARM64 Steam client together with ARM64 builds of
Proton. This makes it possible to run the Steam client natively on ARM64 and
leave architecture translation to Proton only when it is actually required by an
x86 or x86_64 Windows game.

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
x86_64 Windows games. With ARM64 Proton, this translation is handled as part of
the Proton environment rather than around the Steam client itself.

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

  extraLibraries = with pkgs; [
    # Additional native ARM64 runtime libraries.
  ];
};
```

`users` controls which users receive the required KVM access.

`extraLibraries` can be used to expose additional native ARM64 libraries to
Steam through the compatibility runtime if Valve introduces new dependencies.

# Status

This project should currently be considered experimental.

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
