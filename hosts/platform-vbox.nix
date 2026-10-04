# Runtime hardware configuration for the Oracle VirtualBox test target.
# The installed appliance image is built by hosts/image-vbox.nix, which
# imports this module and the upstream virtualbox-image builder; the boot and
# filesystem values here are mkDefault so that builder can override them.
{ lib, pkgs, ... }:

{
  # Guest integration (drivers, clipboard, shared folders) for running as a
  # VirtualBox guest.
  virtualisation.virtualbox.guest.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/nixos";
    fsType = lib.mkDefault "ext4";
  };

  swapDevices = lib.mkDefault [ ];

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

  # Lets this VM act as a build machine for the aarch64-linux Raspberry Pi
  # image. Without this, any derivation that isn't already in the aarch64
  # binary cache fails with "platform mismatch".
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nixpkgs.hostPlatform = "x86_64-linux";

  system.stateVersion = "24.11";
}
