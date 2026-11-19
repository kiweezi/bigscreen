---
name: build-rpi4-image
description: Use when building the flashable Raspberry Pi 4 SD-card image (bigscreen-rpi4 sdImage) for this NixOS flake, especially from an x86_64 host/VM that cannot run aarch64 natively. Covers the fast cross-compiled-kernel method, required disk/CPU, and the allowMissingModules fix.
---

# Build the Raspberry Pi 4 SD image (fast, from x86_64)

Target: `bigscreen-rpi4` → `config.system.build.sdImage`, a `.img.zst` that
flashes straight onto an SD card.

## Why the naive build is unbearably slow

`nix build .#nixosConfigurations.bigscreen-rpi4.config.system.build.sdImage`
on x86_64 looks like it should mostly hit the `cache.nixos.org` aarch64 cache.
It does — **except for the kernel**. The flake uses the Raspberry Pi vendor
kernel (`pkgs.linuxPackages_rpi4`, e.g. `linux-rpi-6.12.75-1+rpt1`), which
Hydra does not build, so it is **not in any binary cache**. That single
derivation is ~15,000 object files. Under `boot.binfmt.emulatedSystems`
(qemu-user) it runs at roughly **1–2 objects per minute → 20–35 hours**.

Everything else (the whole aarch64 userspace closure) downloads from cache in
minutes.

## Try the binary cache first

On tagged releases, CI pushes the vendor kernel (and Comin) to
`https://kiweezi-rpi-bigscreen.cachix.org`
(see `.github/workflows/release-rpi4-bootstrap.yml`), and machines built from
this flake trust it via `hosts/base.nix`. If the cache holds the kernel your
lockfile points at, the plain `nix build` substitutes it and **no
cross-compile trick is needed**. Check:

```sh
nix path-info --store https://kiweezi-rpi-bigscreen.cachix.org \
  "$(nix eval .#nixosConfigurations.bigscreen-rpi4-deploy.config.boot.kernelPackages.kernel.outPath --raw)"
```

A miss means the cache predates your nixpkgs bump: build the kernel once
(cross-compiled, per the method below) and `cachix push kiweezi-rpi-bigscreen
<kernel-path>`. The builder machine must trust the cache — machines built from
this flake get the substituter automatically via `hosts/base.nix`; an ad-hoc
NixOS VM needs the substituter and public key in `/etc/nix/nix.conf`.

## The fast method: cross-compile only the kernel, natively

Build the *same* kernel from `pkgsCross.aarch64-multiplatform`, whose builder
runs **natively on x86_64** (only the target is aarch64) while every other
package still comes from the aarch64 cache. The kernel is byte-for-byte the
same version/config; only the build machine differs. This turns the kernel
build into ~20–40 minutes on 8 vCPUs.

Do **not** cross-build the whole system (`crossSystem`) — that misses the
cache and recompiles everything. Override just `boot.kernelPackages`.

### 1. Prerequisites

- An x86_64 machine/VM with Nix flakes. It needs to hold the entire aarch64
  system closure **plus** the kernel build tree and the image: allow
  **≥ 40 GiB** of store space. A stock 32 GiB VM is *not* enough; attach a
  second disk and put the store (or at least Nix's `build-dir`) on it. Example
  for a VM: attach a 120 GiB VDI, `mkfs.ext4 -L nixstore /dev/sdb`, mount it,
  and either move `/nix/store` there or overlay it:
  ```sh
  mount /dev/sdb /mnt/nixstore
  mkdir -p /mnt/nixstore/upper /mnt/nixstore/work
  mount -t overlay overlay \
    -o lowerdir=/nix/store,upperdir=/mnt/nixstore/upper,workdir=/mnt/nixstore/work \
    /nix/store
  ```
  Also keep the build tree off the small disk by pointing Nix at the bigger
  one (`build-dir = /mnt/nixstore/builds` in `/etc/nix/nix.conf`, then
  `systemctl restart nix-daemon`).
- **As many vCPUs as you can** (8 is a good target). The cross kernel build
  scales with cores. `VBoxManage modifyvm <vm> --cpus 8 --memory 10240` (VM
  powered off).

### 2. One config fix is required

The vendor kernel does not provide every module in nixpkgs' large default
initrd module list (e.g. `dw-hdmi` is absent on this board). Without this the
build dies in the module-shrinking step:

```
modprobe: FATAL: Module dw-hdmi not found in directory .../6.12.75
```

Add to `hosts/hardware-rpi4.nix` (already present in this repo):

```nix
boot.initrd.allowMissingModules = true;
```

### 3. Build

From the repo root, with the kernel swapped to the cross build:

```sh
nix build \
  --extra-experimental-features 'nix-command flakes' \
  --impure --out-link result --expr '
let
  f = builtins.getFlake (toString ./.);
  nixpkgs = f.inputs.nixpkgs;
  crossPkgs = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform;
  sys = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      ./hosts/common.nix
      ./hosts/hardware-rpi4.nix
      f.inputs.nixos-hardware.nixosModules.raspberry-pi-4
      { boot.kernelPackages = nixpkgs.lib.mkForce crossPkgs.linuxPackages_rpi4; }
    ];
  };
in sys.config.system.build.sdImage'
```

Point `builtins.getFlake` at the repo path; the `./hosts/...` paths are
relative to the directory you run from.

The result is `result/sd-image/nixos-image-sd-card-<rev>-aarch64-linux.img.zst`.
Rename/copy it to `isos/bigscreen-rpi4-aarch64-linux.img.zst` if you keep
images there.

Confirm it succeeded: the build prints `BUILD_EXIT=0` and the `.img.zst`
appears. Record `sha256sum` of the image.

> The image-assembly steps (`modules-shrunk`, initrd, `mke2fs`) still run as
> aarch64 derivations under emulation, but they are short compared with the
> kernel; only the kernel needed the cross trick.

### Fallback (slow, but simplest)

If you can run this on a real aarch64 machine, or accept the multi-hour
emulated kernel, the plain command is:

```sh
nix build .#nixosConfigurations.bigscreen-rpi4.config.system.build.sdImage
```

`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` (already set in
`hosts/hardware-vbox.nix`) must be applied first on an x86_64 builder.
