# Media and desktop applications offered by the Bigscreen launcher, plus a
# Flatpak "app store" (KDE Discover backed by Flathub) for occasional installs.
{ config, pkgs, lib, ... }:

{
  # Drop packages that aren't available on this host's platform - e.g. Spotify
  # is x86_64-only, so it is present on the VM/ISO but absent from the aarch64
  # Raspberry Pi image.
  environment.systemPackages =
    let
      supported = p: lib.meta.availableOn pkgs.stdenv.hostPlatform p;
    in
    builtins.filter supported (with pkgs; [
      # Streaming / media
      kodi
      jellyfin-media-player
      moonlight-qt
      spotify
      # Desktop
      kdePackages.konsole # terminal
      kdePackages.dolphin # file manager
      kdePackages.kate # text editor
      notepad-next # text editor
      blanket # ambient sound player
      trayscale # Tailscale GUI (see services.tailscale below)
      # App store (Flatpak/Flathub is its back end; see below).
      kdePackages.discover
    ]);

  # --- Tailscale (so Trayscale works) -------------------------------------
  services.tailscale.enable = true;

  # Let the htpc user drive tailscaled without root, which the Trayscale GUI
  # needs. Authenticate the node once with `sudo tailscale up`.
  systemd.services.tailscale-operator = {
    description = "Allow htpc to control Tailscale (for Trayscale)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${pkgs.tailscale}/bin/tailscale set --operator=htpc || true";
  };

  # --- App store: Flatpak + Flathub ---------------------------------------
  # Discover offers these in a GUI; anything installed from Flathub lands in
  # /var/lib/flatpak (added to the profile by this module) and shows up in the
  # Bigscreen launcher.
  services.flatpak.enable = true;

  # Stremio, Open TV, Zen Browser and Steam Link are not packaged in nixpkgs
  # (Stremio's nixpkgs package builds a heavy Rust/GTK tree from source), so
  # install them from Flathub. Declarative and idempotent (re-runs are no-ops).
  # Triggered by a timer ~1 min after boot so a large first download never
  # gates boot.
  systemd.services.flatpak-managed-install = {
    description = "Install managed Flatpak apps from Flathub";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "flatpak-system-helper.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30min";
    };
    script = ''
      ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub \
        https://flathub.org/repo/flathub.flatpakrepo || true
      # Install each app on its own so a Flathub app that does not exist for
      # this architecture (e.g. Steam Link / Zen Browser on aarch64) is skipped
      # instead of failing the whole service - a failing oneshot here would also
      # make switch-to-configuration (and therefore a Comin deployment) fail.
      for app in com.stremio.Stremio dev.fredol.open-tv app.zen_browser.zen com.valvesoftware.SteamLink; do
        if ! ${pkgs.flatpak}/bin/flatpak install --system --noninteractive --assumeyes flathub "$app"; then
          echo "flatpak: $app is not available for this architecture, skipping" >&2
        fi
      done
    '';
  };

  systemd.timers.flatpak-managed-install = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      Unit = "flatpak-managed-install.service";
    };
  };
}
