# Compatibility module for the existing bigscreen-rpi4 output: the platform
# plus the flashable SD-card image builder.
{ modulesPath, ... }:

{
  imports = [
    ./platform-rpi4.nix
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];
}
