# TODO — NixOS Configuration

This list is ordered by operational risk and depends on the static review in `CODE_REVIEW.md`. Status reflects the repository snapshot, not live machines.

## P0 — Human safety gates (before destructive or production actions)

- [ ] **Human:** Confirm the six Mercury storage drive IDs and the boot SSD ID using `/dev/disk/by-id`, model, serial, and capacity. Compare against `hosts/mercury/{disko.nix,storage-pool.nix}`.
- [ ] **Human:** Confirm the existing ZFS pool and dataset state with `zpool status storage` and `zfs list -o name,mountpoint,canmount,compression,recordsize`. Do not re-create the pool or run destructive disko commands as part of ordinary rebuilds.
- [ ] **AI + Human:** On a Nix-capable machine, evaluate all three NixOS hosts and both Home Manager outputs. Resolve every evaluation error before switching any host.
- [ ] **Human:** Decide whether Mercury should allow SSH directly to root. If not essential, remove the root authorized key and use `gemini` plus `sudo`.
- [ ] **Human:** Test Google Drive sync with a dry run/test remote and disposable files before the first real `rclone sync` against `gdrive:Outbox`.

## P1 — Correctness and reliability

- [ ] **AI:** Fix Minecraft backup cleanup so `save-on` runs even if backup creation fails. Write backups into temporary directories, publish only successful backups, verify source data, and prune only complete backups.
- [ ] **AI:** Update n8n reverse-proxy configuration instructions and environment variables to `N8N_WEBHOOK_URL`, `N8N_EDITOR_BASE_URL`, and `N8N_PROXY_HOPS=1` for the pinned n8n version.
- [ ] **AI:** Implement and version-control the missing sticker wrapper scripts: input validation, ImageMagick processing, silhouette/border, geometry-aware nesting, sheet rendering, registry reservation, commit journal, rejection rollback, and deterministic reprint.
- [ ] **AI:** Export/version-control the actual n8n workflow JSON(s), including Form Trigger, validation, per-image processing, wait/approval, retry/change-layout path, commit, and Error Trigger notification.
- [ ] **AI:** Add concurrency/idempotency guarantees to listing-number reservation. A SQLite transaction plus a unique constraint should be the single allocator; filename scanning is only a bootstrap/reconciliation input.
- [ ] **AI:** Rework the SMB retry logic so every scheduled health check verifies current mounts and bounded share access even after the original oneshot unit has succeeded. On required-share failure, update status and block/stop automation.
- [ ] **AI + Human:** Confirm `pkgs.minecraftServers.vanilla-26_2` exists at the locked nix-minecraft revision and evaluate the Mercury toplevel.
- [ ] **AI:** Add a safe sync preview command and update the outbox documentation so the first-time test is genuinely non-destructive.

## P2 — Service boundaries and filesystem correctness

- [ ] **Human + AI:** Decide whether `Shop-Accounting` should be writable by regular Samba users. The current `read only = no` setting conflicts with a root-owned, non-group-writable share root. Choose explicit read-only or correctly scoped write permissions.
- [ ] **AI:** Gate Ollama on the actual model-storage mount, or move models to a stable dedicated data path, so `nofail` cannot hide model writes on the root filesystem.
- [ ] **AI:** Remove the stale Uranus TCP 7125 firewall exception unless a service truly uses it; check the effective listener/port policy first.
- [ ] **AI:** Pin Odysseus and ChromaDB images to tested release tags or digests. Keep upgrades deliberate and recorded.
- [ ] **Human + AI:** Confirm the Windows VM threat model for `pcie_acs_override=downstream,multifunction`. Treat ACS override as a compatibility workaround, not hardware-enforced IOMMU isolation; inspect full groups and only pass through intended devices. Prefer native ACS separation if the guest must be untrusted.
- [ ] **AI:** Consolidate ZFS mount-dependent tmpfiles/permission handling and ensure a missing pool cannot cause permission changes to bare mountpoint directories.
- [ ] **Human + AI:** Decide whether all six SMB shares really must be mandatory for n8n, including host-only `Shop-Accounting`, `Shop-3DModels`, and `Shop-Videos`. Keep all-share checks if that is an explicit policy; otherwise define critical and optional share sets.
- [ ] **AI:** Document and enforce the trust boundary for n8n Execute Command: restrict editors, keep the UI tailnet-only, keep shell wrappers fixed, and evaluate a separate processing worker.
- [ ] **Human:** Verify that SMB credentials, n8n environment files, rclone credentials, and the n8n encryption key exist with the intended ownership/mode on the correct host. Never commit them.

## P3 — Consolidation and maintainability

- [ ] **AI:** Consolidate repeated Home Manager option imports and duplicated `nixpkgs.overlays` / `allowUnfree` declarations where it reduces real maintenance without creating implicit magic.
- [ ] **AI:** Create a small account/profile matrix for host accounts, groups, SSH policy, Home Manager output, and enabled profiles. Preserve host-specific privileges explicitly.
- [ ] **AI:** Correct stale comments and setup-guide artifacts, including the literal `\n` in the SMB share list, the outdated VM placeholder note, and the contradictory outbox “not exposed over Samba” comment.
- [ ] **AI:** Decide whether a reusable module should own each domain (storage, shares, backups, containers) or whether small host-specific modules should remain separate. Avoid one monolithic module.
- [ ] **AI:** Add formatting/static checks and non-destructive CI. Do not run deploy, format disks, import pools, mutate remote Drive data, or restart production services in CI.
- [ ] **AI:** Make the Home Manager target system explicit if non-x86_64 configurations are planned; current `mkHome` is hardcoded to `x86_64-linux`.
- [ ] **Human:** Decide whether the one-time Windows VM definition should be version-controlled declaratively rather than requiring manual virt-manager setup.

## Validation checklist (repeat after every structural change)

- [ ] `nix flake check --show-trace`
- [ ] Evaluate `system.build.toplevel.drvPath` for `saturn`, `uranus`, and `mercury`.
- [ ] Evaluate Home Manager activation packages for `aquarius@uranus`, `aquarius@saturn`, and `gemini@mercury`.
- [ ] Evaluate the Minecraft package attribute at the locked input revision.
- [ ] Run `nix fmt`, inspect the diff, and check for accidental unrelated changes.
- [ ] Test SMB mount fail/recovery behavior, the n8n startup gate, GNOME failure notification, Google Drive dry-run/delete guard, Minecraft backup failure cleanup, and a complete sticker job with disposable test data.
- [ ] Only after successful staging tests, deploy one host at a time and retain a rollback generation.
