---
name: iterating-nixos-in-vbox
description: 'Use when testing or iterating any NixOS configuration in an Oracle VirtualBox VM through the terrarium MCP (env_exec, env_push, env_fork, env_promote, env_screenshot) - bootstrapping SSH on an installer ISO, getting config changes onto the guest, running nixos-rebuild, diagnosing why a boot or graphical session fails, promoting and re-forking a golden image, or deciding whether an app should come from nixpkgs versus Flatpak/Flathub. Keywords: terrarium, VirtualBox, vbox, nixos-rebuild switch, nixos-install, env_push, env_exec, base64, golden, fork, share_host_path, shared folder, VMSVGA, sshd, systemd-udevd, SDDM, kwin_wayland, Wayland, black screen, nixpkgs over Flatpak, Flathub, comin, comin/deploy, GitOps, pull-mode deployment, bootstrap image.'
metadata:
  version: "1.1.0"
---

# Iterating a NixOS configuration in a VirtualBox VM (terrarium)

**REQUIRED BACKGROUND:** This skill covers only the terrarium/VM iteration
*mechanism*. For NixOS itself - module options, flakes, `nixos-rebuild`
semantics, overlays, packaging, systemd services - load the **`nixos`** skill.

## Core principle

Drive the guest entirely through the terrarium MCP over **SSH** (`env_exec`,
`env_push`, `env_screenshot`). **Never** transfer files by typing base64
chunks with `env_type` - it is slow, fragile (stuck-key glitches), and lost on
every reboot because a live ISO is tmpfs. Edit files **locally**, push them
with `env_push`, rebuild with `env_exec`, look with `env_screenshot`. The
committed config is the single source of truth; every fix lands in code, not
in ad-hoc guest commands.

## Package sourcing: prefer nixpkgs over Flatpak

When the configuration needs an application, **prefer the nixpkgs package over a
Flatpak (Flathub) or other bundled format wherever one exists and is
reasonable.** nixpkgs pins and provides every dependency and builds
reproducibly from source - that is the whole point of Nix. A Flatpak instead
hides its dependencies in a sandbox and floats outside the store, so it is
neither pinned by the flake nor integrated with the system (PATH, services,
Qt/QML import paths). Reach for Flatpak only when there is no viable nixpkgs
package - e.g. proprietary apps with no maintained derivation, or a package
whose build is so heavy it is impractical.

A Flatpak ID (e.g. `com.stremio.Stremio`) is a hint that the app *may* also
exist in nixpkgs - verify before defaulting to Flatpak, don't assume:

```
nix eval --impure --raw --expr \
  '(builtins.getFlake "/path/to/flake").inputs.nixpkgs.legacyPackages.x86_64-linux.<attr>.pname'
```

(`.pname` prints the name if it exists; a missing-attribute error means it is
not packaged.) Watch for **removed throwaway aliases**: an attr can exist as an
alias that `throw`s at build time (e.g. nixpkgs' `stremio` points to
`stremio-linux-shell`) - the error usually names the replacement.

## When to use

- You changed a NixOS config and need to see it actually boot/run in a VM.
- A VM boots to a black screen / wrong session / failed service and you must
  find out why.
- You want a disposable test machine that already has a working system.

Not for: validating syntax only (`nix flake check` / `nixos-rebuild build` are
cheaper and need no VM).

## Prerequisites

- terrarium works on this host - call its **`doctor`** tool first; if it reports
  `ok:false`, stop and report the failing check rather than working around it.
- **Either** a terrarium golden of a working install (see "Promote / re-fork"),
  **or** a VM created from a NixOS installer ISO (see "Bootstrapping SSH").
- VirtualBox VM settings are host-side; terrarium does not expose them. Inspect
  with `VBoxManage showvminfo <vm> --machinereadable`; set with the VM off:
  ```
  VBoxManage modifyvm <vm> --cpus 2 --memory 4096 \
    --graphicscontroller vmsvga --accelerate3d on --vram 128
  ```
  - **`vmsvga` + 3D + >=128MB VRAM** for any Wayland/GPU guest: the legacy
    `vboxvga` has no atomic modesetting, so compositors abort ("does not
    support atomic modesetting"). Headless/server configs can ignore this.
  - **2 vCPUs, not 4**: 4 vCPU threads starved on the host caused intermittent
    `systemd-udevd` RCU-stall deadlocks during boot.
  - If the guest has a compositor but no working GPU, force Mesa software
    rendering in the VM's hardware module:
    `environment.sessionVariables = { LIBGL_ALWAYS_SOFTWARE = "1"; GALLIUM_DRIVER = "llvmpipe"; };`
    (VM-only - real hardware uses its GPU).
  - **Detach the installer ISO after installing** (VM off):
    `VBoxManage storageattach <vm> --storagectl SATA --port 1 --device 0 --medium none`
    - an attached ISO can hang `udev` coldplug (`cdrom_id`).

## The iteration loop

1. **Fork a disposable test** (host repo mounted read-write):
   ```
   env_fork name=test1 golden=<golden> \
     share_host_path=<abs path to your repo> ttl_seconds=3600
   ```
   On an installed system `vboxsf` mounts the folder (at `/work`, or
   `/mnt/shared` via the automounter). `env_exec`/`env_push` work immediately
   (creds inherited from the golden). If the fork fails with "Shared folder
   named 'work' already exists", see "Promote / re-fork".
2. **Edit the config locally.**
3. **Get files onto the guest** - already live via the mount (skip to 4), or
   push the whole tree in one call:
   ```
   env_push name=test1 recursive=true local_path=<repo> guest_path=/root/cfg
   ```
   (`guest_path` uses forward slashes even from Windows.)
4. **Rebuild detached** - MCP calls time out ~60-90s but a KDE-sized build is
   longer, so background it and write a completion sentinel you can grep:
   ```
   env_exec name=test1 command=
     echo <password> | sudo -S bash -c 'export NIX_CONFIG="experimental-features = nix-command flakes"; \
     setsid bash -c "cd /root/cfg && nixos-rebuild switch --flake /root/cfg#<host> \
       > /root/rebuild.log 2>&1; echo REBUILD_EXIT=\$? >> /root/rebuild.log" \
       </dev/null >/dev/null 2>&1 & echo STARTED'
   ```
   (If using the mount, `cd /work && ... --flake /work#<host>`.)
   Do **not** chain `systemctl restart display-manager` here - see step 6.
5. **Poll** until the sentinel appears:
   ```
   env_exec name=test1 command='tail -5 /root/rebuild.log; grep -q REBUILD_EXIT /root/rebuild.log && echo FINISHED'
   ```
6. **Get a clean session**: `nixos-rebuild switch` activates the config but the
   running session is stale. Reboot for one clean session:
   `env_exec name=test1 command='echo <password> | sudo -S systemctl reboot'`.
   (Restarting `display-manager` in place leaves the old user session running
   and stacks sessions; only do it after killing that session - which also
   kills your own `env_exec` connection.)
7. **Look**: `env_screenshot name=test1` (re-screenshot once - the guest screen
   lags a keystroke).
8. Iterate. `env_revert name=test1` resets to the clean fork; `env_rm`/TTL
   tears it down.

## Iterating with Comin vs. `nixos-rebuild`

A machine may be managed by **Comin** (pull-mode GitOps: it fetches
`comin/deploy`, evaluates a per-target NixOS configuration, builds it and runs
`switch-to-configuration switch`) instead of being rebuilt by hand. Choose the
method by what you are trying to learn.

| Situation | Method | Why |
|---|---|---|
| Still designing the change; not sure it even evaluates | Edit locally, then rebuild in a **forked test VM** | Fastest loop; no commit needed; a failure costs a throwaway fork |
| Proving the **real GitOps path**: branch policy, persistence, what a device actually runs, Comin itself | Commit + push to `comin/deploy`; let Comin deploy | Only this exercises fetch → evaluate → build → switch and survives reboot |
| Already committed; you just want the deployed result | Comin, or `nixos-rebuild switch --flake ...#<host>` in a fork of the deployed system | |

Rule of thumb: use `nixos-rebuild` **while designing**, and switch to the Comin
path once the config is worth committing and the deployment pipeline itself is
what must be proven.

Factors to weigh:

- **Round-trip cost** - the rebuild loop is seconds-to-minutes in a fork; Comin
  polls (~60s) then evaluates/builds/switches, so a full deployment is minutes.
- **Commit hygiene** - `comin/deploy` is what every device follows, so only push
  what you want deployed; WIP stays off it. Never force-push or reset it behind
  a commit a device has already deployed (Comin rejects that).
- **Isolation** - a fork is disposable (`env_revert`/`env_rm`); a deploy target
  is not.
- **What you are testing** - if the question is "does this config work", use the
  rebuild loop; if it is "does the deployment pipeline work", use Comin.

Concrete Comin iteration: `env_fork` a golden whose Comin points at the branch
(or a full golden), push a commit (a scratch branch or a local remote gives a
fast poll), then watch `comin status` and `journalctl -u comin`, confirm the
generation with `readlink -f /run/current-system`, and reboot to verify
persistence. Concrete rebuild iteration is "The iteration loop" above: fork,
edit, `env_push`, backgrounded `nixos-rebuild switch` with a sentinel, then
`env_screenshot`.

## Bootstrapping SSH on a fresh installer-ISO env

A VM created from the NixOS ISO has empty passwords, so `env_exec`/`env_push`
fail ("no supported methods remain"). Enable SSH, then record creds:

1. `env_screenshot` to confirm you're at the live-ISO root shell, then
   `env_type` (short, ASCII-only, `press_enter=true`):
   ```
   echo 'root:<password>' | sudo chpasswd && \
   sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/; s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
   sudo systemctl restart sshd && echo SSH_READY
   ```
2. Record creds so `env_exec` works (the documented "adopt with what worked"
   flow; `take_snapshot=true` creates the base snapshot):
   ```
   golden_adopt vm=<vm-name> image=<golden> user=root password=<password> shell=posix take_snapshot=true
   ```
   `share_host_path` will NOT mount here (live ISO has no guest additions) -
   use `env_push` for the bootstrap.
3. Push the config: `env_push name=<env> recursive=true local_path=<repo> guest_path=/root/cfg`.
4. Partition + install (example: BIOS/MBR layout - match your hardware module):
   ```
   env_exec name=<env> command='
     parted /dev/sda -- mklabel msdos
     parted /dev/sda -- mkpart primary ext4 1MiB 100%
     mkfs.ext4 -q -L nixos /dev/sda1; partprobe /dev/sda; sleep 2
     mount /dev/disk/by-label/nixos /mnt
     export NIX_CONFIG="experimental-features = nix-command flakes"
     cd /root/cfg && nixos-install --flake .#<host> --root /mnt --no-root-passwd'
   ```
   Run long installs detached with a sentinel as in the loop step 4. The
   bootloader is configured by the hardware module (`boot.loader.*`).
5. Set the installed root password (root SSH is `prohibit-password` by
   default): `env_exec command='nixos-enter --root /mnt --command "echo root:<password> | chpasswd"'`.
6. Detach the ISO, reboot from disk, then re-adopt the golden with the normal
   user + password for iteration.

## Promote / re-fork

- `env_promote name=<working vm> image=<golden>` - full disk copy, takes
  minutes; the MCP call times out but **completes server-side**, so poll
  `env_list` for the new golden. It inherits the graphics/CPU config and the
  SSH creds.
- A golden promoted from a VM that had `share_host_path` set bakes a stale
  `work` shared-folder into its snapshot; a later `env_fork` with
  `share_host_path` then fails ("Shared folder named 'work' already exists").
  Either fork **without** `share_host_path` (the folder is already there), or
  clear it (VM off): `VBoxManage sharedfolder remove <golden-vm> --name work`.

## Diagnosing a failed boot or session

`env_exec` runs as the golden's SSH user, so user-level logs need no sudo (just
point at the runtime dir). Use SSH, not the console:

```
# system-wide + display manager
env_exec name=<env> command='echo <pw> | sudo -S journalctl -b -u display-manager --no-pager | tail -30'
env_exec name=<env> command='echo <pw> | sudo -S journalctl -b -p err --no-pager | tail -30'
env_exec name=<env> command='echo <pw> | sudo -S systemctl --failed --no-pager'
# the user's graphical session (runs as your ssh user)
env_exec name=<env> command='XDG_RUNTIME_DIR=/run/user/1000 journalctl --user -b --no-pager -o cat | tail -40'
# crashes
env_exec name=<env> command='echo <pw> | sudo -S coredumpctl list --no-pager | tail'
# what env the session actually got
env_exec name=<env> command='echo <pw> | sudo -S cat /proc/$(pgrep -f <session-binary> | head -1)/environ | tr "\0" "\n" | grep -E "<RELEVANT_VARS>"'
```

Method: read the first error of the failing unit, find the root cause, fix it in
the config, rebuild, reboot. Use the **`nixos`** skill for the option/module/
packaging side of the fix.

Generic NixOS-in-a-VM pitfalls:

| Symptom | Likely cause | Fix |
|---|---|---|
| session exits quickly with `127` (`<binary>: command not found`) | a binary the launcher execs is not on the session PATH; a package's dependencies are **not** symlinked into `/run/current-system/sw/bin` | declare the providing package explicitly in `environment.systemPackages` |
| session exits non-zero right after start, `Failed to create wl_display` | compositor not found or not started | ensure the compositor package is on the session PATH |
| compositor logs `does not support atomic modesetting` / `failed to create compositor backend` | VM graphics controller | set VMSVGA + 3D (legacy `vboxvga` has no atomic KMS) |
| Qt/GL app aborts during GL/EGL init in a VM | no working GPU | force Mesa software rendering in the VM's hardware module |
| boot stalls, `RCU` stalls at `systemd-udevd`, `systemd` blocked | vCPU starvation or an attached ISO | 2 vCPUs; detach the installer ISO; power-cycle |
| a service `times out` and blocks the session | it shells out to a binary/service that isn't present | read its journal, add the missing dependency in config |
| kernel says `module ... is not installed` (QML) | a runtime import path lacks a package not pulled in by the app's own deps | add the package and extend the app's import-path env var |

## Common mistakes

- Typing files with `env_type`/base64 instead of `env_push recursive=true`.
- Running a long `nixos-rebuild`/`nixos-install` in the foreground - the MCP
  timeout kills it mid-build. Always `setsid ... &` to a log with a
  `REBUILD_EXIT=$?` sentinel and poll for it.
- Trusting a single `env_screenshot` after a keystroke - the guest screen lags.
- "Fixing" the guest imperatively (hand-editing `/etc`, `nix-env`) so the
  result isn't reproducible. Every fix goes in the config, then rebuild.
- Chasing graphics/session failures as config bugs when they are VM settings
  (VMSVGA, 3D, vCPU count, software GL).
- `systemctl restart display-manager` without tearing down the old user session
  - overlapping sessions; reboot instead.
- Assuming config files persist across reboots of a live-ISO env - they don't
  (tmpfs); push them to the installed disk, or fork from a golden.

## Worked example (this repo)

The `plasma-bigscreen-vbox` golden and the Plasma Bigscreen/Wayland fixes are a
concrete instance of this workflow. The repo README's "Verified behaviour" and
"Known issues" sections carry the session-specific error → fix list (session
exit 127/4, `QKdeTheme` SIGSEGV, missing `kactivitymanagerd`, `kcminit`/`xrdb`
blocked by missing Xwayland, home-screen QML modules needing `QML2_IMPORT_PATH`,
and the VM-only remote-desktop dialog).
