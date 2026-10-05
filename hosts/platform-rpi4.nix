# Runtime hardware configuration for real Raspberry Pi 4 Model B hardware.
# Booted from an SD card created by hosts/image-rpi4.nix, and combined with
# nixos-hardware's raspberry-pi-4 module at the flake level.
{ lib, pkgs, ... }:

{
  # Bootloader: use the U-Boot/extlinux-based boot that both nixos-hardware's
  # raspberry-pi-4 module and the sd-image-aarch64 module expect.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Mainline kernel: the nixos-hardware raspberry-pi-4 module selects a custom
  # vendor kernel with `lib.mkDefault`, so this overrides it. Mainline is in the
  # aarch64 binary cache (the vendor kernel is not), which makes the bootstrap
  # image build fast. Pi-specific hardware that needs vendor drivers may be
  # affected; this is an intentional trade-off.
  boot.kernelPackages = pkgs.linuxPackages;

  # nixos-hardware stages the Raspberry Pi firmware partition itself, and only
  # chainloads U-Boot (which then reads extlinux.conf from the root partition)
  # when this is enabled. With it off, the firmware partition has no bootable
  # kernel and the Pi stops at the firmware splash with a black screen. Enable
  # it so the SD image is actually bootable, and keep the running system's
  # firmware partition in sync across deploys.
  hardware.raspberry-pi.firmware.enable = true;
  hardware.raspberry-pi.firmware.uboot.enable = true;

  # Load the kernel's own device tree (via extlinux FDT) instead of the vendor
  # firmware DTB. The mainline kernel must be paired with its matching DTB;
  # otherwise vc4/HDMI fails to probe (endless "vc4_hdmi ... PCM component
  # -517" loop) and there is no DRM connector, so the desktop renders nowhere.
  boot.loader.generic-extlinux-compatible.useGenerationDeviceTree = lib.mkForce true;

  # The Raspberry Pi vendor kernel does not provide every module in nixpkgs'
  # large default initrd module list (e.g. dw-hdmi is not built on this board).
  # Without this the image build fails in the module-shrinking step with
  # "modprobe: FATAL: Module ... not found".
  boot.initrd.allowMissingModules = true;

  # sd-image-aarch64.nix creates the root filesystem with label NIXOS_SD;
  # declare "/" here to match once the image is flashed and booted.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # Rpi4 has no swap partition by default; keep zram to avoid OOM under Plasma.
  zramSwap.enable = true;

  networking.wireless.enable = lib.mkDefault false; # use NetworkManager instead

  # GPU: VideoCore VI, needed for hardware-accelerated Plasma/Wayland.
  hardware.graphics.enable = true;

  # Pi4 boards commonly need this for HDMI audio / display quirks.
  boot.kernelParams = [ "cma=256M" ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "24.11";
}
