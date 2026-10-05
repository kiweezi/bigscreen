# Which profile each managed device follows. "bootstrap" is the minimal
# image-only system; "full" is the Bigscreen desktop. Push a change here to the
# comin/deploy branch to deploy it. The Pi row stays "bootstrap" until its
# configuration is intentionally promoted.
{
  rpi4 = "full";
  vbox = "full";
}
