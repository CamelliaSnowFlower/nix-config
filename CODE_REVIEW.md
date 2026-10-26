# Strict Code Review — NixOS Configuration

**Scope:** the latest uploaded configuration archive plus the latest quick-glance `README.md`: 51 tracked files, including 46 `.nix` files, `flake.lock`, Markdown documentation, and the Stylix image. This is a static review of the repository contents, not a report of a deployment test.

**Validation limitation:** the review environment did not have `nix`, `nix-instantiate`, `alejandra`, `statix`, or `deadnix` available. I could not evaluate the flake, type-check NixOS options, build host configurations, inspect a live system, or test services. Any package/option concern below that explicitly says “verify” is not asserted to be a confirmed evaluation failure.

## Executive verdict

The repository has a recognizable structure and several good practices: a locked flake, shared NixOS and Home Manager layers, host-specific profiles, secret files kept outside the repository/Nix store, pinned n8n and SearXNG images, loopback-bound n8n, a dedicated rclone service account, and an explicit mountpoint guard before Drive synchronization.

It is **not yet ready to be treated as a production-complete sticker automation system**. Several supporting services are configured, but the sticker scripts and actual n8n workflow are still absent. There are also reliability and operational issues worth resolving before depending on unattended jobs or performing destructive storage operations.

## Findings, ordered by priority

### P1 — Fix before relying on unattended production operation

#### CR-01 — Minecraft backup may leave world saving disabled after an error

- **Location:** `hosts/mercury/minecraft-backup.nix:25–50`
- **Finding:** the script sends `save-off`, flushes the world, then runs `rsync`; `save-on` is sent only after `rsync` succeeds. `writeShellApplication` uses strict shell behavior, so an `rsync` failure can exit before `save-on`. A failed copy also leaves a timestamped partial directory under the live backup root. A later successful run can count that partial directory toward retention and eventually prune a known-good backup.
- **Required change:** use a trap/cleanup path that attempts `save-on` on every exit after `save-off`; copy into a clearly named temporary directory, verify success, then atomically rename it to a completed timestamp; prune only completed backups. Verify the world directory exists and make the flush/backup completion test more robust than an unconditional 10-second sleep.
- **Acceptance test:** simulate a failed `rsync`, confirm `save-on` is sent, no completed backup is published, and the last known-good backups remain untouched.

#### CR-02 — Sticker n8n reverse-proxy setup uses an outdated webhook variable

- **Location:** `hosts/uranus/STICKER-AUTOMATION.md:35`; `hosts/uranus/sticker-automation.nix:202–215`
- **Finding:** the setup instructions say to set `WEBHOOK_URL`. Current n8n documentation says `N8N_WEBHOOK_URL` replaces `WEBHOOK_URL` starting with n8n 2.35.0. The configured image is n8n `2.44.7`. The reverse-proxy instructions should also set `N8N_PROXY_HOPS=1` when using a single proxy hop. Otherwise generated webhook/form URLs and proxy-related behavior may be wrong or emit deprecation warnings.
- **Required change:** configure `N8N_WEBHOOK_URL=https://<tailnet-hostname>/`, `N8N_EDITOR_BASE_URL=https://<tailnet-hostname>/`, and `N8N_PROXY_HOPS=1` in the external environment file; update the setup guide and test the actual Form Trigger URL from a Tailscale-connected client. Preserve the current loopback-only host port and do not enable Funnel or router forwarding.
- **Reference:** https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/configuration-examples/configure-webhook-urls-with-reverse-proxy/

#### CR-03 — The sticker module is infrastructure scaffolding, not a working production workflow yet

- **Location:** `hosts/uranus/sticker-automation.nix`; `hosts/uranus/STICKER-AUTOMATION.md:76–88`
- **Finding:** the module mounts `/srv/sticker-automation/scripts` read-only into the container, but there are no script files in the repository. There is also no exported n8n workflow JSON and no implemented validation, image processing, silhouette, nesting, composition, atomic registry reservation/commit, approval, rollback, or error-trigger workflow. The setup guide correctly acknowledges that these parts remain to be implemented.
- **Required change:** add version-controlled fixed scripts and workflow exports before calling the feature complete. Define the job state model and test idempotency, concurrent reservations, partial-failure recovery, rejection cleanup, and deterministic reprints. Treat uploaded filenames and customer text as data, never shell syntax.
- **Acceptance test:** a known test image flows through preview/approval/commit end to end, survives a process restart, and can be reprinted from its saved layout recipe without re-nesting.

#### CR-04 — SMB retry timer does not continuously revalidate successful mounts

- **Location:** `hosts/uranus/sticker-automation.nix:153–257`
- **Finding:** `mercury-smb-mounts.service` is a successful `Type=oneshot` with `RemainAfterExit=true`. The retry service exits immediately when that unit is active, so it does not re-check the mounts after the initial successful run. If a share is later unmounted, mounted from the wrong source, or becomes stale, the five-minute timer can fail to notice it while the mount unit remains active.
- **Required change:** separate “mount and verify current share state” from the long-lived systemd success marker. On every scheduled check, verify each source and perform a bounded read/access probe; define what happens on a stale CIFS filesystem; update the status file and stop/block n8n when required shares are unhealthy. Keep the requirement that a failed check never prevents the rest of system boot.
- **Acceptance test:** unmount one share after a successful boot (and separately simulate an unreachable/stale share); the health check must notify, prevent new n8n work, and restore service after recovery.

#### CR-05 — Disko definitions target real disks and can be destructive when used for installation/repartitioning

- **Location:** `hosts/mercury/disko.nix`; `hosts/mercury/storage-pool.nix`; `flake.nix:136–145`
- **Finding:** the configuration specifies one boot disk and six storage disks by fixed `/dev/disk/by-id` values. The `disko.nix` comments explicitly state that the boot layout is destructive. This is appropriate for declarative storage only if the device mapping is continuously verified; a mistaken install/repartition command could erase the wrong drive.
- **Required change:** keep ordinary review/build steps separate from destructive disko execution. Before any install/format operation, confirm every ID against `ls -l /dev/disk/by-id`, record model/serial/capacity, and verify the existing pool with `zpool status storage`. Never run `disko`, `nixos-anywhere`, format, or pool-recreation commands as part of a routine AI-generated patch without explicit human authorization.
- **Acceptance test:** document a dry review procedure that does not format or mount over live data; perform destructive steps manually only after matching every device.

#### CR-06 — Google Drive sync uses destructive mirror semantics; the documented “dry/test” step is not actually a dry run

- **Location:** `hosts/mercury/outbox-sync.nix:129–175`; first-time instructions in the same file
- **Finding:** the service runs `rclone sync`, which makes the destination mirror the source, including deleting destination-only files. `--max-delete 100` is a useful guard but still allows up to 100 deletions. The instructions tell the operator to start the real service for testing and later mention doing a dry/test run, but the service itself has no dry-run mode.
- **Required change:** provide a distinct, explicitly invoked dry-run/preview command or temporary test remote, compare the source/destination listing before the first production sync, and test deletion behavior using disposable data. Keep the mount check and `.staging` exclusion. Consider a configurable dry-run flag that defaults to false only after a deliberate activation.
- **Acceptance test:** a test run reports planned creates/updates/deletes without changing Drive; a separate approved real sync has a clear deletion count and cannot target an unintended remote/path.

### P1 — Security decision requiring explicit owner confirmation

#### CR-07 — A public key is installed directly for root SSH on Mercury

- **Location:** `hosts/mercury/configuration.nix:49–56`
- **Finding:** the same public key is authorized for both `gemini` and `root`, while `services.openssh.enable = true`. Depending on the effective sshd policy, possession of the corresponding private key can grant direct root shell access. The configuration comment suggests this is intentional as a recovery path; this is therefore a high-risk design choice rather than an unconditional bug.
- **Required decision:** confirm whether direct root SSH is truly required. Prefer `gemini` plus audited `sudo` and remove the root key if not. If retained as a recovery mechanism, document why, limit the exposure path, and test effective SSH policy (`sshd -T`) from a trusted network.

### P2 — Correctness, reliability, and security improvements

#### CR-08 — Shop-Accounting is declared writable in Samba but its dataset root remains root-owned and not group-writable

- **Location:** `hosts/mercury/samba-shares.nix:86–123`; dataset `storage/shop-accounting` in `hosts/mercury/disko-zfs.nix`
- **Finding:** `Shop-Accounting` has `read only = no`, but the permission-normalization rule intentionally excludes `/mnt/storage/shop-accounting`. The dataset creation comments state new dataset roots start `root:root 0755`; therefore ordinary Samba users cannot create a file or directory at the share root. `create mask=0600` / `directory mask=0700` governs items Samba creates, not permission to create the first item in the root directory.
- **Required decision/change:** decide whether the share is deliberately read-only for normal users. If yes, set it read-only and document that. If it must accept writes, set a carefully scoped owner/group/ACL on the dataset root without making existing accounting data broadly readable; retain private file/directory modes.

#### CR-09 — Ollama's model bind mount is marked `nofail` and its source lives under a user's home directory

- **Location:** `hosts/uranus/ollama.nix:16–40`
- **Finding:** Ollama uses `/var/lib/ollama-models`, bind-mounted from `/home/aquarius/Media/SOLID/ollama-models`, with `nofail`. If that mount fails or its source filesystem is unavailable, the daemon may start against the bare mountpoint and write model data onto the system root filesystem, hiding it when the bind mount later becomes available.
- **Required change:** decide whether a user-home path is the intended long-term location. Prefer a dedicated stable data mount under `/mnt` or `/var/lib`, or explicitly gate Ollama startup on the correct mount being present and verified. A mount failure should produce a visible status rather than silently using root storage.
- **Acceptance test:** boot with the SSD absent/unmounted and confirm Ollama does not populate the underlying directory.

#### CR-10 — Uranus opens TCP 7125, but the Odysseus module defaults to loopback port 7000

- **Location:** `hosts/uranus/configuration.nix:53–58`; `modules/nixos/odysseus.nix:85–105`; `hosts/uranus/odysseus.nix:10–28`
- **Finding:** `networking.firewall.allowedTCPPorts = [7125]` has no matching listener in the repository. Odysseus defaults to host port `7000` and `127.0.0.1`, so the firewall exception appears stale.
- **Required change:** remove `7125` unless a separately managed service needs it, or explicitly declare the actual service and port. Verify listening sockets before changing firewall rules.

#### CR-11 — Some OCI image references use mutable `latest` tags

- **Location:** `modules/nixos/odysseus.nix:78–82, 188–192`; `hosts/uranus/odysseus.nix:20–23`
- **Finding:** n8n and SearXNG are pinned, while Odysseus and ChromaDB default to `latest`. Recreating containers may silently change runtime behavior without a corresponding flake diff.
- **Required change:** pin tested version tags, preferably immutable digests for critical services; document and test upgrades as deliberate changes. Update dependent images together only when compatibility requires it.

#### CR-12 — The storage permission fix modifies the global tmpfiles service from multiple modules

- **Location:** `hosts/mercury/samba-shares.nix:117–133`; `hosts/mercury/outbox-sync.nix:195–209`; `hosts/mercury/minecraft-backup.nix:92–107`
- **Finding:** dataset-specific modules add ordering to the global `systemd-tmpfiles-setup` service. NixOS merges these definitions, but the dependency logic is spread across unrelated feature files. Because the dependency is `Wants`/`After` rather than a mount-specific guard, tmpfiles may still run if ZFS mounting failed and adjust the underlying mountpoint directory instead of the dataset.
- **Required change:** consolidate mount-dependent permission rules in a storage module or dedicated post-mount services; gate each operation on the expected ZFS dataset/mount being present. Preserve boot availability when a data pool is unavailable.

#### CR-13 — The accounting share is required for n8n even though n8n cannot access it

- **Location:** `hosts/uranus/sticker-automation.nix:18–27, 153–225`
- **Finding:** all six shares must mount successfully before n8n can start, including `Shop-Accounting`, while the container only receives `Shop-Assets`, `Shop-Designs`, and `Shop-Outbox`. This matches the stated “all shares must mount” requirement, but it couples production automation to shares it never reads and means an accounting-share outage disables sticker processing.
- **Decision:** retain this strict dependency if it is an operational requirement. Otherwise define critical shares (`Shop-Assets`, `Shop-Designs`, `Shop-Outbox`) separately from host-only optional shares, while still notifying on any optional mount failure.

#### CR-14 — Sticker automation enables shell execution inside n8n

- **Location:** `hosts/uranus/sticker-automation.nix:187–215`
- **Finding:** `NODES_EXCLUDE` excludes only `localFileTrigger`, which intentionally re-enables the Execute Command node in n8n 2.x. Anyone allowed to edit/execute workflows effectively gets shell execution inside the container and access to the container's inherited environment. `N8N_RESTRICT_FILE_ACCESS_TO` limits n8n filesystem nodes, not arbitrary shell commands.
- **Required controls:** keep n8n behind Tailscale and authenticated; grant editor access only to trusted operators; keep passwords/tokens out of workflow data and command arguments; use fixed wrapper scripts and validated job IDs. Consider moving processing to a separate worker API so the main n8n container does not need a general shell node.

#### CR-20 — ACS override makes the Windows VM's IOMMU groups an imperfect isolation boundary

- **Location:** `hosts/uranus/windows-vm.nix:41–73`
- **Finding:** the host uses `pcie_acs_override=downstream,multifunction` to split PCIe/IOMMU groups for GPU passthrough. This is a known compatibility workaround, but it can make groups appear separate without adding the missing hardware ACS enforcement. The resulting grouping should not be presented as a strong isolation boundary against a malicious or compromised guest/device.
- **Required decision:** document that the Windows VM is trusted and the override is a convenience workaround, or use hardware/slot topology with genuine ACS isolation if the VM must be a security boundary. Inspect the full IOMMU groups after boot and assign only the intended GPU functions; do not pass bridges or unrelated devices through merely because the software grouping looks separate.
- **Reference:** https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Bypassing_the_IOMMU_groups_(ACS_override_patch)

#### CR-15 — The README/service setup has several stale or contradictory details

- **Locations:** `hosts/uranus/STICKER-AUTOMATION.md:9, 35`; `hosts/uranus/windows-vm.nix:9–14, 64–68`; `hosts/mercury/disko-zfs.nix` outbox comment
- **Finding:** the SMB list in the sticker guide contains a literal `\n-` in the Shop-Outbox line; the guide still refers to `WEBHOOK_URL`; the VM notes say to replace placeholder PCI IDs even though real values are present; and the ZFS outbox comment says the outbox is “not exposed over Samba” while `outbox-sync.nix` explicitly publishes `Shop-Outbox` as a Samba share.
- **Required change:** make the comments and setup guide match the actual implementation, distinguish the SMB share from the Google Drive sync, and remove misleading setup instructions.

### P3 — Maintainability and simplification opportunities

#### CR-16 — User and Home Manager profile facts are duplicated

- **Location:** `hosts/saturn/configuration.nix`, `hosts/uranus/configuration.nix`, `hosts/mercury/configuration.nix`, `home-manager/{aquarius,gemini}/default.nix`, `flake.nix:87–97, 149–157`
- **Finding:** user declarations, overlay configuration, `allowUnfree`, account descriptions, and Home Manager setup are spread across host files. The standalone `mkHome` helper hardcodes `x86_64-linux`, which is valid for current targets but implicit. Some users appear on two desktops with identical descriptions/groups.
- **Recommendation:** build a small account/profile matrix and extract only truly repeated stable parts. Avoid an elaborate framework for three hosts; keep hardware, privilege, and host-specific settings explicit. Make the Home Manager system architecture explicit if non-x86 systems are planned.

#### CR-17 — Optional/profile modules import shared option declarations twice

- **Location:** `home-manager/common/default.nix:2–7`; `home-manager/optional/default.nix:2–6`
- **Finding:** both import `../options.nix`. Nix module import de-duplication may make this harmless, but ownership of the profile option declarations is unclear. Decide on one import location and keep feature modules side-effect-free when disabled.

#### CR-18 — Formatting, linting, and regression automation are missing

- **Location:** repository-wide; `flake.nix:99–114`
- **Finding:** the flake provides an Alejandra formatter output but no repository-level CI/checks for formatting, evaluation of the three hosts, profile evaluation, script tests, or service integration tests. Formatting is inconsistent, and several comments have become stale.
- **Recommendation:** add a documented check script or CI job for formatter check, flake metadata/evaluation, per-host toplevel derivations, Home Manager outputs, Nix shell-wrapper checks, and tests for the backup/sync/mount logic. Never run destructive deployment steps in CI.

#### CR-19 — The README does not distinguish verified architecture from unverified deployment assumptions

- **Location:** `README.md`; `hosts/uranus/STICKER-AUTOMATION.md`
- **Finding:** the architecture summary is useful but describes intended operational flows that have not yet been integration-tested. The Minecraft module itself contains a comment instructing the operator to confirm `pkgs.minecraftServers.vanilla-26_2` exists.
- **Recommendation:** mark setup prerequisites and “implemented vs planned” components explicitly. Evaluate the exact package attribute at the locked `nix-minecraft` revision before deployment; the upstream naming convention replaces dots with underscores, but that alone does not prove the version is present.

## Consolidation direction

Prefer consolidating around **interfaces and policies**, not creating a single giant module:

1. A small host/account inventory that declares usernames, enabled profiles, and explicit privilege/access intent.
2. One storage/share inventory that names datasets, mountpoints, Samba policy, snapshot policy, and mount-dependent permission actions.
3. Reusable container/service hardening conventions while keeping each service's data, secrets, network, and restart policy separate.
4. Reusable operational patterns for health checks, backups, transactional file publication, status reporting, and safe retries.
5. Automated, non-destructive checks and formatting conventions.

Do not change `system.stateVersion`, disk identities, ZFS properties, Samba ACLs, firewall exposure, existing data paths, or direct-root SSH access as a side effect of a broad consolidation. Make those deliberate reviewed changes.

## Required validation before considering the repo reviewed-and-green

Run on a machine with Nix and the intended flake inputs available:

```sh
nix flake check --show-trace
nix eval .#nixosConfigurations.saturn.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.uranus.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.mercury.config.system.build.toplevel.drvPath
nix eval .#homeConfigurations.'aquarius@saturn'.activationPackage.drvPath
nix eval .#homeConfigurations.'aquarius@uranus'.activationPackage.drvPath
nix eval .#homeConfigurations.'gemini@mercury'.activationPackage.drvPath
nix eval .#nixosConfigurations.mercury.pkgs.minecraftServers --apply builtins.attrNames
nix fmt
```

After formatting, inspect the diff rather than blindly committing it. Then perform service tests separately. Do **not** treat `nix flake check` as proof that ZFS, SMB, Tailscale, Google Drive OAuth, OCI images, the Minecraft server, or the sticker pipeline works at runtime.

## References

- n8n reverse proxy and webhook URL configuration: https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/configuration-examples/configure-webhook-urls-with-reverse-proxy/
- n8n filesystem restriction semantics: https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/use-environment-variables/security/
- n8n node exclusion defaults: https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/use-environment-variables/nodes/
- nix-minecraft version naming and package families: https://github.com/Infinidoge/nix-minecraft
- NixOS OCI container systemd integration: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix
- NixOS on ZFS operational notes: https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/index.html
