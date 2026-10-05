# KDE Plasma Bigscreen "10-foot" TV interface, with an ad-free YouTube app
# (VacuumTube - a YouTube "Leanback" client with no ads, no tracking, no
# Google sign-in requirement) pinned to the Bigscreen launcher.
{ config, pkgs, lib, ... }:

{
  # Upstream plasma-bigscreen doesn't pull in kdeconnect-kde, whose QML
  # module (org.kde.kdeconnect) the Bigscreen HomeScreen/HomeHeader and
  # KDEConnect indicators require. Without it, the session fails to load
  # its home screen and crashes straight back to SDDM after login.
  # See: https://discourse.nixos.org/t/getting-kde-plasma-bigscreen-to-work-on-nixos/79086
  nixpkgs.overlays = [
    (final: prev: {
      kdePackages = prev.kdePackages // {
        plasma-bigscreen = prev.kdePackages.plasma-bigscreen.overrideAttrs (old: {
          buildInputs = (old.buildInputs or [ ]) ++ [ prev.kdePackages.kdeconnect-kde ];
          # Two inputhandler fixes, see ./plasma-bigscreen-return-button.patch:
          #  - Make the TV remote's Return button escape fullscreen apps: a
          #    quick press injects Esc into the focused app as before (in-app
          #    back), a long press emits the shell's "home action" instead,
          #    which minimizes the app and shows the home overlay. Without it,
          #    apps that ignore Esc (Bigscreen settings, Discover) trap a
          #    remote-only user.
          #  - Retry setting up the XDG remote-desktop portal input session:
          #    at session start the input handler usually wins the race
          #    against xdg-desktop-portal, and upstream never retries, so no
          #    injected key (navigation, Enter, short Return) works for the
          #    whole session.
          patches = (old.patches or [ ]) ++ [ ./plasma-bigscreen-return-button.patch ];
          # Replace the stock launcher with an organised one (Media / Games /
          # Utilities / Other sections + hidden apps). See the QML's header.
          postInstall = (old.postInstall or "") + ''
            install -m644 ${./bigscreen-launcher/LauncherHome.qml} \
              $out/share/plasma/plasmoids/org.kde.bigscreen.homescreen/contents/ui/launcher/LauncherHome.qml
          '';
          preFixup = (old.preFixup or "") + ''
            wrapQtApp $out/bin/plasma-bigscreen-wayland \
              --prefix QML2_IMPORT_PATH : "${prev.kdePackages.kdeconnect-kde}/lib/qt-6/qml"
          '';
        });
      };
    })
  ];

  # Plasma Bigscreen is a Wayland session; enable the X server too so SDDM
  # has a graphical login target and X11 apps/drivers still work as fallback.
  services.xserver.enable = true;

  # Fixes the SDDM keyboard-layout selector showing a broken "zz" flag/code
  # with no way to change it: it defaults to a placeholder when no layout
  # is configured.
  services.xserver.xkb.layout = "us";

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.defaultSession = "plasma-bigscreen-wayland";

  # The session's .desktop file must be registered via sessionPackages for
  # the display manager to find "plasma-bigscreen-wayland" - merely listing
  # the package in environment.systemPackages is not enough.
  services.displayManager.sessionPackages = [ pkgs.kdePackages.plasma-bigscreen ];

  # Auto-login straight into Bigscreen, like a real TV/set-top box.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "htpc";

  # Audio via PipeWire (recommended stack for Plasma).
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Needed for KDE Connect / remote-control style input used by Bigscreen.
  programs.kdeconnect.enable = true;

  # The Bigscreen session (plasma-bigscreen-wayland) sources its own
  # common-env (PLASMA_PLATFORM=mediacenter, PLASMA_DEFAULT_SHELL=
  # org.kde.plasma.bigscreen) and then runs plasmashell, which loads the
  # Bigscreen shell *because of those env vars*. So we must NOT enable
  # services.desktopManager.plasma6 - its own plasmashell autostart runs with
  # the regular desktop environment and overrides Bigscreen. Instead we
  # declare just the session runtime pieces the launcher execs from PATH but
  # that plasma-bigscreen only pulls in as build deps.
  environment.systemPackages = with pkgs; [
    kdePackages.plasma-bigscreen
    kdePackages.plasma-workspace # startplasma-wayland, plasmashell, ksplashqml
    kdePackages.kwin # kwin_wayland (compositor)
    # The Bigscreen session launches KWin with --xwayland; without the
    # Xwayland binary present KWin logs "Xwayland process failed to start" and
    # leaves $DISPLAY pointing at a dead socket, so plasma-kcminit's `xrdb`
    # step hangs and times out, blocking plasmashell from ever starting.
    xwayland
    kdePackages.kded # kded6 (session daemons)
    kdePackages.kactivitymanagerd # plasmashell aborts shell load without it
    # Qt6 KDE platform theme; without it QKdeTheme::createKdeTheme SIGSEGVs.
    kdePackages.plasma-integration
    # The Bigscreen HomeScreen reuses desktop applet backends whose private QML
    # modules (org.kde.plasma.private.batterymonitor / .volume,
    # org.kde.plasma.networkmanagement, org.kde.milou) are NOT pulled in by
    # plasma-bigscreen itself. Without them the home screen aborts on the first
    # missing import ("module ... is not installed").
    kdePackages.powerdevil
    kdePackages.plasma-pa
    kdePackages.plasma-nm
    kdePackages.milou
    vacuum-tube # ad-free YouTube "Leanback" client, launched from Bigscreen
  ];

  # systemPackages does NOT put those packages' lib/qt-6/qml on plasmashell's
  # wrapped QML import path. plasmashell's QML engine searches QML2_IMPORT_PATH
  # (the wrapQtApp hook *prepends* its own paths to whatever is already there),
  # so setting it as a session variable makes the applet modules resolvable.
  # (QT_QML_IMPORT_PATH is NOT consulted for applet loading - verified.)
  environment.sessionVariables.QML2_IMPORT_PATH = lib.makeSearchPathOutput "lib" "lib/qt-6/qml" [
    pkgs.kdePackages.powerdevil
    pkgs.kdePackages.plasma-pa
    pkgs.kdePackages.plasma-nm
    pkgs.kdePackages.milou
  ];

  # org.kde.plasma.private.batterymonitor (used by the Bigscreen HomeScreen's
  # PowerManagementItem) queries UPower over D-Bus; without the daemon it logs
  # "UPowerManager::allDevices ... ServiceUnknown".
  services.upower.enable = true;

  # Bigscreen sets PLASMA_INTEGRATION_USE_PORTAL=1 and its Input Handler uses
  # the remote-desktop portal; provide the KDE portal backend.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # Firewall: allow local discovery/casting protocols Bigscreen apps expect.
  networking.firewall.allowedTCPPorts = [ 1716 ];
  networking.firewall.allowedUDPPorts = [ 1716 ];
}
