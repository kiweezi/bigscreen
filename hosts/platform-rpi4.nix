# Runtime hardware configuration for real Raspberry Pi 4 Model B hardware.
# Booted from an SD card created by hosts/image-rpi4.nix, and combined with
# nixos-hardware's raspberry-pi-4 module at the flake level.
{ config, lib, pkgs, ... }:

let
  cfg = config.bigscreen.rpi4;
in
{
  options.bigscreen.rpi4.hdmiMode = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "1920x1080@60";
    description = ''
      Force the HDMI output to this DRM mode (for example "1920x1080@60").

      null keeps the display's own preferred mode. On a 4K TV that means a
      3840x2160 desktop, which the Pi 4 GPU cannot composite at a comfortable
      frame rate; set e.g. "1920x1080@60" to trade resolution for smoothness.
      The connector is HDMI-A-1 (the first/primary HDMI port).
    '';
  };

  config = {
    # Bootloader: use the U-Boot/extlinux-based boot that both nixos-hardware's
    # raspberry-pi-4 module and the sd-image-aarch64 module expect.
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

    # Kernel: nixos-hardware's raspberry-pi-4 module selects the Raspberry Pi
    # vendor kernel (`linux-rpi`, stable_* tag) with `lib.mkDefault`, so we let
    # it. The vendor kernel is required for usable graphics on a Pi 4: the
    # mainline kernel's vc4/v3d driver imports SWIOTLB bounce buffers as dma-buf,
    # which the VC4 display driver cannot import. That prints endless
    # "vc4-drm gpu: swiotlb buffer is full" in dmesg and "drmPrimeFDToHandle()
    # failed" from KWin, so the compositor cannot share GPU buffers and the
    # whole session crawls. The vendor kernel carries the downstream fix
    # (drm: vc4: Block swiotlb bounce buffers being imported), plus the
    # `bcm2835-codec` V4L2 hardware video decoder that mainline nixpkgs does not
    # build, so /dev/video* actually exists.
    #
    # See: https://github.com/raspberrypi/linux/issues/3416

    # nixos-hardware stages the Raspberry Pi firmware partition itself, and only
    # chainloads U-Boot (which then reads extlinux.conf from the root partition)
    # when this is enabled. With it off, the firmware partition has no bootable
    # kernel and the Pi stops at the firmware splash with a black screen. Enable
    # it so the SD image is actually bootable, and keep the running system's
    # firmware partition in sync across deploys.
    hardware.raspberry-pi.firmware.enable = true;
    hardware.raspberry-pi.firmware.uboot.enable = true;

    # With U-Boot enabled nixos-hardware defaults useGenerationDeviceTree to
    # false, so U-Boot boots the firmware-supplied DTB with the config.txt
    # device-tree overlays applied (notably vc4-kms-v3d, which enables the V3D
    # GPU and the hardware video decoder). The vendor kernel matches that DTB.
    # Do NOT force the generation DTB here: doing so makes U-Boot reload a bare
    # landed tree and silently drops those overlays.

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

    # --- Easy performance toggle -----------------------------------------
    # Set to e.g. "1920x1080@60" to force a lighter HDMI mode. A 4K desktop is
    # very heavy for the Pi 4 GPU; 1080p is a large, immediate FPS win. This is
    # the one line to change to trade resolution for smoothness.
    bigscreen.rpi4.hdmiMode = lib.mkDefault null;

    # cma=256M is the Raspberry Pi default for the vc4 GPU; override it here so
    # it is explicit. When bigscreen.rpi4.hdmiMode is set, pin the DRM mode too.
    boot.kernelParams = [ "cma=256M" ]
      ++ lib.optional (cfg.hdmiMode != null) "video=HDMI-A-1:${cfg.hdmiMode}";

    nixpkgs.hostPlatform = "aarch64-linux";

    system.stateVersion = "24.11";
  };
}
