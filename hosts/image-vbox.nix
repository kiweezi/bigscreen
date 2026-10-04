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
  # Note: 3D acceleration is intentionally not set here. `VBoxManage modifyvm`
  # applies parameters alphabetically, so `accelerate3d` is applied before
  # `graphicscontroller` and the packaging build fails with
  # "graphics controller does not support the given feature". Enable 3D
  # acceleration per host after importing the appliance (the desktop profile
  # needs VMSVGA + 3D to start a Wayland session).
  virtualbox.params = {
    cpus = 2;
    vram = 128;
    graphicscontroller = "vmsvga";
  };
}
