# Baseline configuration shared by every Bigscreen machine: accounts,
# networking, locale and the tools needed to evaluate this flake. Desktop
# software lives in profile-desktop.nix; hardware lives in platform-*.nix.
{ lib, pkgs, ... }:

{
  # --- Basics -----------------------------------------------------------
  time.timeZone = "Europe/Oslo";
  i18n.defaultLocale = "en_US.UTF-8";

  # Explicit US keyboard layout for both the console and the graphical
  # session. Without this, SDDM's "Layout" picker shows a bogus "zz" entry
  # and the layout cannot be changed.
  services.xserver.xkb.layout = "us";
  services.xserver.xkb.variant = "";
  console.keyMap = "us";

  networking.hostName = "bigscreen-tv";
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # GitOps deployments evaluate this flake on the machine itself.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- User account -------------------------------------------------------
  # No passwords anywhere: this machine is not exposed to the public internet
  # and stores nothing sensitive. An empty hashed password ("") is a
  # passwordless account; SDDM autologin does not need one, and
  # wheelNeedsPassword = false lets htpc use sudo without a prompt.
  users.mutableUsers = false;

  users.users.root.hashedPassword = "";

  users.users.htpc = {
    isNormalUser = true;
    description = "Bigscreen HTPC user";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    hashedPassword = "";
  };

  security.sudo.wheelNeedsPassword = false;

  # SSH is intentionally not enabled here: public bootstrap images expose no
  # remote login. Add openssh.authorizedKeys.keys to htpc if a deployment
  # ever needs it, and enable services.openssh in that profile.

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];

  # Free up disk space / keep the SD card image small.
  documentation.nixos.enable = false;
  documentation.man.enable = false;

  system.stateVersion = "24.11";
}
