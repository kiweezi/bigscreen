# Flashable SD-card image builder for the Pi bootstrap output. It layers the
# upstream aarch64 SD-image module on top of hosts/platform-rpi4.nix, which
# supplies the bootloader, kernel, filesystem and zram settings. The deployed
# bigscreen-rpi4-deploy output does not import this, so it is not an image.
{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];
}
