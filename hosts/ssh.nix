# SSH access for administering the machines and debugging headless boots.
# Key-only: password and root login are disabled. The public key committed here
# is not a secret; the matching private key stays off the repository.
{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.htpc.openssh.authorizedKeys.keyFiles = [ ./bigscreen.pub ];
}
