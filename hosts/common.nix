# Compatibility module: the original monolithic host configuration is now the
# baseline plus the desktop profile. Kept so the existing bigscreen-rpi4,
# bigscreen-vbox and bigscreen-iso outputs keep working unchanged.
{ ... }:

{
  imports = [
    ./base.nix
    ./profile-desktop.nix
  ];
}
