---
name: build-x86-iso
description: Use when building the bootable x86_64 live/installer ISO (bigscreen-iso isoImage) for this NixOS flake. The ISO is x86_64 and builds natively against the binary cache, so it is fast; this skill gives the exact command and where the artifact lands.
---

# Build the x86_64 Bigscreen ISO

Target: `bigscreen-iso` → `config.system.build.isoImage`. A hybrid BIOS/UEFI/
USB live image that boots straight into the Plasma Bigscreen session (no
install). Defined by `hosts/hardware-iso.nix` + `hosts/common.nix`.

## Build

Run on any x86_64 machine with flakes (no VM, emulation, or cross needed):

```sh
nix build .#nixosConfigurations.bigscreen-iso.config.system.build.isoImage
```

This is quick: the x86_64 system is fully built by Hydra, so nearly everything
substitutes from `cache.nixos.org`; only the ISO assembly runs locally. Expect
a few minutes, not hours.

## Result

```
result/iso/*.iso
```

With the pinned nixpkgs this is `result/iso/nixos-<label>-x86_64-linux.iso`
(e.g. `nixos-26.11.20260913.ef34387-x86_64-linux.iso`). Copy/rename it to
`isos/bigscreen-x86_64-linux.iso` if you keep images there:

```sh
cp -L result/iso/*.iso isos/bigscreen-x86_64-linux.iso
```

> `hosts/hardware-iso.nix` still sets `isoImage.isoName`, but recent nixpkgs
> renamed that option to `image.fileName`, so the ISO keeps the default
> `nixos-…` filename. Use `image.fileName = "bigscreen-x86_64-linux.iso";` if
> you want the custom name.

## Notes

- `hosts/hardware-iso.nix` sets `makeBiosBootable`, `makeEfiBootable` and
  `makeUsbBootable`, and forces Mesa software rendering so the Wayland session
  starts even with no GPU.
- It only differs from the other targets in hardware modules; `common.nix`,
  `modules/bigscreen.nix`, `modules/apps.nix` and `modules/theme.nix` are shared.
- `nix flake check` and `nixos-rebuild build --flake .#bigscreen-iso` are quick
  ways to validate changes without producing the ISO.
