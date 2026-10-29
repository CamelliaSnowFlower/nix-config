# Sticker automation prerequisites on Uranus

This module uses Mercury's six Samba shares, all configured in `hosts/mercury/samba-shares.nix`:

- `//192.168.1.80/Shop-Designs`
- `//192.168.1.80/Shop-Assets`
- `//192.168.1.80/Shop-3DModels`
- `//192.168.1.80/Shop-Videos`
- `//192.168.1.80/Shop-Accounting`
- `//192.168.1.80/Shop-Outbox` (production output; admins pull it over the LAN or Tailscale - see `hosts/mercury/tailscale.nix`)

The IP matches the Mercury address already used by `home-manager/common/sysadmin.nix`. Change `mercuryAddress` in `sticker-automation.nix` if Mercury's IP changes.

## Secrets (kept outside the Nix store and repo)

The NixOS module creates empty, root-only files if they do not exist. Before relying on the service, fill them in:

```sh
sudoedit /etc/nixos/secrets/mercury-smb-credentials
```

Use the Samba user configured on Mercury, for example:

```ini
username=aquarius
password=REPLACE_WITH_THE_SAMBA_PASSWORD
domain=WORKGROUP
```

Then edit the n8n environment file:

```sh
sudoedit /etc/nixos/secrets/n8n-sticker.env
```

Set `N8N_WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` to the HTTPS hostname Tailscale gives Uranus, and set `N8N_PROXY_HOPS=1` because Tailscale Serve is a single reverse-proxy hop in front of n8n. `WEBHOOK_URL` is the older name for `N8N_WEBHOOK_URL`; recent n8n releases treat it as a deprecated alias, so use the new name with the pinned n8n 2.44.7 image. After the first start, check `journalctl -u podman-n8n-sticker.service` for deprecation warnings, and open the Form Trigger URL from a Tailscale-connected client to confirm it shows the `https://` tailnet hostname. n8n expects the last proxy to pass `X-Forwarded-For`, `X-Forwarded-Host`, and `X-Forwarded-Proto`; this guide has not confirmed that Tailscale Serve sends all three, so treat that URL test as the check. For predictable credential encryption, you can generate `N8N_ENCRYPTION_KEY` with `openssl rand -hex 32` and place it in this file before the first n8n start. If n8n has already generated its key in `/var/lib/n8n-sticker`, do not add a different key later; leave the persisted key in place. Do not put either secret file in Git or the Nix store.

## Apply

From the configuration repository on Uranus:

```sh
sudo nixos-rebuild switch --flake .#uranus
home-manager switch --flake .#aquarius@uranus
```

The sticker tool lives in `sticker/` and is read by the Nix build, so make sure it is tracked by Git first (flakes ignore untracked files): `git add sticker/`.

Check initial share status:

```sh
systemctl status mercury-smb-mounts.service
cat /run/mercury-smb-mounts.status
systemctl status podman-n8n-sticker.service
systemctl status mercury-smb-retry.timer
```

If Tailscale has not been authenticated on Uranus yet, run `sudo tailscale up` once. Then publish the loopback-only n8n listener through Tailscale Serve:

```sh
sudo tailscale serve --bg http://127.0.0.1:5678
sudo tailscale serve status
```

The host listens on `127.0.0.1:5678` only; do not add router port forwards or enable Tailscale Funnel. If Serve is already configured for another service on Uranus, review its status and use a non-conflicting Serve configuration before applying the command above.

## File layout

```text
/srv/sticker-automation/
├── assets/
│   ├── Shop-Designs/       # SMB mount, n8n read-only
│   ├── Shop-Assets/        # SMB mount, n8n read-only
│   ├── Shop-3DModels/      # SMB mount, host only
│   ├── Shop-Videos/        # SMB mount, host only
│   └── Shop-Accounting/    # SMB mount, host only; private mount modes
└── outbox/                 # SMB mount of Mercury's Shop-Outbox
    ├── ABC000/             # committed sticker files, flat by SKU
    └── .staging/           # in-progress jobs and reprints

/var/lib/sticker-automation/ # SQLite registry, uploads in flight, optional config.json, last-error.json
/var/lib/n8n-sticker/        # persistent n8n database and credentials
```

Inside the container these appear as `/data/outbox`, `/data/assets/...`, and `/data/state`. The outbox is Mercury's `/mnt/storage/outbox` dataset, exposed as the `Shop-Outbox` share; admins pull finished output directly from it (LAN or Tailscale), with no separate external mirror. The other asset shares are mounted for the host but are not exposed to the n8n container.

## The sticker tool

All processing is done by one command, `sticker-tool` (source: `sticker/sticker_tool.py`, tests: `sticker/tests/`). It uses only ImageMagick, NumPy, and Pillow. It has no network access and **never uses AI to generate or alter artwork**: the only changes to art are resizing, background detection, and adding a border.

| Command | What it does |
| --- | --- |
| `mkincoming --exec-id N` | Creates the folder n8n writes an upload into. |
| `intake --exec-id N` | Validates the upload, reserves the next listing number, stages `<SKU>_source.png/.jpg`. |
| `process --job J` | Builds each finished sticker: crop, resize to the requested size at 300 dpi, solid silhouette (holes filled), border, transparent background. |
| `nest --job J [--profile P]` | Packs copies of the sticker onto each requested sheet using the real outline (not the bounding box), renders the sheet PNGs, previews, and `layout.json`. |
| `note-approval --job J --url U` | Saves the approval link beside the staged files. |
| `commit --job J` | Publishes the staged files into `ABC000` with a journal. Restartable after a crash. Never overwrites a file. |
| `reject --job J` | Deletes the staged job and releases its listing number. Refuses once a commit has started. |
| `reprint --sku S --sheet X` | Re-renders a sheet from the saved placement coordinates into `.staging/reprints/`, and reports whether it matches the saved sheet byte for byte. |
| `status [--job J]` | Shows one job or all jobs. |
| `record-error --exec-id N --node NAME` | Records a failed run for the desktop notification. |

Run it by hand from the host with `sudo podman exec n8n-sticker sticker-tool status`.

### How a job moves

1. **Form.** Upload one or more PNG/JPG files, the sticker size, the sheet types, and an optional quantity. Each file becomes one variation of one **new listing**.
2. **Naming.** The listing number is one more than the highest listing number known to the registry or found in `ABC000`. Variations are numbered `V001`, `V002`, ... in upload order. A database transaction is the single allocator, so simultaneous submissions cannot collide. Files added to `ABC000` by hand are respected.
3. **Staging.** Everything is built in `outbox/.staging/<job>/`. The staged folder is visible over Samba (including preview JPGs and `APPROVAL-LINK.txt`) to anyone with Shop-Outbox access (admins only).
4. **Approval.** The workflow pauses on a form with four choices: approve and publish, re-run with a wider gap, re-run with more rotations, or reject. Re-runs reuse the same staged job.
5. **Commit.** Approved files are moved into `ABC000` in a fixed order with the finished sticker last. A journal makes the commit safe to repeat after a crash or restart. Staging is removed afterwards.
6. **Cricut.** Opening the sheet in Cricut Design Space, printing, and cutting stay manual.

Each committed SKU is stored flat as:

```text
ABC008V001.png            finished sticker (artwork + white border, transparent outside)
ABC008V001_source.png     the original upload (.png or .jpg, as submitted)
ABC008V001_layout.json    saved placements for every requested sheet
ABC008V001_letter.png     sheet(s)
ABC008V001_tabloid.png
```

### Assumptions to confirm (these are defaults, not facts about your setup)

Override any of them by creating `/var/lib/sticker-automation/config.json`; it is merged over the defaults in `sticker_tool.py`.

- **Printable area.** `sticker/boundaries/letter.png` and `tabloid.png` are Cricut print-then-cut templates defining each sheet's real printable shape (confirmed: 7.44 x 9.94 in for "letter" media, 9.94 x 15.94 in for "tabloid" -- smaller than standard paper, and not a uniform margin). `margin_in` in `DEFAULT_CONFIG["sheets"]` is only a fallback if a mask image is missing. To use different media, replace the PNG (or point `"mask"` at a new file) with an image whose colored/opaque area marks what's printable.
- **Size.** The requested size is the longest edge of the artwork before the border is added.
- **Border.** The border grows the silhouette by 10 px at 300 dpi on every side.
- **Gap.** 1/16 in between neighbouring stickers (1/8 in for the "wider gap" re-run).
- **Background cutoff.** 0.996 brightness for PNGs without transparency; the JPEG cutoff (0.97) and its small noise filter are starting guesses and need tuning against real JPEGs.
- **One size per submission.** Every file in one form submission uses the same size.
- **Variations.** If one submission has M files, they become `V001` to `V00M` of one listing.

### Packing results

On synthetic test shapes at default settings, the true-outline packing fit about 14% more copies than a plain grid for a five-point star on a letter sheet and about 41% more on tabloid. A circle gained little (26 vs 24 on letter), because the greedy placement does not find the offset-row arrangement circles need. Gains depend heavily on the sticker's shape; test with your real art before relying on a number.

## Import and test the workflows

1. In n8n, import `sticker/n8n/sticker-error.workflow.json` first, then `sticker/n8n/sticker-job.workflow.json`.
2. In the job workflow's settings, set **Error Workflow** to "Sticker error notify".
3. These files were generated without access to a running n8n. Open each node and confirm its settings (especially the Form Trigger fields, the Wait node form, and the Switch rules), then activate the workflow.
4. Test with disposable art: submit one file, approve, and confirm the five files appear in `ABC000`. Then submit again and reject it, confirm the number is reused, and finally run `reprint` and confirm `matches_saved_sheet` is true.

The workflow only runs fixed `sticker-tool` subcommands. A repository test (`sticker/tests/test_workflows.py`) checks that every command in the exported JSON parses against the tool's real arguments and uses only allow-listed expressions.

## Trust boundary for Execute Command

The workflow needs n8n's Execute Command node, which is a shell inside the container.

- **Who can use it.** Anyone who can edit workflows in n8n can run arbitrary commands as the container's `node` user (UID 1000). That user can read the Nix store, write to the outbox and state directories, and read the n8n data. Keep n8n accounts to people you trust with that.
- **Network.** n8n listens on loopback only and is reached through Tailscale Serve. Do not enable Funnel or add router port forwards.
- **Fixed commands.** The shipped workflows call only `sticker-tool` subcommands with server-generated ids (an execution id, a job id) and fixed choices. Customer text (original filenames, notes) is written to `request.json` by n8n and parsed and validated by the tool; it never appears on a command line.
- **The whole Nix store is mounted read-only into the container** so the tools' libraries resolve. That is wider than strictly necessary. Narrowing it to the tool's closure would need a build-time list of store paths; this has not been done. Never put secrets in the Nix store.
- **Evaluated alternative.** A separate processing worker (a small local service with fixed endpoints) would let Execute Command be disabled entirely. It is a larger build and is not implemented; revisit it if more people need n8n editor access.

## Share health check and recovery

The SMB mount service attempts every share before reporting failure. If any share fails, normal boot continues but the n8n container is blocked.

Every five minutes `mercury-smb-retry.service` checks each required share: mounted, from the expected source, and answering a bounded directory listing. A stale or missing share is lazily unmounted and the mount service is restarted (which also restarts n8n, since it requires the mounts). If a share is still unhealthy, the status file says so, n8n is stopped, and the unit is marked failed so it shows up in `systemctl --failed`. When everything is healthy again, n8n is started. All six shares are currently required; whether that should change is an open decision in `TODO.md`.

If n8n is stopped in the middle of a commit, run the same `commit` again after it returns: it resumes from its journal.

Two desktop notifications appear in the GNOME session: one for share problems and one for failed workflow runs.

## Remote access to Mercury's shares

Mercury no longer mirrors `Shop-Outbox` to Google Drive (that sync was removed - it was unreliable on Google's end). Instead `hosts/mercury/tailscale.nix` joins Mercury to the tailnet, so admins can reach `Shop-Outbox` (and the other business shares) directly over Tailscale as well as the LAN. See that file for setup, and `hosts/mercury/samba-shares.nix` for the per-share `valid users` restrictions.

The same tailnet also carries `Shop-Inbox`, a separate drop-off share external artists use to submit art - see the comments in `hosts/mercury/tailscale.nix` and `hosts/mercury/samba-shares.nix` for how artist accounts are scoped to that one share only.

## Running the tests

```sh
scripts/check.sh            # everything that can run without a Nix evaluation
python3 -m unittest discover -s sticker/tests -v   # just the Python tests
```

The Python tests need ImageMagick, NumPy, and Pillow. They use disposable directories only. They do not replace evaluating the flake or testing against the real shares.

## Known limitations

- No Nix tooling was available when this was written, so none of the `.nix` changes were evaluated, and the n8n exports have not been imported into a running n8n.
- Cut paths for Cricut print-then-cut come from the transparent outline of the sheet PNG imported into Design Space; registration marks are Design Space's job.
- Non-90-degree rotations use bicubic resampling, so a reprint is byte-identical only with the same Pillow version. `reprint` reports whether it matched.
