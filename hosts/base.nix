# Baseline configuration shared by every Bigscreen machine: accounts,
# networking, locale and the tools needed to evaluate this flake. Desktop
# software lives in profile-desktop.nix; hardware lives in platform-*.nix.
{ lib, pkgs, ... }:

{
  imports = [ ./ssh.nix ];

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

  # Binary cache holding the Raspberry Pi vendor kernel and Comin — the two
  # store paths Hydra/cache.nixos.org do not provide for aarch64. Everything
  # else substitutes from cache.nixos.org, so devices and dev VMs download the
  # kernel instead of building it for hours. This is public config: only
  # pushing needs a token, and that lives in CI (CACHIX_AUTH_TOKEN secret).
  nix.settings.extra-substituters = [ "https://kiweezi-rpi-bigscreen.cachix.org" ];
  nix.settings.extra-trusted-public-keys =
    [ "kiweezi-rpi-bigscreen.cachix.org-1:4l+G9VDeEh8CdNG0+OqeUgXvNpkwwQ8m7ReBHm0aPwQ=" ];

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

  # SSH is provided by hosts/ssh.nix (imported above): key-only, with the
  # committed public key, for administration and headless-boot debugging.

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
