# The full Bigscreen desktop software stack. Imported only by machines whose
# deployment profile is "full"; bootstrap images never include it.
{ ... }:

{
  imports = [
    ../modules/bigscreen.nix
    ../modules/apps.nix
    ../modules/theme.nix
  ];

  # The installed/full system keeps the historical OpenSSH service (no keys or
  # passwords are configured, so this alone grants no login). Bootstrap images
  # do not import this profile and stay SSH-free.
  services.openssh.enable = true;
}
