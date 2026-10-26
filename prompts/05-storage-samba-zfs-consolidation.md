# Prompt 5 — Consolidate Mercury Storage, ZFS, Samba, and Permissions

Review `hosts/mercury/{disko.nix,storage-pool.nix,disko-zfs.nix,sanoid.nix,samba-shares.nix,outbox-sync.nix,minecraft-backup.nix,configuration.nix}` as one storage subsystem. Propose a source of truth for dataset names, mountpoints, compression/recordsize, snapshot policy, share names, permissions, and mount-dependent permission actions.

Safety constraints: do not run disko or format/create/destroy disks/pools; do not change any `/dev/disk/by-id`, rename/move datasets, change `system.stateVersion`, widen accounting permissions, or alter Drive deletion behavior without approval. This is live-data infrastructure; any static refactor must be migration-free.

Check every Samba path against the declared datasets, reconcile the `Shop-Outbox` exposure comment, and ensure accounts can do intended operations while private data stays private. Consolidate tmpfiles/mount ordering without changing permissions on bare mountpoints if ZFS is unavailable. Deliver a migration-free patch and any separate migration proposal for human review. State exact validation and remaining runtime tests.
