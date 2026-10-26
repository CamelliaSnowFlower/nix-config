# Prompt 7 — Consolidate Backup, Sync, and Sticker Job Reliability

Review the Minecraft backup script, Google Drive outbox sync, SMB mount/retry/notification services, and planned sticker pipeline. Identify common reliability needs and implement a small shared convention for bounded retries, status reporting, temporary output, atomic publication, cleanup traps, validation, retention, and actionable logs.

Required behavior:
- Minecraft must attempt `save-on` on every exit after `save-off`; only complete backups count toward retention.
- `rclone sync` must have a genuine preview/dry-run procedure and clear delete accounting. Preserve the mount guard, delete limit, and `.staging` exclusion.
- SMB checks must detect loss/staleness after a successful mount; n8n must not process with missing required shares, without blocking normal system boot.
- Sticker jobs reserve IDs transactionally, stage on the same filesystem as final output, recover safely from crashes, exclude staged files from Drive, and reprint from exact saved placement coordinates.
- Uploaded filenames/customer text must never become shell syntax. Wrappers consume server-generated job IDs and validated manifests.

Do not build a generic framework if simple scripts will suffice. Propose tests before code: concurrency, permissions, network disconnect, partial copy, backup failure, Drive delete preview, rejection rollback, and process restart. Use disposable fixtures. Never test deletion against the real Drive target without explicit human authorization.
