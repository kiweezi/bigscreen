# Shared configuration for the Plasma Bigscreen TV interface.
# Hardware-specific settings live in hardware-rpi4.nix / hardware-vbox.nix.
{ config, pkgs, lib, ... }:

{
  imports = [
    ../modules/bigscreen.nix
    ../modules/apps.nix
    ../modules/theme.nix
  ];

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

  # sshd refuses empty passwords (PermitEmptyPasswords defaults to no), so
  # password logins are impossible; add an openssh.authorizedKeys.keys list to
  # the htpc user if remote access is ever needed.
  services.openssh.enable = true;

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
