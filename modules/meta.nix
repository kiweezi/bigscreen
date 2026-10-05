# Deployment metadata and cross-cutting invariants for the managed machines.
# Every managed output sets `bigscreen.target` and `bigscreen.profile`; the
# assertions keep the deployment contract honest regardless of which modules
# a target imports.
{ config, lib, ... }:

{
  options.bigscreen = {
    target = lib.mkOption {
      type = lib.types.enum [ "rpi4" "vbox" ];
      description = "Hardware platform this machine is deployed to.";
    };
    profile = lib.mkOption {
      type = lib.types.enum [ "bootstrap" "full" ];
      description = "Deployment profile selected by the comin/deploy branch.";
    };
  };

  config = {
    assertions = [
      {
        assertion =
          !(config.services.comin.enable or false)
          || config.services.comin.hostname == "bigscreen-${config.bigscreen.target}-deploy";
        message = "bigscreen: comin must select the matching bigscreen-<target>-deploy output.";
      }
      {
        assertion =
          config.bigscreen.profile != "bootstrap"
          || !(config.services.xserver.enable or false);
        message = "bigscreen: a bootstrap profile must not enable the X server.";
      }
      {
        assertion =
          config.bigscreen.profile != "bootstrap"
          || !(config.services.displayManager.enable or false);
        message = "bigscreen: a bootstrap profile must not enable a display manager.";
      }
    ];
  };
}
