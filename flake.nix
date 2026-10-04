{
  description = "Plasma Bigscreen TV interface - Raspberry Pi 4 and VirtualBox test configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }:
    {
      nixosConfigurations = {
        # Real hardware target: Raspberry Pi 4 Model B (aarch64), booted from SD card.
        bigscreen-rpi4 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-rpi4.nix
            nixos-hardware.nixosModules.raspberry-pi-4
          ];
        };

        # Test target: Oracle VirtualBox VM (x86_64). Install NixOS from the
        # normal NixOS ISO inside the VM, then point it at this flake
        # (`nixos-rebuild switch --flake .#bigscreen-vbox`) instead of the
        # generated hardware-configuration.nix. See hosts/hardware-vbox.nix
        # for recommended VM settings and partition labels.
        bigscreen-vbox = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-vbox.nix
          ];
        };

        # Bootable live ISO of the Bigscreen system (x86_64) - boots the
        # graphical session straight from the image. Build with:
        #   nix build .#nixosConfigurations.bigscreen-iso.config.system.build.isoImage
        bigscreen-iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/common.nix
            ./hosts/hardware-iso.nix
          ];
        };
      };
    };
}
