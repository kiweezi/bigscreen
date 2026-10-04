# The full Bigscreen desktop software stack. Imported only by machines whose
# deployment profile is "full"; bootstrap images never include it.
{ ... }:

{
  imports = [
    ../modules/bigscreen.nix
    ../modules/apps.nix
    ../modules/theme.nix
  ];
}
