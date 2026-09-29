# Steam Asahi

Native ARM64 Steam on NixOS running on Apple Silicon / Asahi Linux.

The project runs Valve's native ARM64 Steam client inside `muvm`, providing the
4 KiB page-size environment required by Steam while retaining native ARM64
execution and accelerated Asahi graphics.

# Usage

Add flake input

```nix
{
  inputs.steam-asahi = {
    url = "github:thatwhichisdev/steam-asahi";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Import and configure NixOS module:

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
    users = [ "your-user" ];
  };
}
```
