# Shared Comin (GitOps) configuration. Every managed machine pulls the public
# repository's comin/deploy branch and evaluates its bigscreen-<target>-deploy
# output. `bigscreen.target` and `bigscreen.profile` come from modules/meta.nix.
{ config, pkgs, comin, ... }:

{
  services.comin = {
    enable = true;
    # Use the package from the comin input we pin, rather than whatever
    # version nixpkgs happens to ship.
    package = comin.packages.${pkgs.stdenv.hostPlatform.system}.default;
    hostname = "bigscreen-${config.bigscreen.target}-deploy";
    remotes = [
      {
        name = "origin";
        url = "https://github.com/kiweezi/bigscreen.git";
        # Deploy only this branch. An empty testing name disables comin's
        # default testing-<hostname> branch selection, so a stray testing
        # branch can never be activated on a device.
        branches.main.name = "comin/deploy";
        branches.testing.name = "";
        poller.period = 60;
      }
    ];
    evalTimeout = 1800;
    # The first full deployment builds the whole desktop closure on the device.
    buildTimeout = 7200;
    debug = false;
    # Bind the Prometheus exporter to loopback; the firewall port stays closed.
    exporter.listen_address = "127.0.0.1";
  };
}
