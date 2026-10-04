# Comin bootstrap images and GitOps deployment

Date: 2026-10-04
Status: Draft for user review; implementation has not started.

## Intent and agreed scope

Build a minimal Raspberry Pi 4 bootstrap image rather than distributing the full Bigscreen desktop in every image. The Pi obtains its actual configuration from the public `https://github.com/kiweezi/bigscreen` repository through Comin, following `comin/deploy`. Bootstrap image releases are built natively on GitHub-hosted ARM64 runners when a tag is pushed. A fresh VirtualBox bootstrap appliance exercises the same configuration transition before the Pi is promoted.

User-confirmed decisions:

- Bootstrap networking is wired Ethernet with DHCP.
- Public bootstrap images provide local console recovery, not provisioned SSH access.
- Bootstrap images and deployment configurations share hardware and Comin modules.
- Pi and VirtualBox promotion are independent. The Pi remains minimal throughout the VM test.
- Scoped implementation commits and VM-test pushes to `main` and `comin/deploy` are authorized. Fewer commits are preferred. Commit messages must not include AI watermarks or attribution trailers.
- Creating a tag, publishing an actual release, or promoting the real Pi is not authorized in this session.
- This specification and a subsequent implementation plan may be added under `docs/superpowers/`; each is reviewed before the next stage.

Success means a minimal image can boot, discover the designated branch, activate the intended full configuration without manual rebuilding, persist that configuration across reboot, and accept a second Git commit without losing Comin.

## Current configuration and constraints

The flake currently exposes full `bigscreen-rpi4`, `bigscreen-vbox`, and `bigscreen-iso` systems. `hosts/common.nix` mixes desktop imports with baseline users, networking, and tools. `hosts/hardware-rpi4.nix` also imports the SD-image builder; `hosts/hardware-vbox.nix` describes an installed BIOS/MBR system but does not generate an appliance. No CI, Comin configuration, or custom flake checks exist.

All current systems use hostname `bigscreen-tv`; Comin therefore needs an explicit configuration selector rather than its hostname default. Pi storage uses `NIXOS_SD`; VirtualBox storage uses an ext4 partition labelled `nixos` and GRUB on `/dev/sda`. Deployment must preserve those layouts and `system.stateVersion = "24.11"`.

The local `.gitignore` and `opencode.jsonc` contain unrelated user changes and must not be staged, overwritten, or included in test publication. Windows has no native Nix tools on PATH. The existing terrarium golden can supply an isolated x86_64 Linux builder, but is not itself evidence that a new bootstrap appliance works.

## Alternatives and selected approach

1. **Selected: minimal installed bootstrap images plus Git-selected profiles.** Share platform and Comin definitions, keep desktop software separate, and use explicit deployment selectors. Image releases stay independent of routine application deployment.
2. **Full-config images on every release.** Simpler one-stage boot but retains large image closures and couples desktop changes to image production.
3. **Live ISO bootstrap for VirtualBox.** Easy to boot but does not prove persistent activation; rejected as the end-to-end test target. The existing full live ISO remains available for its current purpose.

The task is a focused deployment subsystem change, not a redesign of Bigscreen's desktop, applications, or theme.

## Configuration boundaries and outputs

Separate these concerns:

- **Baseline:** locale/timezone, Nix flake support, DHCP-capable networking, users and local recovery, CA certificates, and essential diagnostics.
- **Comin:** pinned upstream module and matching package, public HTTPS remote, branch policy, explicit target identity, polling, timeout, and retention settings.
- **Platform:** Pi firmware/kernel/bootloader/filesystems or VirtualBox GRUB/filesystems/guest support. Runtime platform definitions must not depend on being booted from live installation media.
- **Desktop profile:** existing Bigscreen, app, and theme modules, plus graphical platform requirements. This profile is not imported into bootstrap outputs.
- **Image construction:** SD image for Pi and an installed VirtualBox OVA, separate from desktop selection.
- **Deployment selection:** a small tracked map selecting `bootstrap` or `full` independently for Pi and VirtualBox. This is configuration selection, not an application feature-flag framework.

Preserve the existing full system outputs and live ISO. Add the following explicit outputs:

| Output | Purpose |
| --- | --- |
| `bigscreen-rpi4-bootstrap` | Always-minimal Pi system and SD image build |
| `bigscreen-vbox-bootstrap` | Always-minimal installed VirtualBox appliance |
| `bigscreen-rpi4-deploy` | Pi runtime configuration selected by the deployment map |
| `bigscreen-vbox-deploy` | VirtualBox runtime configuration selected by the deployment map |

Comin on both bootstrap and full managed profiles selects the corresponding `*-deploy` output through `services.comin.hostname`; it never selects an image-builder output. Actual network hostnames may remain unchanged. Explicit selection prevents the shared `bigscreen-tv` hostname from choosing the wrong platform.

Initially both deployment targets resolve to bootstrap. The VM promotion commit changes only the VirtualBox entry to full. The Pi entry remains bootstrap until a later user-authorized commit. Bootstrap image outputs remain minimal even after promotion, so new tags do not accidentally publish the desktop closure.

Existing full outputs remain usable for explicit manual builds. The managed full configuration must retain the same Comin selector and platform contract as its bootstrap counterpart.

## Bootstrap behavior and access

Both images contain enough NixOS to boot persistently, acquire a DHCP lease, resolve DNS, validate HTTPS, evaluate flakes, and run Comin. Use NetworkManager for Ethernet continuity with the existing full configuration. Include no Wi-Fi credentials, GitHub token, deploy private key, test credential, or shared machine identity in an image.

Public bootstrap images expose no SSH service. Local HDMI/keyboard or VM console access uses the existing project's passwordless local `htpc` convention with administrative sudo; no automatic desktop session is installed. Passwordless console access is physical access, not passwordless network login. Console recovery remains possible if GitHub or a deployment is unavailable.

A VM-only, temporary SSH channel may be provisioned out of band for automated inspection. Its private key stays outside the repository and release artifact. If required across activation, install the public key as machine-local state and enable only key authentication in a test-only configuration; remove test access after verification. The canonical public appliance must also be verified without depending on that access. Console-based verification is acceptable if retaining SSH would contaminate the canonical deployment.

Bootstrap excludes Bigscreen, SDDM, application installers, Flatpak, Tailscale, themes, wallpapers, and unnecessary graphical userspace. Required board firmware and the Pi kernel are not optional size optimizations. Preserve the current Pi boot approach; do not introduce a cross-compiled-kernel build path for this native ARM workflow.

VirtualBox uses a dynamically allocated disk with at least 32 GiB virtual capacity to leave room for the desktop closure and deployment generations. Configure 2 vCPUs, at least 4 GiB RAM, VMSVGA, and 128 MiB VRAM for the full-desktop test. Image creation is native x86_64 on the local Linux builder, not cross-built in the ARM release job. Importing the resulting OVA as a named bootstrap golden is within the requested VM image test; leave the pre-existing user golden unchanged and report any newly created durable golden.

## Comin behavior

Add `github:nlewo/comin` as a locked flake input following the project's nixpkgs input. Select the package from that same Comin input explicitly if required to avoid using a mismatched nixpkgs package with newer module options.

Each managed system must:

- Pull `https://github.com/kiweezi/bigscreen.git` without credentials.
- Deploy only `comin/deploy`, with operation `switch` and a 60-second poll period.
- Set `remotes.*.branches.testing.name = ""` to disable Comin's default testing-branch selection. Upstream's repository selector explicitly skips an empty testing-branch name; confirm this behavior for the locked revision with a focused test.
- Enable `nix-command` and `flakes`; evaluate the committed lockfile without opportunistic input updates.
- Keep Comin's persistent state on the installed root filesystem, including across profile transitions and reboots.
- Allow up to two hours for a build, rather than relying on the upstream 30-minute default for the first full deployment; the evaluation timeout remains 30 minutes.
- Keep at least the default three successful/boot-entry generations and five recent deployment records; do not add aggressive automatic store garbage collection in this change.
- Bind observability endpoints to loopback and keep their ports closed to inbound network traffic. Leave debug logging disabled.

There is no Git credential in a public-read pull. Write access to the deployment branch is effectively permission to administer these machines. Document that trust boundary and recommend protecting the branch; do not modify repository protection settings as part of this task. Commit-signature enforcement is deferred until the user selects a signing identity and policy.

Comin evaluates and builds on the target device using available Nix substitutes. Native ARM image CI does not turn later Pi deployments into CI-built binary deployments. A separate binary cache and full-system prebuild pipeline are out of scope.

## Branch lifecycle and failure behavior

The image is built from a tag's commit, while runtime configuration comes from the moving `comin/deploy` branch. This distinction is deliberate. No push to `main` automatically promotes a device, and no tag is required for an ordinary deployment.

Publish implementation and the initial minimal deployment map to `comin/deploy` before promotion. Use subsequent normal descendant commits for the VM promotion and follow-up change. Never force-push or reset the branch behind a deployed commit: upstream Comin rejects that ancestry pattern. Undo a deployment through a new reverting commit, not branch history rewriting.

If networking, GitHub, the branch, or a configuration output is unavailable, the bootstrap or last activated system remains usable and Comin continues retrying. Evaluation and build failures must not replace the running system. A failed activation is not promised to be transactionally rolled back; retain previous boot generations and local recovery, and document the distinction. Reverting a bad configuration is a forward Git commit.

`switch` activates userspace and updates the boot configuration but does not guarantee that a new kernel is running. Do not automatically reboot a TV. The VM acceptance test performs an explicit reboot, and operational instructions explain when a Pi reboot is needed.

## Tag-triggered ARM release workflow

Add a workflow for pushed semantic-version tags, not `release.published`, because the workflow creates the release. GitHub tag globs support only `*`/`**`, so trigger on `push.tags: ['v*']` and then validate in a job that the tag matches `v<major>.<minor>.<patch>` (rejecting non-semver tags with a clear failure) before building. The release name and artifact names derive from the tag.

Every job runs on an ARM64 runner, and the workflow checks out the exact tag commit and verifies the runner architecture is `aarch64` before building; it must not enable QEMU/binfmt or silently fall back to x86_64. GitHub publishes no unpinned Linux ARM label (there is no `ubuntu-latest-arm`), so the newest general-availability label `ubuntu-26.04-arm` is the closest match to "latest". Adopting a future image is a deliberate one-line label change once GitHub generally recommends a newer ARM image.

The workflow installs Nix with flake support, validates the bootstrap configuration, then builds:

```sh
nix build --no-write-lock-file \
  .#nixosConfigurations.bigscreen-rpi4-bootstrap.config.system.build.sdImage
```

Use pinned action revisions and minimal permissions. Build steps need repository read access; release publication requires `contents: write`. Do not export GitHub credentials into the image or Nix derivations. Scope any upload credential to the publication step and avoid persisted checkout credentials.

Publish a release for the existing tag only after the build and artifact checks succeed. The attached image and checksum both derive from the tag. For a semantic-version tag such as `v1.2.3`, attach:

- `bigscreen-rpi4-bootstrap-v1.2.3.img.zst`;
- a SHA-256 checksum file for the exact attached image.

Release notes identify the source commit, bootstrap-only purpose, DHCP/console assumptions, and `comin/deploy` runtime source. Verify exactly one expected SD image exists and the compressed file is readable before publication. Handle reruns by updating the same tag's release assets deliberately, never creating or moving a tag.

Runner disk capacity is a known risk: GitHub documents 14 GiB standard storage and the Pi vendor kernel may miss the binary cache. Preflight disk space, reclaim only documented disposable runner tools if needed, and fail clearly if insufficient; do not claim a successful ARM build without a completed ARM runner execution. A public repository can use the standard ARM runner without a self-hosted machine, but this does not guarantee every kernel build fits its disk/time limits.

No actual tag or release is created during the authorized VM test. Workflow correctness can be evaluated and linted now; a successful tag-triggered ARM run remains a separate acceptance item pending permission to publish a tag.

## Verification and evidence

### Static and build checks

- Preserve the current working-tree changes and verify the staged diff contains only intended files.
- Evaluate all existing and new system outputs with the committed lockfile.
- Add focused flake checks/assertions for bootstrap minimality, independent deployment selection, explicit Comin selectors, branch policy, no public bootstrap SSH, retained Comin after promotion, platform/disk compatibility, and ARM-only tag-release workflow expectations.
- Run `nix flake check --all-systems --no-build --no-write-lock-file` plus the relevant buildable checks on the available native builder.
- Run formatter/lint checks for changed Nix and workflow files using commands selected in the implementation plan; no existing project lint/typecheck script currently exists. Nix module evaluation supplies option/type validation.
- Build the actual VirtualBox bootstrap appliance and full VirtualBox toplevel. Do not substitute switching the existing full desktop golden down to minimal as proof of fresh-image correctness.

### VirtualBox end-to-end test

1. Fork the existing terrarium golden only as an isolated builder when useful. Check available guest disk and memory before building.
2. Build and import a new canonical minimal OVA, then fork a disposable test environment. The new image must not contain the builder's user state, repository working tree, SSH identities, or preinstalled desktop closure.
3. Boot it with both deployment targets still minimal. Verify persistent ext4 storage, no display manager/desktop, working DHCP, and active Comin targeting GitHub's `comin/deploy`.
4. Temporarily interrupt guest connectivity and restore it; verify Comin recovers without rebuilding or reflashing the image.
5. Push a valid descendant commit selecting the full profile for VirtualBox only. Record the Git SHA. Do not push another change while that deployment is still building.
6. Observe Comin, not a manual `nixos-rebuild`, evaluate/build/switch to that exact commit. Verify the Pi selector remains minimal, Comin remains active, and Bigscreen is running using service/process checks and a fresh screenshot.
7. Reboot explicitly. Confirm the installed full profile, root filesystem, and Comin state survive. Capture another screenshot.
8. Push a second harmless VM-only configuration change with an observable marker, verify its deployed SHA and marker, and remove the temporary marker in a follow-up commit.
9. Exercise a controlled VM-only invalid configuration commit after the valid baseline; verify evaluation fails without changing the active system. Recover with a new fixing/reverting commit and verify deployment resumes. Pi configuration must remain evaluable throughout.
10. Remove temporary test access and disposable test environments created for this task. Do not remove the user's existing golden or expired environment without separate approval. Report any retained bootstrap golden and the final deployment SHA.

Record actual command results, Comin status/journal evidence, current system paths before/after, commit SHAs, and screenshots. Separate tested VM behavior from untested physical Pi boot and unexecuted release publication.

## Repository publication and documentation

Implementation may commit and push to both `main` and `comin/deploy`, but only the minimum commits needed. Prefer grouping related changes and avoid throwaway commits; where a deployment-branch promotion can be one commit, make it one. Commit messages must be plain and factual, with no AI watermarks, co-author trailers, or tool attribution. Avoid unrelated local edits (`.gitignore`, `opencode.jsonc`) in those commits.

Deployment-branch commits must be descendants of the currently deployed commit; never force-push or reset `comin/deploy` behind a deployed commit, because upstream Comin rejects that ancestry. `main` remains the integration branch for the workflow and configuration; pushing to `main` does not itself deploy any device. No tag, release, or Pi promotion occurs in this session.

Update the existing README rather than creating additional operational documents. Describe bootstrap builds, tag releases, flashing/decompression, Ethernet boot, console recovery, deployment-map promotion, logs, forward-revert recovery, manual reboot, and VM test results. Explicitly document that future fresh boots immediately converge to the current deployment-branch selection, not necessarily the bootstrap state used during initial testing.

## Out of scope

- Creating a real release/tag or promoting the physical Pi during this session.
- Wi-Fi provisioning, SSH keys in public artifacts, Tailscale enrollment, or secrets management.
- Full-system CI prebuilds or a new binary-cache service.
- Automatic reboot, guaranteed automatic activation rollback, or fleet orchestration.
- Reworking desktop applications, Flatpak behavior, or existing graphical quirks.
- Claiming that VirtualBox validation proves Pi firmware, kernel, GPU, or physical boot correctness.

## Approval checkpoint

Review this specification before implementation planning. After approval, prepare the implementation plan, including precise checks and the VM transport/build procedure, then ask the user to select its execution method. No implementation, branch publication, or release build has been performed at this stage.
