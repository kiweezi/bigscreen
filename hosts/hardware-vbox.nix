# Hardware configuration for testing in an Oracle VirtualBox VM.
# Use this to validate the Bigscreen/YouTube setup before flashing an SD card.
#
# This targets a BIOS/legacy-boot VirtualBox VM (the terrarium-managed test
# VM created via VBoxManage defaults to BIOS, not UEFI), using GRUB with an
# MBR partition table:
#
#   parted /dev/sda -- mklabel msdos
#   parted /dev/sda -- mkpart primary ext4 1MiB 100%
#   mkfs.ext4 -L nixos /dev/sda1
#   mount /dev/sda1 /mnt
#
# If your VM instead has EFI enabled (Settings > System > Motherboard >
# Enable EFI), use an EFI System Partition + systemd-boot instead - see the
# git history of this file for that variant.
{ config, pkgs, lib, modulesPath, ... }:

{
  # Guest integration (drivers, clipboard, shared folders) for running as a
  # VirtualBox guest. This is NOT the image-builder module - you still
  # install NixOS the normal way from the official ISO inside the VM.
  virtualisation.virtualbox.guest.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  swapDevices = [ ];

  hardware.graphics.enable = true;

  # VirtualBox's emulated VMSVGA (vmwgfx) GPU does not hand the guest a working
  # hardware GL context unless the Guest Additions version matches the host's
  # VirtualBox exactly (here they don't, so the 3D channel fails to open).
  # kwin_wayland then aborts during GL/EGL init and the session never starts.
  # Force Mesa's software rasteriser so the compositor can come up. This is a
  # VM-only workaround - the Raspberry Pi target uses its own VideoCore GPU.
  environment.sessionVariables = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    GALLIUM_DRIVER = "llvmpipe";
  };

  # Note: CPU microcode updates (hardware.cpu.intel/amd.updateMicrocode) are
  # a host-level concern and don't apply inside a VirtualBox guest, so they
  # are intentionally omitted here.

  # Lets this VM act as a build machine for the aarch64-linux Raspberry Pi
  # image (`nix build .#nixosConfigurations.bigscreen-rpi4...`). Without
  # this, any derivation that isn't already in the aarch64 binary cache
  # fails with "platform mismatch". This registers a QEMU-based binfmt
  # interpreter and adds aarch64-linux to nix's usable build platforms.
  # Builds that fall back to emulation are much slower than native/cached
  # builds, but this keeps things working with no extra infrastructure.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nixpkgs.hostPlatform = "x86_64-linux";

  system.stateVersion = "24.11";
}
