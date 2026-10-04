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

  boot.kernelPackages = pkgs.linuxPackages_rpi4;

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
