# Bootable live ISO of the Bigscreen system (x86_64). Booting it starts the
# graphical Plasma Bigscreen session straight from the image - there is no disk
# install, so it doubles as a "first revision" you can boot anywhere.
{ modulesPath, lib, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
  ];

  isoImage = {
    # Hybrid image: boots from CD/DVD (BIOS), USB and EFI.
    makeBiosBootable = true;
    makeEfiBootable = true;
    makeUsbBootable = true;
    isoName = "bigscreen-x86_64-linux.iso";
  };

  # A live ISO has no GPU driver or hardware GL, so force Mesa software
  # rendering to let the Wayland compositor start (e.g. booted in a VM).
  environment.sessionVariables = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    GALLIUM_DRIVER = "llvmpipe";
  };
}
