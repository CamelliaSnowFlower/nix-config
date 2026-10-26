# Sticker automation prerequisites on Uranus

This module uses Mercury's five asset Samba shares configured in `hosts/mercury/samba-shares.nix`, plus `Shop-Outbox` from `hosts/mercury/outbox-sync.nix`:

- `//192.168.1.80/Shop-Designs`
- `//192.168.1.80/Shop-Assets`
- `//192.168.1.80/Shop-3DModels`
- `//192.168.1.80/Shop-Videos`
- `//192.168.1.80/Shop-Accounting`\n- `//192.168.1.80/Shop-Outbox` (production output, mirrored one-way to Google Drive)

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

Set `WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` to the HTTPS hostname Tailscale gives Uranus. For predictable credential encryption, you can generate `N8N_ENCRYPTION_KEY` with `openssl rand -hex 32` and place it in this file before the first n8n start. If n8n has already generated its key in `/var/lib/n8n-sticker`, do not add a different key later; leave the persisted key in place. Do not put either secret file in Git or the Nix store.

## Apply

From the configuration repository on Uranus:

```sh
sudo nixos-rebuild switch --flake .#uranus
home-manager switch --flake .#aquarius@uranus
```

Check initial share status:

```sh
systemctl status mercury-smb-mounts.service
cat /run/mercury-smb-mounts.status
systemctl status podman-n8n-sticker.service
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
├── outbox/                 # SMB mount of Mercury's Shop-Outbox
│   ├── ABC000/             # committed sticker files, flat by SKU
│   └── .staging/           # temporary jobs; excluded from Google Drive sync
└── scripts/                # fixed, reviewed wrapper scripts mounted read-only

/var/lib/sticker-automation/ # workflow registry/state
/var/lib/n8n-sticker/        # persistent n8n database and credentials
```

n8n sees the useful sticker sources under `/data/assets/Shop-Assets` and `/data/assets/Shop-Designs`; committed and staged production files are under `/data/outbox/`. The outbox is Mercury's `/mnt/storage/outbox` dataset, exposed as the `Shop-Outbox` share. Mercury's `outbox-sync.nix` mirrors committed outbox content to Google Drive; its rclone command excludes `/.staging/**`, so unapproved work is not published. The other asset shares are mounted for the host but are not exposed to the n8n container.

The SMB mount service attempts every share before reporting failure. If any share fails, normal boot continues, but the n8n container is blocked. A Home Manager user unit displays a GNOME notification in the graphical session (including after login if the failure happened before login), and a timer retries mounts every five minutes. If they all recover, it starts n8n automatically. The sticker-processing and nesting wrapper scripts and the n8n workflow graph still need to be added/tested as a separate implementation stage.

## Google Drive integration on Mercury

The latest config imports `./outbox-sync.nix` from `hosts/mercury/configuration.nix`, so the `Shop-Outbox` Samba share and hourly one-way Drive sync are enabled. Before switching Mercury, follow the OAuth/rclone setup documented in `hosts/mercury/outbox-sync.nix`. The sync service is guarded by a mountpoint check and a delete limit; do a manual dry/test run with a disposable file before relying on it. Never remove the `.staging` exclusion: the sticker workflow uses that directory for in-progress jobs.
