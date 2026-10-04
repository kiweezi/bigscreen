# Installed VirtualBox appliance builder for the bootstrap output. The upstream
# virtualbox-image module supplies the MBR/GRUB layout, the labelled root
# filesystem, swap, Guest Additions and the OVA export; hosts/platform-vbox.nix
# supplies the runtime quirks at mkDefault so this module's values win. The
# deployed bigscreen-vbox-deploy output does not import this.
{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/virtualbox-image.nix")
  ];

  # Room for the full desktop closure and several deployment generations once
  # the device is promoted to the "full" profile.
  virtualisation.diskSize = 32768;

  virtualbox.memorySize = 4096;
  virtualbox.params = {
    cpus = 2;
    vram = 128;
    graphicscontroller = "vmsvga";
    accelerate3d = "on";
  };
}
