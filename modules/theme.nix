# "Apple TV"-style theming for the Bigscreen session.
#
# - A macOS-like look-and-feel (WhiteSur-dark) for the desktop theme, colours,
#   icons and cursor.
# - Inter as the San Francisco substitute (Apple's SF Pro is not
#   redistributable and is not packaged in nixpkgs; Inter is the usual open
#   stand-in - swap the family name below once you drop in the real SF fonts).
# - The wallpapers in media/wallpapers shipped as Plasma wallpaper packages, so
#   they are selectable in the Bigscreen settings, with a default one applied.
{ config, pkgs, lib, ... }:

let
  wallpaperSrc = ../media/wallpapers;
  files = builtins.attrNames (builtins.readDir wallpaperSrc);
  stemOf = f: builtins.head (builtins.match "(.*)\\.[^.]*" f);
  idOf = f: builtins.replaceStrings [ " " ] [ "-" ] (stemOf f);
  # Title-case a kebab-case stem for the picker (e.g. "mount-fuji" -> "Mount Fuji").
  cap = w: lib.toUpper (builtins.substring 0 1 w) + builtins.substring 1 (builtins.stringLength w) w;
  prettyOf = f: lib.concatStringsSep " " (map cap (lib.splitString "-" (idOf f)));

  # Install every image as a Plasma wallpaper package (share/wallpapers/<id>/
  # {metadata.json,contents/images}) so the Image wallpaper plugin lists it.
  wallpapers = pkgs.runCommand "bigscreen-wallpapers" { } (
    lib.concatMapStrings (f: ''
      d="$out/share/wallpapers/${idOf f}"
      mkdir -p "$d/contents/images"
      cp "${wallpaperSrc}/${f}" "$d/contents/images/${f}"
      cat > "$d/metadata.json" <<EOF
      { "KPlugin": { "Id": "${idOf f}", "Name": "${prettyOf f}", "License": "Unknown" } }
      EOF
    '') files
  );

  defaultWallpaper = "${wallpapers}/share/wallpapers/the-valley-of-the-god/contents/images/the-valley-of-the-god.jpg";
in
{
  environment.systemPackages = [
    wallpapers # the wallpaper packages (visible in the wallpaper picker)
    pkgs.whitesur-kde # macOS-like look-and-feel / desktop theme / colour schemes
    pkgs.whitesur-icon-theme # WhiteSur icons
    pkgs.whitesur-cursors # WhiteSur cursor theme
  ];

  # systemPackages only merges the share/ subdirs listed here into the profile
  # (and therefore onto XDG_DATA_DIRS), so Plasma/WhiteSur can find the themes
  # and the wallpaper packages.
  environment.pathsToLink = [
    "/share/wallpapers"
    "/share/plasma"
    "/share/color-schemes"
    "/share/aurorae"
    "/share/ksplash"
  ];

  # Make the SF substitute available to fontconfig.
  fonts.packages = [ pkgs.inter ];

  # Apply the theme and default wallpaper once the shell is up, every session.
  systemd.user.services.bigscreen-theme = {
    description = "Apply the Bigscreen Apple (WhiteSur) theme and wallpaper";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "plasma-plasmashell.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      export PATH="${pkgs.kdePackages.plasma-workspace}/bin:${pkgs.kdePackages.kconfig}/bin:$PATH"

      # macOS-like look-and-feel: desktop theme, colour scheme, icons, cursor,
      # window decoration.
      plasma-apply-lookandfeel -a com.github.vinceliuice.WhiteSur-dark || true

      # San Francisco stand-in (Inter) as the general UI font.
      kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,50,0,0,0,0,0"

      # Default wallpaper from media/wallpapers.
      plasma-apply-wallpaperimage "${defaultWallpaper}" || true
    '';
  };
}
