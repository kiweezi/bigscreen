# TEMPORARY VM-test access. Removed in the final VM-test commit. Not part of
# the Pi outputs. Enables SSH on the VirtualBox bootstrap/deploy machines only,
# using a throwaway public key, so the test harness can drive the guest.
{ ... }:

{
  bigscreen.allowTestSsh = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  users.users.htpc.openssh.authorizedKeys.keyFiles = [ ./ci-vm-access.pub ];

  environment.etc."bigscreen-vm-marker".text = "marker-2";
}
