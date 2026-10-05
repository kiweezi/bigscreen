{
  description = "Plasma Bigscreen TV interface - Raspberry Pi 4 and VirtualBox GitOps deployments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, comin, ... }:
    let
      # Which deployment profile each managed device follows. This file is the
      # only place promotion is expressed; push a change here to comin/deploy
      # and the device picks it up on its next Comin poll.
      profiles = import ./hosts/deployment-selection.nix;

      # A managed machine: baseline + platform + Comin, with the profile
      # (bootstrap or full) chosen by hosts/deployment-selection.nix. Comin
      # always deploys the matching bigscreen-<target>-deploy output, never an
      # image-builder output.
      mkManaged = { target, system, platform, extraModules ? [ ] }:
        let profile = profiles.${target}; in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit comin; };
          modules = [
            comin.nixosModules.comin
            ./hosts/base.nix
            platform
            ./modules/meta.nix
            ./hosts/comin.nix
            (if profile == "full" then ./hosts/profile-desktop.nix else ./hosts/profile-bootstrap.nix)
            { bigscreen.target = target; bigscreen.profile = profile; }
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        # --- Managed GitOps devices ----------------------------------------
        # Minimal images used only to bootstrap a device. They stay minimal
        # regardless of the deployment selection, so a tag never ships the
        # desktop closure.
        bigscreen-rpi4-bootstrap = mkManaged {
          target = "rpi4";
          system = "aarch64-linux";
          platform = ./hosts/platform-rpi4.nix;
          extraModules = [ nixos-hardware.nixosModules.raspberry-pi-4 ./hosts/image-rpi4.nix ];
        };
        bigscreen-rpi4-deploy = mkManaged {
          target = "rpi4";
          system = "aarch64-linux";
          platform = ./hosts/platform-rpi4.nix;
          extraModules = [ nixos-hardware.nixosModules.raspberry-pi-4 ];
        };
        bigscreen-vbox-bootstrap = mkManaged {
          target = "vbox";
          system = "x86_64-linux";
          platform = ./hosts/platform-vbox.nix;
          extraModules = [ ./hosts/image-vbox.nix ];
        };
        bigscreen-vbox-deploy = mkManaged {
          target = "vbox";
          system = "x86_64-linux";
          platform = ./hosts/platform-vbox.nix;
          extraModules = [ ];
        };

        # --- Pre-existing outputs (kept working unchanged) -----------------
        # Real hardware target: Raspberry Pi 4 Model B (aarch64), booted from SD card.
        bigscreen-rpi4 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-rpi4.nix
            nixos-hardware.nixosModules.raspberry-pi-4
          ];
        };

        # Test target: Oracle VirtualBox VM (x86_64). See hosts/hardware-vbox.nix
        # for the expected partition labels and VM settings.
        bigscreen-vbox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-vbox.nix
          ];
        };

        # Bootable live ISO of the Bigscreen system (x86_64).
        bigscreen-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-iso.nix
          ];
        };
      };

      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          rpi4Deploy = self.nixosConfigurations.bigscreen-rpi4-deploy.config;
          vboxDeploy = self.nixosConfigurations.bigscreen-vbox-deploy.config;
          rpi4Boot = self.nixosConfigurations.bigscreen-rpi4-bootstrap.config;
          vboxBoot = self.nixosConfigurations.bigscreen-vbox-bootstrap.config;
          mainRemote = builtins.head rpi4Boot.services.comin.remotes;
          check = name: cond:
            pkgs.runCommand "check-${name}" { } (
              if cond then
                "touch $out"
              else
                "echo 'bigscreen check failed: ${name}' >&2; exit 1"
            );
        in
        {
          rpi4-deploy-comin = check "rpi4-deploy-comin" (
            rpi4Deploy.services.comin.enable
            && rpi4Deploy.services.comin.hostname == "bigscreen-rpi4-deploy"
          );
          vbox-deploy-comin = check "vbox-deploy-comin" (
            vboxDeploy.services.comin.enable
            && vboxDeploy.services.comin.hostname == "bigscreen-vbox-deploy"
          );
          bootstrap-branch-policy = check "bootstrap-branch-policy" (
            mainRemote.branches.main.name == "comin/deploy"
            && mainRemote.branches.testing.name == ""
          );
          bootstrap-no-ssh = check "bootstrap-no-ssh" (
            !rpi4Boot.services.openssh.enable && !vboxBoot.services.openssh.enable
          );
          vbox-bootstrap-minimal = check "vbox-bootstrap-minimal" (
            vboxBoot.bigscreen.profile == "bootstrap"
            && !(vboxBoot.services.xserver.enable or false)
            && !(vboxBoot.services.displayManager.enable or false)
          );
          legacy-outputs-ssh = check "legacy-outputs-ssh" (
            rpi4Deploy.services.openssh.enable && vboxDeploy.services.openssh.enable
          );
          pideploy-profile-bootstrap = check "pideploy-profile-bootstrap" (
            rpi4Deploy.bigscreen.profile == "bootstrap"
          );
        });
    };
}
