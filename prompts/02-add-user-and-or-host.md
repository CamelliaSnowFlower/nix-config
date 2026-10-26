# Prompt 2 — Add a User and/or Host

Review this repository and implement the following addition:

- Request type: `[new user / new host / both]`
- User name and role: `[fill in]`
- Target host name and role: `[fill in]`
- Hardware/architecture: `[fill in; do not guess]`
- Login method: `[local / SSH / both / service-only]`
- Privileges: `[wheel/sudo, networking, storage, Samba, libvirt, Podman, etc.]`
- Home Manager profile and feature profiles: `[fill in]`
- SSH access policy: `[fill in; public key only if supplied]`
- `stateVersion` for a genuinely new installation: `[confirm explicitly]`

First inspect `flake.nix`, host configurations, `hosts/common.nix`, host modules, `home-manager/options.nix`, both Home Manager profile roots, and existing account definitions. Explain which files need to change before patching. Add the smallest amount of reusable structure needed; do not over-generalize one-off hardware settings.

Requirements: add all needed flake outputs/imports; add/reuse a Home Manager profile; keep username and homeDirectory consistent; choose system vs user packages deliberately; apply only requested groups/privileges; add SSH public keys only when supplied and only to intended accounts; preserve existing users, host behavior, and all existing state versions. For new hardware, require a separately generated hardware configuration—never copy another machine's UUIDs or disk IDs. Never format disks or switch a host while implementing.

Validate with formatting, `nix flake check`, the new host's `system.build.toplevel.drvPath`, its Home Manager activation package if applicable, and a diff review of privilege changes. If validation cannot run, list the exact commands still required and every unresolved assumption.
