# TODO — NixOS Configuration

This list is ordered by operational risk and depends on the static review in `CODE_REVIEW.md`. Status reflects the repository snapshot, not live machines.

## P0 — Human safety gates (before destructive or production actions)

- [ ] **Human:** Confirm the six Mercury storage drive IDs and the boot SSD ID using `/dev/disk/by-id`, model, serial, and capacity. Compare against `hosts/mercury/{disko.nix,storage-pool.nix}`.
- [ ] **Human:** Confirm the existing ZFS pool and dataset state with `zpool status storage` and `zfs list -o name,mountpoint,canmount,compression,recordsize`. Do not re-create the pool or run destructive disko commands as part of ordinary rebuilds.
- [ ] **AI + Human:** On a Nix-capable machine, evaluate all three NixOS hosts and both Home Manager outputs. Resolve every evaluation error before switching any host.
- [ ] **Human:** Decide whether Mercury should allow SSH directly to root. If not essential, remove the root authorized key and use `gemini` plus `sudo`.
- [ ] **Human:** Run `sudo tailscale up` on mercury to join the tailnet, then set up each real artist account (replace the `artist-example` placeholder in `hosts/mercury/configuration.nix`, run `smbpasswd -a <name>`) and write the Tailscale ACL restricting artist devices to mercury:445 only. See `hosts/mercury/tailscale.nix`.

## P1 — Correctness and reliability

- [ ] **AI:** Fix Minecraft backup cleanup so `save-on` runs even if backup creation fails. Write backups into temporary directories, publish only successful backups, verify source data, and prune only complete backups.
- [ ] **AI:** Update n8n reverse-proxy configuration instructions and environment variables to `N8N_WEBHOOK_URL`, `N8N_EDITOR_BASE_URL`, and `N8N_PROXY_HOPS=1` for the pinned n8n version.
- [ ] **AI:** Implement and version-control the missing sticker wrapper scripts: input validation, ImageMagick processing, silhouette/border, geometry-aware nesting, sheet rendering, registry reservation, commit journal, rejection rollback, and deterministic reprint.
- [ ] **AI:** Export/version-control the actual n8n workflow JSON(s), including Form Trigger, validation, per-image processing, wait/approval, retry/change-layout path, commit, and Error Trigger notification.
- [ ] **AI:** Add concurrency/idempotency guarantees to listing-number reservation. A SQLite transaction plus a unique constraint should be the single allocator; filename scanning is only a bootstrap/reconciliation input.
- [ ] **AI:** Rework the SMB retry logic so every scheduled health check verifies current mounts and bounded share access even after the original oneshot unit has succeeded. On required-share failure, update status and block/stop automation.
- [ ] **AI + Human:** Confirm `pkgs.minecraftServers.vanilla-26_2` exists at the locked nix-minecraft revision and evaluate the Mercury toplevel.

## P2 — Service boundaries and filesystem correctness

- [ ] **Human + AI:** Decide whether `Shop-Accounting` should be writable by regular Samba users. The current `read only = no` setting conflicts with a root-owned, non-group-writable share root. Choose explicit read-only or correctly scoped write permissions.
- [ ] **AI:** Gate Ollama on the actual model-storage mount, or move models to a stable dedicated data path, so `nofail` cannot hide model writes on the root filesystem.
- [ ] **AI:** Remove the stale Uranus TCP 7125 firewall exception unless a service truly uses it; check the effective listener/port policy first.
- [ ] **AI:** Pin Odysseus and ChromaDB images to tested release tags or digests. Keep upgrades deliberate and recorded.
- [ ] **Human + AI:** Confirm the Windows VM threat model for `pcie_acs_override=downstream,multifunction`. Treat ACS override as a compatibility workaround, not hardware-enforced IOMMU isolation; inspect full groups and only pass through intended devices. Prefer native ACS separation if the guest must be untrusted.
- [ ] **AI:** Consolidate ZFS mount-dependent tmpfiles/permission handling and ensure a missing pool cannot cause permission changes to bare mountpoint directories.
- [ ] **Human + AI:** Decide whether all six SMB shares really must be mandatory for n8n, including host-only `Shop-Accounting`, `Shop-3DModels`, and `Shop-Videos`. Keep all-share checks if that is an explicit policy; otherwise define critical and optional share sets.
- [ ] **AI:** Document and enforce the trust boundary for n8n Execute Command: restrict editors, keep the UI tailnet-only, keep shell wrappers fixed, and evaluate a separate processing worker.
- [ ] **Human:** Verify that SMB credentials, n8n environment files, and the n8n encryption key exist with the intended ownership/mode on the correct host. Never commit them.
- [ ] **Human + AI:** Design per-artist sharing within `Shop-Assets`, now that the Google Drive mirror is gone - each artist/collaborator gets access scoped to their own subdirectory, not the whole share. Decide the mechanism (per-artist Samba accounts + per-directory `valid users`/path like the `Shop-Inbox` pattern, vs. something else) and how directories map to artists before implementing - this is additional access to an existing business share, so needs an explicit decision, not an assumption.

## P3 — Consolidation and maintainability

- [ ] **AI:** Consolidate repeated Home Manager option imports and duplicated `nixpkgs.overlays` / `allowUnfree` declarations where it reduces real maintenance without creating implicit magic.
- [ ] **AI:** Create a small account/profile matrix for host accounts, groups, SSH policy, Home Manager output, and enabled profiles. Preserve host-specific privileges explicitly.
- [ ] **AI:** Correct stale comments and setup-guide artifacts, including the literal `\n` in the SMB share list and the outdated VM placeholder note.
- [ ] **AI:** Decide whether a reusable module should own each domain (storage, shares, backups, containers) or whether small host-specific modules should remain separate. Avoid one monolithic module.
- [ ] **AI:** Add formatting/static checks and non-destructive CI. Do not run deploy, format disks, import pools, mutate remote Drive data, or restart production services in CI.
- [ ] **AI:** Make the Home Manager target system explicit if non-x86_64 configurations are planned; current `mkHome` is hardcoded to `x86_64-linux`.
- [ ] **Human:** Decide whether the one-time Windows VM definition should be version-controlled declaratively rather than requiring manual virt-manager setup.

## Staged review queue (external LLM pass, 2026-10-28)

Four-phase todo list from an external LLM review pass, added verbatim except for the dev-environment leftover item that was dropped. Numbering is sequential within this section only and does not correspond to the P0–P3 items above.

### Phase 1 — Bugs

- [ ] **AI:** `sysadmin.nix`: `hh` is a script that runs `cd` (no effect). Replace with `programs.bash.shellAliases.hh`.
- [ ] **AI + Human:** Remove dead references to `AGENTS.md`, `CODE_REVIEW.md`, `TODO.md`, `prompts/`, `AI_PROMPTS.md`, `hosts/uranus/STICKER-AUTOMATION.md`, and `sticker/tests` from `README.md` and all `.nix` comments. Update README's sticker status (scripts ARE committed) and add saturn to the rebuild section.
- [ ] **AI:** uranus `AMD.nix`: replace the global `nixpkgs.config.rocmSupport` with a blender-only override; confirm with `nvd` that only blender's closure changes.
- [ ] **AI + Human:** Declare `users.users.aquarius.uid = 1000` on uranus (check `id aquarius` first; ask the owner if it isn't 1000).
- [ ] **AI:** Move `services.fprintd.enable` from `hosts/desktop.nix` to saturn.
- [ ] **AI + Human:** Remove bspwm xsession config from `home-manager/aquarius` (GNOME is used); ask whether obsidian/spotify should autostart via GNOME instead.
- [ ] **AI + Human:** Delete the commented `./nvidia.nix` import; ask whether to delete `obs.nix`.
- [ ] **Human:** Clarify what TCP 7125 on uranus is for; document or remove it. (Related to the existing P2 item on this same port.)
- [ ] **AI + Human:** Add to `hosts/common`: `services.openssh.settings.PasswordAuthentication = false` (only where ssh is enabled), `nix.gc` (weekly, `--delete-older-than 14d`), `nix.optimise.automatic`, `boot.loader.systemd-boot.configurationLimit = 10`. Ask whether the mercury root SSH key stays. (Related to the existing P0 item on mercury root SSH.)
- [ ] **AI + Human:** Pin odysseus and chromadb images to explicit tags (ask for versions, or use the current digest). (Duplicate of the existing P2 pinning item — resolve together.)
- [ ] **AI + Human:** Fix deprecated `programs.git` options if the build warns; ask which git email to use.
- [ ] **AI:** Remove stale comments: mercury `hardware-configuration` "doesn't exist yet", redundant `zfs-mount.enable`, saturn/uranus `stateVersion` cross-reference.

### Phase 2 — Condense (each change must be closure-neutral)

- [ ] **AI + Human:** `flake.nix`: drop template comments, set `description`, `systems = ["x86_64-linux"]`, add an `mkHost` helper; move `nixos-hardware` (saturn) and disko/disko-zfs/minecraft modules (mercury) into each host's own imports via `inputs`. Ask before removing the `nixos-anywhere` input.
- [ ] **AI:** Create `hosts/common/{default,users,tailscale,nix}.nix`; move shared aquarius/camelliasnowflower users there (saturn+uranus only), drop empty packages lists, dedupe tailscale enable between `mercury/tailscale.nix` and `sticker-automation.nix`, drop redundant `extraLocaleSettings` and redundant tailscale/cifs-utils/fastfetch package entries.
- [ ] **AI:** Replace the claude-code module + `hosts/uranus/claude-code.nix` wrapper with a plain package + env var in uranus config; remove it from `modules/nixos/default.nix`.
- [ ] **AI + Human:** Define mercury's address once (prefer MagicDNS name; ask the owner for it) and use it in `sysadmin.nix` and `sticker-automation.nix`.
- [ ] **AI:** `storage-pool.nix`: generate the six disk entries from a list of by-id names. (Depends on confirming the by-id names in the existing P0 drive-ID item.)
- [ ] **AI:** Create `hosts/mercury/shares.nix` as the single source of truth for shares (dataset, mountpoint, zfs props, sanoid template, owner/group/mode, samba users/hosts allow) and generate disko-zfs datasets, sanoid datasets, storage-permissions, and samba share sections from it. Do this in small steps, nvd-diffing and also diffing the generated `smb.conf` (`nix build .#nixosConfigurations.mercury.config.environment.etc."samba/smb.conf".source`) before/after; output must be identical.
- [ ] **AI:** `sticker-notification.nix`: factor the three watcher script/service/path triples into an `mkWatcher` helper; generated units must be identical.
- [ ] **AI:** `sticker-automation.nix`: merge the duplicated `share_target`/`publish_status` logic into one script file (`mercury-shares.sh` with `mount` and `check` modes) loaded via `writeShellApplication` + `builtins.readFile`; generate the tmpfiles rules from the share list.
- [ ] **AI + Human:** Replace `hms`/`sms`/`hmsb`/`sms-mercury`/`hms-mercury`/`gmu` with `nh` (`programs.nh` with flake path set) plus `nixos-rebuild --target-host gemini@<mercury> --sudo` for mercury. Ask before removing `gmu`.

### Phase 3 — Split / restructure

- [ ] **AI:** Turn `sticker-automation.nix` into `modules/nixos/sticker-automation.nix` with options (`enable`, `mercuryAddress`, `shares`, `requiredShares`, `n8nImage`, `credentialsFile`, `environmentFile`); uranus just enables it.
- [ ] **AI:** Move `sticker/` into `pkgs/sticker-tool/`: split `sticker_tool.py` into a package (registry, imaging, nesting, svg_layout, cli), build with `python3Packages.buildPythonApplication`, keep the `sticker-tool` entrypoint and subcommands unchanged. Add pytest tests for: SKU/regex validation, registry allocation, intake validation rejecting bad input, nest no-overlap, commit/reject idempotence, and `minecraft-backup.sh` with stubs. Wire tests as `doCheck`.
- [ ] **AI:** Home Manager: merge `common/` + `optional/` profile modules into `home-manager/profiles/`, each file declaring its own `options.profiles.<x>.enable`; keep `nixpkgs.nix`/fonts as base. Pass `hostname` via `mkHome` and import `home-manager/aquarius/<host>.nix` if it exists; move `sticker-notification.nix` to `aquarius/uranus.nix`.
- [ ] **AI:** Split uranus imports into `hardware/{amd,vfio}.nix`, `gaming.nix` (steam + monitor scripts), `creative.nix` (3D), `ai.nix` (ollama + odysseus + claude-code).
- [ ] **AI:** Group mercury into `storage/` and `services/` subfolders.

### Phase 4 — Safety net

- [ ] **AI:** Add a `checks.x86_64-linux` output building all three toplevels, all three HM activationPackages, the sticker-tool package (with tests), and a formatting check.
- [ ] **AI:** Add `.github/workflows/check.yml` running `nix flake check` with `cachix/install-nix-action` (no secrets).
- [ ] **AI + Human:** Evaluate sops-nix or agenix for `/etc/nixos/secrets/*` and the n8n env file; write a proposal, don't implement until approved.
- [ ] **AI:** Trim comments that narrate history (move the story to commit messages), rewrite README to match the final tree, update `docs/ACCOUNTS.md`.

## Validation checklist (repeat after every structural change)

- [ ] `nix flake check --show-trace`
- [ ] Evaluate `system.build.toplevel.drvPath` for `saturn`, `uranus`, and `mercury`.
- [ ] Evaluate Home Manager activation packages for `aquarius@uranus`, `aquarius@saturn`, and `gemini@mercury`.
- [ ] Evaluate the Minecraft package attribute at the locked input revision.
- [ ] Run `nix fmt`, inspect the diff, and check for accidental unrelated changes.
- [ ] Test SMB mount fail/recovery behavior, the n8n startup gate, GNOME failure notification, Minecraft backup failure cleanup, and a complete sticker job with disposable test data.
- [ ] Only after successful staging tests, deploy one host at a time and retain a rollback generation.
