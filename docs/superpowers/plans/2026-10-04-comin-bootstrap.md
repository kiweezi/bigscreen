# Comin Bootstrap Images and GitOps Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build minimal Raspberry Pi 4 and VirtualBox bootstrap images that install themselves from `comin/deploy` via Comin, publish tag-built ARM64 Pi images, and prove the whole path end-to-end in VirtualBox.

**Architecture:** Refactor the existing monolithic host config into composable NixOS modules (baseline, desktop profile, platform, image). Each managed machine pulls `bigscreen-<target>-deploy` from the deployment map; bootstrap images stay minimal, promotion is a Git commit on `comin/deploy`. A tag-triggered GitHub Actions workflow builds the Pi SD image on an ARM64 runner and attaches it to a release.

**Tech Stack:** Nix flakes, NixOS modules, `nixos-hardware`, `nlewo/comin`, `make-disk-image`/`sd-image-aarch64`/`virtualbox-image`, GitHub Actions, terrarium (VirtualBox MCP).

**Spec:** `docs/superpowers/specs/2026-10-04-comin-bootstrap-design.md`

## Global Constraints

- Deploy branch: `comin/deploy`. Remote: `https://github.com/kiweezi/bigscreen.git`.
- Comin selectors: `bigscreen-rpi4-deploy` and `bigscreen-vbox-deploy`; Comin must never select an image output.
- Comin `remotes.*.branches.testing.name = ""` to disable testing branches.
- Comin poller 60s; `evalTimeout` 1800s; `buildTimeout` 7200s; debug off; no firewall ports opened.
- Publisher runner label: `ubuntu-26.04-arm` (no unpinned Linux ARM label exists); verify `uname -m` is `aarch64`.
- Release trigger: `push.tags: ['v*']` then validate `v<major>.<minor>.<patch>`; artifact `bigscreen-rpi4-bootstrap-<tag>.img.zst` + `.sha256`.
- Repository public images contain no SSH, no keys, no Wi-Fi credentials, no tokens.
- State version `24.11` everywhere; Pi root label `NIXOS_SD`; VBox root label `nixos`, GRUB on `/dev/sda`.
- Commit messages: plain, factual, no AI watermarks/co-author/tool trailers; minimize commit count.
- Do not stage or modify `.gitignore` / `opencode.jsonc`.
- No tag, release, or physical Pi promotion in this session.
- Unless stated otherwise, every `nix`/`git` command runs inside the terrarium Linux builder env (`builder1`, Tasks 9–10), because the Windows host has no Nix. Repository edits are made locally and reach the guest through the shared `/work` mount.

## Review Focus

- Fresh boot runs the image's baked config only until Comin fetches; it must then converge to the current `comin/deploy` selection, even if that differs from build time.
- An invalid `comin/deploy` commit must fail evaluation/build without replacing the running system, and a later fix commit must resume deployment.
- After the VM's profile flips bootstrap→full, Comin must still be enabled and must keep polling so a second commit also deploys.
- The Pi deploy output must remain evaluable and minimal while the VM is promoted to full; the shared hostname must not cross-select targets.
- `switch` does not change the running kernel; a reboot must still yield the full profile and preserved Comin state.
- Canonical bootstrap images must reach a shell and network without test SSH; test keys are removed before finishing.

---

### Task 1: Split hosts into base, desktop profile, and platforms (preserve existing outputs)

**Files:**
- Create: `hosts/base.nix`
- Create: `hosts/profile-desktop.nix`
- Create: `hosts/platform-rpi4.nix`
- Create: `hosts/platform-vbox.nix`
- Modify: `hosts/common.nix`
- Modify: `hosts/hardware-rpi4.nix`
- Modify: `hosts/hardware-vbox.nix`

**Interfaces:**
- Produces: `hosts/base.nix` (users/networking/locale/packages; no desktop, no sshd), `hosts/profile-desktop.nix` (imports `modules/bigscreen.nix`, `modules/apps.nix`, `modules/theme.nix`), `hosts/platform-rpi4.nix` (runtime Pi boot/fs), `hosts/platform-vbox.nix` (runtime VBox boot/fs/guest/GL/binfmt).

- [ ] **Step 1: Create `hosts/base.nix`** from the non-desktop parts of `hosts/common.nix`: timezone `Europe/Oslo`, locale `en_US.UTF-8`, `services.xserver.xkb.layout = "us"`, `console.keyMap = "us"`, `networking.hostName = "bigscreen-tv"`, `networking.networkmanager.enable = true`, `nixpkgs.config.allowUnfree = true`, `users.mutableUsers = false`, `users.users.root.hashedPassword = ""`, the `htpc` user with groups `[ "wheel" "networkmanager" "video" "audio" "input" ]` and `hashedPassword = ""`, `security.sudo.wheelNeedsPassword = false`, `nix.settings.experimental-features = [ "nix-command" "flakes" ]`, `environment.systemPackages = with pkgs; [ vim git htop ]`, `documentation.nixos.enable = false`, `documentation.man.enable = false`, `system.stateVersion = "24.11"`. Do **not** include `imports` of desktop modules and do **not** enable `services.openssh`.

- [ ] **Step 2: Create `hosts/profile-desktop.nix`** with `imports = [ ../modules/bigscreen.nix ../modules/apps.nix ../modules/theme.nix ];`.

- [ ] **Step 3: Rewrite `hosts/common.nix`** to `{ imports = [ ./base.nix ./profile-desktop.nix ]; }`.

- [ ] **Step 4: Create `hosts/platform-rpi4.nix`** with the runtime parts of `hosts/hardware-rpi4.nix` (everything except the `sd-image-aarch64` import): `boot.loader.grub.enable = false`, `boot.loader.generic-extlinux-compatible.enable = true`, `boot.loader.efi.canTouchEfiVariables = lib.mkForce false`, `boot.kernelPackages = pkgs.linuxPackages_rpi4`, `boot.initrd.allowMissingModules = true`, `fileSystems."/" = { device = "/dev/disk/by-label/NIXOS_SD"; fsType = "ext4"; options = [ "noatime" ]; }`, `zramSwap.enable = true`, `networking.wireless.enable = lib.mkDefault false`, `hardware.graphics.enable = true`, `boot.kernelParams = [ "cma=256M" ]`, `nixpkgs.hostPlatform = "aarch64-linux"`, `system.stateVersion = "24.11"`.

- [ ] **Step 5: Create `hosts/platform-vbox.nix`** with the runtime parts of `hosts/hardware-vbox.nix` using `lib.mkDefault` for boot/fs so the image module can override: `virtualisation.virtualbox.guest.enable = true`, `boot.loader.grub.enable = true`, `boot.loader.grub.device = "/dev/sda"`, `boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "sd_mod" "sr_mod" ]`, `fileSystems."/" = { device = lib.mkDefault "/dev/disk/by-label/nixos"; fsType = "ext4"; }`, `hardware.graphics.enable = true`, `environment.sessionVariables = { LIBGL_ALWAYS_SOFTWARE = "1"; GALLIUM_DRIVER = "llvmpipe"; }`, `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`, `nixpkgs.hostPlatform = "x86_64-linux"`, `system.stateVersion = "24.11"`.

- [ ] **Step 6: Rewrite the old hardware files as imports** so old outputs keep working: `hosts/hardware-rpi4.nix` becomes `{ modulesPath, ... }: { imports = [ ./platform-rpi4.nix (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ]; }`; `hosts/hardware-vbox.nix` becomes `{ imports = [ ./platform-vbox.nix ]; }`.

- [ ] **Step 7: Verify all original outputs still evaluate**

Run: `nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox.config.system.build.toplevel.drvPath`
Expected: a `/nix/store/...drv` path, no conflict/undefined-option errors.
Run the same for `bigscreen-rpi4` and `bigscreen-iso`.
Expected: success for each.

- [ ] **Step 8: Commit**

```bash
git add hosts/
git commit -m "Split hosts into base, desktop profile, and platform modules"
```

---

### Task 2: Add Comin input, deployment metadata options, and Comin module

**Files:**
- Modify: `flake.nix`
- Create: `modules/meta.nix`
- Create: `hosts/comin.nix`

**Interfaces:**
- Produces: flake input `comin`; meta options `bigscreen.target` (`"rpi4"|"vbox"`) and `bigscreen.profile` (`"bootstrap"|"full"`); `hosts/comin.nix` sets `services.comin.*` and `services.comin.hostname = "bigscreen-${config.bigscreen.target}-deploy"`.

- [ ] **Step 1: Add the flake input**

In `flake.nix` `inputs`: add
```nix
comin = {
  url = "github:nlewo/comin";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

- [ ] **Step 2: Create `modules/meta.nix`**

Options `bigscreen.target = lib.mkOption { type = lib.types.enum [ "rpi4" "vbox" ]; }`, `bigscreen.profile = lib.mkOption { type = lib.types.enum [ "bootstrap" "full" ]; }` (both required, no default), and `bigscreen.allowTestSsh = lib.mkOption { type = lib.types.bool; default = false; }`. Add assertions: `bigscreen.profile == "bootstrap" && !config.bigscreen.allowTestSsh -> !config.services.openssh.enable`; and `config.services.comin.enable -> config.services.comin.hostname == "bigscreen-${config.bigscreen.target}-deploy"`. All four managed outputs set `bigscreen.target`/`bigscreen.profile`; the option lives here (not in the temporary module) so it exists for every target.

- [ ] **Step 3: Create `hosts/comin.nix`**

Signature `{ config, pkgs, comin, ... }`. Content:
```nix
{
  services.comin = {
    enable = true;
    package = comin.packages.${pkgs.stdenv.hostPlatform.system}.default;
    hostname = "bigscreen-${config.bigscreen.target}-deploy";
    remotes = [{
      name = "origin";
      url = "https://github.com/kiweezi/bigscreen.git";
      branches.main.name = "comin/deploy";
      branches.testing.name = "";
      poller.period = 60;
    }];
    evalTimeout = 1800;
    buildTimeout = 7200;
    debug = false;
  };
}
```

- [ ] **Step 4: Write the failing check for the branch policy**

Run: `nix eval --no-write-lock-file --json .#nixosConfigurations.bigscreen-vbox-bootstrap.config.services.comin.remotes`
Expected: FAIL currently (`bigscreen-vbox-bootstrap` output does not exist yet).

- [ ] **Step 5: Defer verification to Task 3**

Do not add the new outputs here; this task only establishes the modules and input. Note in the commit body that outputs land in Task 3.

- [ ] **Step 6: Commit**

```bash
git add flake.nix modules/meta.nix hosts/comin.nix
git commit -m "Add comin input and shared Comin deployment module"
```

---

### Task 3: Add deployment selection and the four managed outputs

**Files:**
- Create: `hosts/deployment-selection.nix`
- Create: `hosts/profile-bootstrap.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: `hosts/base.nix`, `hosts/profile-desktop.nix`, `hosts/comin.nix`, `modules/meta.nix`, `hosts/platform-*.nix`.
- Produces: `bigscreen-rpi4-bootstrap`, `bigscreen-rpi4-deploy`, `bigscreen-vbox-bootstrap`, `bigscreen-vbox-deploy`.

- [ ] **Step 1: Create `hosts/deployment-selection.nix`**

```nix
{
  rpi4 = "bootstrap";
  vbox = "bootstrap";
}
```
Values must be `"bootstrap"` or `"full"`; this file is the only place promotion is expressed.

- [ ] **Step 2: Create `hosts/profile-bootstrap.nix`** as `{ ... }: { }` (minimal; exists so the selector has two symmetric branches).

- [ ] **Step 3: Rewrite `flake.nix` outputs**

Add args `comin`. Define `profiles = import ./hosts/deployment-selection.nix;`. Define a builder:
```nix
mkManaged = { target, system, platform, extraModules ? [ ] }:
  let profile = profiles.${target}; in
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit comin; };
    modules = [
      comin.nixosModules.comin
      ./hosts/base.nix
      platform
      ./hosts/comin.nix
      ./modules/meta.nix
      (if profile == "full" then ./hosts/profile-desktop.nix else ./hosts/profile-bootstrap.nix)
      { bigscreen.target = target; bigscreen.profile = profile; }
    ] ++ extraModules;
  };
```
Add outputs:
```nix
bigscreen-rpi4-bootstrap = mkManaged { target = "rpi4"; system = "aarch64-linux"; platform = ./hosts/platform-rpi4.nix; extraModules = [ nixos-hardware.nixosModules.raspberry-pi-4 ./hosts/image-rpi4.nix ]; };
bigscreen-rpi4-deploy    = mkManaged { target = "rpi4"; system = "aarch64-linux"; platform = ./hosts/platform-rpi4.nix; extraModules = [ nixos-hardware.nixosModules.raspberry-pi-4 ]; };
bigscreen-vbox-bootstrap = mkManaged { target = "vbox"; system = "x86_64-linux"; platform = ./hosts/platform-vbox.nix; extraModules = [ ./hosts/image-vbox.nix ./hosts/ci-vm-access.nix ]; };
bigscreen-vbox-deploy    = mkManaged { target = "vbox"; system = "x86_64-linux"; platform = ./hosts/platform-vbox.nix; extraModules = [ ./hosts/ci-vm-access.nix ]; };
```
Keep the existing `bigscreen-rpi4`, `bigscreen-vbox`, `bigscreen-iso` outputs untouched. `hosts/image-rpi4.nix`, `hosts/image-vbox.nix`, `hosts/ci-vm-access.nix` are created here as empty stubs `{ ... }: { }` and filled in Tasks 4–5, so every output evaluates from this task onward.

- [ ] **Step 4: Verify minimal outputs evaluate and selectors are correct**

Run:
```
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-rpi4-deploy.config.services.comin.hostname
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox-deploy.config.services.comin.hostname
nix eval --no-write-lock-file --json .#nixosConfigurations.bigscreen-vbox-bootstrap.config.services.comin.remotes
```
Expected: `bigscreen-rpi4-deploy`, `bigscreen-vbox-deploy`, and JSON with `"branches":{"main":{"name":"comin/deploy"...},"testing":{"name":""...}}`.

- [ ] **Step 5: Verify bootstrap minimality assertion**

Run: `nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox-bootstrap.config.services.openssh.enable`
Expected: `false` without test access enabled; if the meta assertion fires it is a bug (test access must set `bigscreen.allowTestSsh`).

- [ ] **Step 6: Commit**

```bash
git add flake.nix hosts/deployment-selection.nix hosts/profile-bootstrap.nix hosts/image-rpi4.nix hosts/image-vbox.nix hosts/ci-vm-access.nix
git commit -m "Add deployment selection and bootstrap/deploy outputs"
```

---

### Task 4: Pi SD image output

**Files:**
- Modify: `hosts/image-rpi4.nix`

**Interfaces:**
- Produces: `bigscreen-rpi4-bootstrap.config.system.build.sdImage` (`.img.zst`).

- [ ] **Step 1: Implement `hosts/image-rpi4.nix`**

`{ modulesPath, ... }: { imports = [ (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") ]; }`. Rely on `hosts/platform-rpi4.nix` for boot/fs; do not duplicate them.

- [ ] **Step 2: Verify the SD image derivation evaluates**

Run: `nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-rpi4-bootstrap.config.system.build.sdImage.drvPath`
Expected: a `/nix/store/...drv` path.

- [ ] **Step 3: Verify the deploy output has no SD builder**

Run: `nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-rpi4-deploy.config.system.build.sdImage.drvPath`
Expected: fails with "attribute 'sdImage' missing" (confirms deploy is not an image).

- [ ] **Step 4: Commit**

```bash
git add hosts/image-rpi4.nix
git commit -m "Build Pi bootstrap SD image from platform module"
```

---

### Task 5: VirtualBox bootstrap OVA and temporary test access

**Files:**
- Modify: `hosts/image-vbox.nix`
- Modify: `hosts/ci-vm-access.nix`

**Interfaces:**
- Produces: `bigscreen-vbox-bootstrap.config.system.build.virtualBoxOVA`; `bigscreen.allowTestSsh` granted by `ci-vm-access.nix`.

- [ ] **Step 1: Implement `hosts/image-vbox.nix`**

`{ modulesPath, ... }: { imports = [ (modulesPath + "/virtualisation/virtualbox-image.nix") ]; virtualisation.diskSize = 32768; virtualbox.memorySize = 4096; virtualbox.params = { cpus = 2; vram = 128; graphicscontroller = "vmsvga"; accelerate3d = "on"; }; }`. The image module supplies `fileSystems`, GRUB, swap, and Guest Additions; `hosts/platform-vbox.nix` supplies the rest at `mkDefault`.

- [ ] **Step 2: Implement `hosts/ci-vm-access.nix`** (temporary; deleted in Task 10)

Signature `{ lib, ... }`. Content sets `bigscreen.allowTestSsh = true;` (the option itself is defined in `modules/meta.nix`), `services.openssh = { enable = true; settings.PermitRootLogin = "no"; };`, and `users.users.htpc.openssh.authorizedKeys.keyFiles = [ ./ci-vm-access.pub ];`. Add a header comment: `# TEMPORARY VM-test access. Removed in the final VM-test commit. Not part of the Pi outputs.`

- [ ] **Step 3: Create the test keypair (public key committed, private key outside the repo)**

Run:
```
ssh-keygen -t ed25519 -N "" -C "ci-vm-access" -f <TEMP>/ci-vm-access
Copy-Item <TEMP>/ci-vm-access.pub D:\repos\bigscreen\hosts\ci-vm-access.pub
```
Expected: `hosts/ci-vm-access.pub` exists; the private key stays in the temp dir.

- [ ] **Step 4: Verify the OVA derivation evaluates and minimality holds under test access**

Run:
```
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox-bootstrap.config.system.build.virtualBoxOVA.drvPath
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox-bootstrap.config.virtualisation.diskSize
```
Expected: a `/nix/store/...drv` path and `32768`.

- [ ] **Step 5: Commit**

```bash
git add hosts/image-vbox.nix hosts/ci-vm-access.nix hosts/ci-vm-access.pub
git commit -m "Build VirtualBox bootstrap OVA and add temporary VM test access"
```

---

### Task 6: Flake checks for deployment invariants

**Files:**
- Create: `modules/invariants.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: evaluated configs from Task 3.
- Produces: `checks.x86_64-linux.<name>` derivations that fail the build when an invariant is broken.

- [ ] **Step 1: Add assertions to `modules/meta.nix`** (extend Task 2 file)

Add assertions: bootstrap profile implies `!config.services.displayManager.enable`; bootstrap profile implies `!(config.services.xserver.enable or false)` and that `pkgs.plasma-bigscreen` is not in `environment.systemPackages`; every managed config has `services.comin.enable` (unless it is an image-only output — all four managed outputs have it).

- [ ] **Step 2: Implement `modules/invariants.nix`** as evaluated booleans

Provide `{ lib, config, ... }` exporting no options; instead expose the checks from `flake.nix`. In `flake.nix` add a `checks` output:
```nix
checks = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system:
  let pkgs = nixpkgs.legacyPackages.${system}; in {
    rpi4-deploy-comin = pkgs.runCommand "check-rpi4-deploy-comin" { } ''
      grep -q 'bigscreen-rpi4-deploy' ${self.nixosConfigurations.bigscreen-rpi4-deploy.config.services.comin.hostname}
      touch $out
    '';
    vbox-bootstrap-minimal = pkgs.runCommand "check-vbox-bootstrap-minimal" { } ''
      grep -q 'bigscreen-vbox-deploy' ${self.nixosConfigurations.bigscreen-vbox-bootstrap.config.services.comin.hostname}
      touch $out
    '';
  });
```

- [ ] **Step 3: Run the checks**

Run: `nix flake check --all-systems --no-write-lock-file --no-build`
Expected: evaluation succeeds; assertions in `modules/meta.nix` fire on any violation.

- [ ] **Step 4: Prove a check fails when its invariant is broken**

Temporarily set `hosts/deployment-selection.nix` `rpi4 = "full"` and confirm the `rpi4-deploy-comin`/minimality assertion fails; then revert to `bootstrap`. Do not commit the temporary change.

- [ ] **Step 5: Commit**

```bash
git add modules/meta.nix modules/invariants.nix flake.nix
git commit -m "Add flake checks for deployment and profile invariants"
```

---

### Task 7: Tag-triggered ARM64 release workflow

**Files:**
- Create: `.github/workflows/release-rpi4-bootstrap.yml`

**Interfaces:**
- Produces: a release for a pushed `v*` tag containing the SD image and checksum.

- [ ] **Step 1: Write the workflow**

```yaml
name: release-rpi4-bootstrap
on:
  push:
    tags: ['v*']
permissions:
  contents: read
jobs:
  guard:
    runs-on: ubuntu-26.04-arm
    outputs:
      version: ${{ steps.semver.outputs.version }}
    steps:
      - name: Verify ARM64 runner
        run: test "$(uname -m)" = aarch64
      - id: semver
        name: Validate semantic version tag
        run: |
          v="${GITHUB_REF_NAME}"
          if ! printf '%s' "$v" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "tag $v is not v<major>.<minor>.<patch>" >&2; exit 1
          fi
          echo "version=$v" >> "$GITHUB_OUTPUT"
  build:
    needs: guard
    runs-on: ubuntu-26.04-arm
    steps:
      - uses: actions/checkout@<PINNED_SHA> # v4
        with:
          persist-credentials: false
      - uses: cachix/install-nix-action@<PINNED_SHA> # installs Nix with flakes
      - name: Build bootstrap SD image
        run: nix build --no-write-lock-file .#nixosConfigurations.bigscreen-rpi4-bootstrap.config.system.build.sdImage
      - name: Stage artifact
        run: |
          img="$(ls result/sd-image/*.img.zst)"
          name="bigscreen-rpi4-bootstrap-${{ needs.guard.outputs.version }}.img.zst"
          cp "$img" "$name"
          sha256sum "$name" > "$name.sha256"
      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "${{ github.ref_name }}" "bigscreen-rpi4-bootstrap-${{ needs.guard.outputs.version }}.img.zst" "bigscreen-rpi4-bootstrap-${{ needs.guard.outputs.version }}.img.zst.sha256" --title "${{ github.ref_name }}" --notes "Bootstrap-only Raspberry Pi 4 image. Runtime config comes from comin/deploy."
```
`build` needs `permissions: { contents: write }` on the job. Replace `<PINNED_SHA>` with the current release SHA of `actions/checkout` (v4) and `cachix/install-nix-action` (v27+); record the versions in the commit message.

- [ ] **Step 2: Lint the workflow**

Run: `actionlint .github/workflows/release-rpi4-bootstrap.yml` (or `npx --yes actionlint` if unavailable locally).
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-rpi4-bootstrap.yml
git commit -m "Add ARM64 tag-triggered bootstrap image release workflow"
```

---

### Task 8: README documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a bootstrap/GitOps section** documenting: how to build `bigscreen-rpi4-bootstrap` locally, how tag releases are produced and where the `.img.zst`/`.sha256` live, decompress + flash steps, Ethernet DHCP first boot, console-only recovery, deployment-map promotion edits, `journalctl -u comin` and `/var/lib/comin`, forward-revert recovery, when a manual reboot is needed, and that a fresh flash converges to the current `comin/deploy` selection. Note the trust boundary (write access to `comin/deploy` administers machines).

- [ ] **Step 2: Verify links and heading rendering**

Run: `git diff --check`
Expected: no whitespace errors.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document Comin bootstrap images and GitOps workflow"
```

---

### Task 9: Build the VirtualBox appliance and run the end-to-end test

**Files:** none in the repo (guest-side operations).

**Interfaces:**
- Consumes: committed implementation from Tasks 1–8.
- Produces: a new golden `bigscreen-vbox-bootstrap`; evidence logs and screenshots.

- [ ] **Step 1: Fork a Linux builder** from golden `plasma-bigscreen-vbox-theme2` with the repo mounted (`env_fork name=builder1 golden=plasma-bigscreen-vbox-theme2 share_host_path=D:\repos\bigscreen ttl_seconds=14400`). Confirm `env_exec` works and `nix --version` is present.

- [ ] **Step 2: Check resources in the builder**

Run: `env_exec name=builder1 command='df -h / /nix; free -h; nproc'`
Expected: enough free space for the desktop closure; if not, grow the disk or reduce scope and report.

- [ ] **Step 3: Build the bootstrap OVA on the builder** (detached with a sentinel, per the iterating-nixos-in-vbox skill)

Run: `nix build --no-write-lock-file .#nixosConfigurations.bigscreen-vbox-bootstrap.config.system.build.virtualBoxOVA` in the mounted repo, backgrounded to `/root/ova.log` with `OVA_EXIT=$?`. Poll until the sentinel appears.
Expected: `OVA_EXIT=0` and an OVA under `result/`.
Fallback if VBoxManage export fails inside the guest: build a raw disk image instead and convert on the host (`env_pull` the `.img`, then `VBoxManage convertfromraw` on Windows).

- [ ] **Step 4: Pull the artifact to the host**

Run: `env_pull name=builder1 guest_path=/work/result/<ova-name> local_path=C:\Users\rhysm\AppData\Local\Temp\opencode\bigscreen-bootstrap.ova` (recursive if needed).
Expected: file exists on host.

- [ ] **Step 5: Register and adopt a bootstrap golden**

Import on the host, then record it:
```
VBoxManage import <ova> --vsys 0 --vmname trr-golden-bigscreen-vbox-bootstrap
```
then `golden_adopt vm=trr-golden-bigscreen-vbox-bootstrap image=bigscreen-vbox-bootstrap user=htpc key=<TEMP>/ci-vm-access take_snapshot=true shell=posix`.
Expected: `env_list` shows the golden with `ssh_user` `htpc`.

- [ ] **Step 6: Fork a disposable test env** `vmtest1` (no shared folder; 2 vCPU, 4096 MB) and verify minimal bootstrap

Run:
```
env_exec name=vmtest1 command='systemctl is-active comin; systemctl is-enabled display-manager 2>/dev/null; pgrep -a kwin_wayland; nix --version; ip -4 addr show | grep inet'
```
Expected: `comin` active; `display-manager` not found/inactive; no `kwin_wayland`; nix present; a DHCP address.
`env_screenshot name=vmtest1` — expected: console/agetty, no graphical session.

- [ ] **Step 7: Verify Comin reaches GitHub and selects the branch**

Run: `env_exec name=vmtest1 command='cat /var/lib/comin/comin.yaml; journalctl -u comin -n 40 --no-pager'`
Expected: remote URL, `main.name: comin/deploy`, `testing.name: ''`, fetch success (no auth error).

- [ ] **Step 8: Network interruption recovery**

Run: `env_exec name=vmtest1 command='sudo ip link set <iface> down; sleep 90; sudo ip link set <iface> up'`, then poll `journalctl -u comin` for a successful fetch.
Expected: fetch resumes without reflash/rebuild.

- [ ] **Step 9: Publish implementation and create the deployment branch**

Run: `git status --short` (expect only `docs/`, `.gitignore`, `opencode.jsonc`; do not stage the latter two). Then push the implementation commits to `main`:
```
git push origin HEAD:main
git push origin HEAD:comin/deploy
```
Expected: `main` and `comin/deploy` both point at the implementation HEAD with `deployment-selection.nix` still `{ rpi4 = "bootstrap"; vbox = "bootstrap"; }`.

- [ ] **Step 10: Confirm the test env still runs the bootstrap selection**

Run: `env_exec name=vmtest1 command='systemctl show -p ExecMainStartTimestamp comin; journalctl -u comin -n 20 --no-pager | grep -i deploy'`
Expected: Comin reports the selected commit from `comin/deploy` with no deployment errors (bootstrap == running config, so no switch).

- [ ] **Step 11: Push the VM promotion commit**

Edit `hosts/deployment-selection.nix` so `vbox = "full";` (leave `rpi4 = "bootstrap"`). Commit and push only that file:
```
git add hosts/deployment-selection.nix
git commit -m "Select full Bigscreen profile for the VirtualBox target"
git push origin HEAD:comin/deploy
git rev-parse HEAD
```
Expected: a recorded promotion SHA. Do not push another commit until Step 12 completes.

- [ ] **Step 12: Observe Comin evaluate, build, and switch to the promotion SHA**

Poll: `env_exec name=vmtest1 command='comin status --oneline 2>/dev/null; journalctl -u comin -n 40 --no-pager'`. Build is long; poll up to the build timeout.
Expected: selected commit equals the promotion SHA; build succeeds; deployment status `done`.
Then: `env_exec name=vmtest1 command='readlink -f /run/current-system; systemctl is-active comin'`
Expected: `current-system` is the built full generation; Comin still active.

- [ ] **Step 13: Verify the desktop is running and Pi stayed minimal**

Run:
```
env_exec name=vmtest1 command='systemctl is-active display-manager; pgrep -a kwin_wayland | head; systemctl is-active sddm'
env_screenshot name=vmtest1
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-rpi4-deploy.config.bigscreen.profile
```
Expected: display manager active, a Wayland session, Bigscreen home screen; and `rpi4-deploy` profile still `bootstrap`.

- [ ] **Step 14: Reboot and confirm persistence**

Run: `env_exec name=vmtest1 command='sudo systemctl reboot'`; wait for SSH; re-check:
```
env_exec name=vmtest1 command='readlink -f /run/current-system; systemctl is-active comin; systemctl is-active sddm; cat /var/lib/comin/state.json | head -c 400'
env_screenshot name=vmtest1
```
Expected: full generation still current, Comin active with preserved state, session returns.

- [ ] **Step 15: Marker commit and verify the second deployment**

Add to `hosts/ci-vm-access.nix`: `environment.etc."bigscreen-vm-marker".text = "marker-2";`. Commit `Add VM test marker` and push to `comin/deploy`; record the SHA.
Run: `env_exec name=vmtest1 command='cat /etc/bigscreen-vm-marker; journalctl -u comin -n 30 --no-pager'`
Expected: `marker-2` present and the marker SHA deployed.

- [ ] **Step 16: Invalid commit fails safely**

Add to `hosts/ci-vm-access.nix`: `environment.systemPackages = [ pkgs.this-package-does-not-exist-xyz ];` (add `pkgs` to the signature). Commit `Exercise deployment failure handling` and push; record the SHA.
Run: `env_exec name=vmtest1 command='readlink -f /run/current-system; journalctl -u comin -n 40 --no-pager | grep -iE "error|fail"'`
Expected: evaluation fails (error recorded), `current-system` unchanged (still marker-2 generation), system responsive.

- [ ] **Step 17: Recover and remove test access in one commit**

Remove the marker line and the invalid package line from `hosts/ci-vm-access.nix`, keeping test access for now so the automation channel stays available. Commit `Revert VM test failure and marker` and push; record the SHA.
Run:
```
env_exec name=vmtest1 command='readlink -f /run/current-system; test -e /etc/bigscreen-vm-marker && echo MARKER_PRESENT || echo MARKER_GONE'
```
Expected: a new generation is deployed, marker gone, system healthy.

- [ ] **Step 18: Final deploy-branch state check**

Run: `git log --oneline origin/comin/deploy -5`
Expected: exactly the intended deploy commits (promotion, marker, failure, recovery), each a descendant of the previous; no force-push.

---

### Task 10: Canonical bootstrap rebuild, cleanup, and final verification

**Files:**
- Delete: `hosts/ci-vm-access.nix`, `hosts/ci-vm-access.pub`
- Modify: `flake.nix` (drop `./hosts/ci-vm-access.nix` from the two vbox `extraModules`)

**Interfaces:**
- Produces: canonical (no test SSH) `bigscreen-vbox-bootstrap`; destroyed disposable environments.

- [ ] **Step 1: Remove the temporary module from the flake and delete the files**

Edit `flake.nix` so both vbox outputs have `extraModules` without `./hosts/ci-vm-access.nix`; delete `hosts/ci-vm-access.nix` and `hosts/ci-vm-access.pub`. Commit `Remove temporary VM test access` and push to `main` and `comin/deploy` (skip `comin/deploy` if it would be rejected as a non-ancestor; then use `main` only and note the divergence).

- [ ] **Step 2: Re-evaluate canonical outputs**

Run:
```
nix eval --no-write-lock-file --raw .#nixosConfigurations.bigscreen-vbox-bootstrap.config.services.openssh.enable
nix flake check --all-systems --no-write-lock-file --no-build
```
Expected: `false` and clean evaluation.

- [ ] **Step 3: Rebuild and verify the canonical appliance (no test SSH)**

Rebuild the OVA on `builder1` from the updated working tree (sentinel as before), re-import as `trr-golden-bigscreen-vbox-bootstrap`, re-adopt with no credentials, fork `vmcanon1`, and verify via `env_screenshot` (console only) that it boots, runs `comin` (`systemctl is-active comin` via a console command typed at the login shell), and exposes no SSH.
Expected: canonical appliance verified without test SSH; record the screenshot.

- [ ] **Step 4: Tear down disposable environments**

Run `env_rm` for `vmtest1`, `vmcanon1`, and `builder1`; `env_gc`. Leave the user's `plasma-bigscreen-vbox-theme2` untouched. Report any retained golden (`bigscreen-vbox-bootstrap`) explicitly.

- [ ] **Step 5: Final report**

Summarize: implementation commit(s) on `main`; deploy-branch commit SHAs and the final deployed SHA; test evidence (logs/screenshots); canonical verification; unexecuted items (tag/release, physical Pi boot); and the exact next user action (create a `v*` tag to publish, flash the Pi, wire Ethernet).

---

### Task 11: Document the Comin lifecycle (bootstrap → tag → deploy branch → device pull)

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: verified behavior from Tasks 9–10.
- Produces: a written explanation of how a device is provisioned and updated.

- [ ] **Step 1: Add a "How GitOps updates work" section** with a diagram (mermaid in a fenced block) showing: flash a minimal bootstrap image → device boots with Comin pulling `comin/deploy` → a push to `comin/deploy` is pulled, evaluated, built, and switched → publishing a semantic-version tag runs the ARM workflow and produces a **new bootstrap image release** for provisioning additional devices.

- [ ] **Step 2: State the branch roles and the tag relationship explicitly**: `main` is integration; `comin/deploy` is what devices follow; `v*` tags produce bootstrap images only. Add a clearly labelled "planned future step" note that automating a tag → `comin/deploy` update is not implemented, and describe what it would change.

- [ ] **Step 3: Restate the trust boundary** (write access to `comin/deploy` administers the fleet) and forward-revert recovery.

- [ ] **Step 4: Verify and commit**

Run: `git diff --check`
Expected: no whitespace errors.
```bash
git add README.md
git commit -m "Document the Comin bootstrap and update lifecycle"
```

---

### Task 12: Add a Comin-vs-rebuild decision guide to the `iterating-nixos-in-vbox` skill

**Files:**
- Modify: `.opencode/skills/iterating-nixos-in-vbox/SKILL.md`

**Interfaces:**
- Consumes: the verified Comin workflow and its cost profile from Tasks 9–10.
- Produces: guidance letting an agent choose the cheaper correct iteration method.

- [ ] **Step 1: Load the `writing-skills` skill** and follow it for this edit.

- [ ] **Step 2: Add an "Iterating with Comin vs. `nixos-rebuild`" section** containing a decision guide. Cover the factors: speed/round-trip cost; whether the change under test is still being written; whether the goal is to validate the real GitOps path (branch policy, persistence, comin itself); commit hygiene (comin needs committed pushes; `nixos-rebuild` does not); availability of a running Comin device vs a fresh fork. Give a short rule of thumb: use direct `nixos-rebuild` while designing locally, and switch to the Comin path once the config is worth committing and the GitOps behavior itself is what must be proven. Include concrete commands for the Comin path (fork a bootstrap golden, push a commit to a scratch branch or local remote, `comin status`, reboot check) and for the rebuild path (backgrounded `nixos-rebuild switch` with a sentinel).

- [ ] **Step 3: Verify per `writing-skills`** (the skill must parse, references exist, and the guidance is decision-complete without contradicting the rest of the file). Commit

```bash
git add .opencode/skills/iterating-nixos-in-vbox/SKILL.md
git commit -m "Add Comin-vs-rebuild iteration guide to the VirtualBox skill"
```

---

## Self-Review Notes

- **Spec coverage:** configuration boundaries (Tasks 1–5), Comin behavior (Tasks 2–3), deployment lifecycle/failure (Tasks 9–10), tag release (Task 7), verification (Tasks 6, 9–10), documentation (Task 8). No spec section is unaddressed.
- **Type/name consistency:** `bigscreen.target`, `bigscreen.profile`, `bigscreen.allowTestSsh`, `bigscreen-<target>-deploy`, and the four output names are used identically across tasks.
- **Review Focus mapping:** fresh-boot convergence (Task 9 Step 10), invalid commit safety (Step 16), retained Comin after promotion (Steps 12–15), Pi stays minimal during promotion (Step 13), reboot after switch (Step 14), canonical no-SSH (Task 10 Step 3).
- **Open execution risks:** OVA export inside a VirtualBox guest (fallback: raw image + host `convertfromraw`); ARM runner disk capacity for the Pi kernel (observed only when a tag is later pushed); first full deployment build duration (bumped `buildTimeout`).
