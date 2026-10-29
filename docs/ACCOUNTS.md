# Accounts, groups, SSH, and profiles

A snapshot of who can do what on each machine, taken from the Nix files in this
repository (not from a live system). Update it in the same change whenever a
user, group, SSH key, or Home Manager profile changes. Host-specific privileges
are listed explicitly so a consolidation refactor cannot quietly change them.

## Hosts and accounts

| Host | Account | Kind | Groups | Home Manager output | SSH / access notes |
| --- | --- | --- | --- | --- | --- |
| saturn | `aquarius` | normal user | `networkmanager`, `wheel` | `aquarius@saturn` | Defined in `hosts/saturn/configuration.nix`. |
| saturn | `camelliasnowflower` | normal user | `networkmanager`, `wheel` | none | Admin account without a Home Manager output. |
| uranus | `aquarius` | normal user | `networkmanager`, `wheel`, `libvirtd` | `aquarius@uranus` | `libvirtd` comes from `hosts/uranus/windows-vm.nix`. UID is assumed to be 1000 by the sticker SMB mounts and the n8n container. |
| uranus | `camelliasnowflower` | normal user | `networkmanager`, `wheel` | none | Admin account without a Home Manager output. |
| uranus | `ollama` | system user | `ollama` | none | Runs the Ollama service; owns the model directory. |
| mercury | `gemini` | normal user | `networkmanager`, `wheel` | `gemini@mercury` | Has an authorized SSH key. Runs the Minecraft server and its weekly backup. |
| mercury | `root` | root | n/a | none | Has an authorized SSH key (direct root SSH). Whether to keep this is an open decision. |
| mercury | `aquarius` | normal user | `users` | none | Samba access only: no `wheel`, no SSH key. Admin on all Shop-* shares, including pull access on Shop-Inbox. |
| mercury | `gubby` | normal user | `users` | none | Samba access only: no `wheel`, no SSH key. Admin on all Shop-* shares, including pull access on Shop-Inbox. |
| mercury | `artist-example` | normal user | `artists` | none | Samba access only: no `wheel`, no SSH key. Placeholder for external artists dropping files into Shop-Inbox over Tailscale - rename/add one block per real artist (see `hosts/mercury/configuration.nix`). Scoped to Shop-Inbox only via `valid users` in `samba-shares.nix`. |

Mercury also has the `minecraft-servers` module configured to run as `gemini:users`.

SSH is enabled on uranus and mercury (`services.openssh.enable`). Mercury also joins the tailnet (`hosts/mercury/tailscale.nix`), which is how artist accounts and remote admin pulls reach it without opening Samba to the public internet; the Google Drive outbox sync that used to run here (via a `rclone-sync` service account) has been removed.

## Home Manager profiles

Profiles are declared in `home-manager/options.nix`. Both users import
`home-manager/common` (which owns the option declarations and the shared
nixpkgs settings) and `home-manager/optional`.

| Profile | `aquarius` (saturn, uranus) | `gemini` (mercury) |
| --- | --- | --- |
| photography | on | off |
| coding | on | on |
| sysadmin | on | on |
| desktop | on | off |
| unstable | on | off |

`aquarius@saturn` and `aquarius@uranus` are the same configuration built twice
(`mkHome "aquarius"` in `flake.nix`), so anything in `home-manager/aquarius/`
applies to both machines. Desktop-notification units for the sticker system are
inert on saturn because the files they watch exist only on uranus.

## Things to keep explicit

- Do not widen `wheel` membership, add SSH keys, or change Samba-only accounts
  as a side effect of a refactor.
- Shop-Accounting is mounted on uranus with private modes (`0600`/`0700`) and is
  not visible to the n8n container.
- Samba passwords are set with `smbpasswd -a <user>` on mercury and are never
  stored in this repository.
