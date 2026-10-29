# Changes in this snapshot (work stopped partway)

Nothing here was evaluated with Nix or run on a real machine. Run `scripts/check.sh` on a machine with Nix before deploying anything.

## Done
- `sticker/sticker_tool.py`: validation, ImageMagick processing, true-outline nesting, SQLite listing registry, journaled commit, reject, reprint. Tests in `sticker/tests/` (42 passing in a sandbox without Nix).
- `sticker/n8n/`: workflow exports (intake/approval, error notify). Never imported into n8n.
- `hosts/uranus/sticker-automation.nix`: packages `sticker-tool`, new SMB health check (replaces the retry script), bounded mount probes, unused scripts mount removed.
- `hosts/mercury/`: Minecraft backup rewritten (`minecraft-backup.sh`), new `storage-permissions.nix` (replaces tmpfiles rules), `outbox-sync-preview.service` (dry run).
- `hosts/uranus/ollama.nix`: Ollama requires its model bind mount.
- `home-manager/`: shared nixpkgs settings in `common/nixpkgs.nix`; duplicate option import removed; failed-run desktop notification added.
- Stale comments fixed; `docs/ACCOUNTS.md`, `scripts/check.sh`, `.github/workflows/check.yml`, `hosts/uranus/STICKER-AUTOMATION.md` updated.
- Prompts removed: 01 (duplicate of AGENTS.md), 03, 07, 08 (done). Restore with `git checkout HEAD -- prompts/`.

## Not done
- `README.md`, `TODO.md`, and `CODE_REVIEW.md` were NOT updated and still describe the old state (for example, they say the sticker scripts are missing).
- Open decisions and checks remain in `TODO.md`: port 7125, Odysseus/ChromaDB image pins, Shop-Accounting write access, root SSH, ACS override, mandatory shares, secrets check, Nix evaluation, `nix fmt`.

## Dev environment and Claude Code (added after the snapshot above)
Also not evaluated with Nix; `./dev.sh` is the way to check it.
- `modules/nixos/claude-code.nix` (exported as `nixosModules.claude-code`) and `hosts/uranus/claude-code.nix` enabling it on uranus. No unfree allowance in the module because `hosts/common.nix` already allows unfree.
- `devshell.nix` + `devShells.x86_64-linux.default` in `flake.nix`: nixd, alejandra, statix, deadnix, nvd, plus shellcheck, ImageMagick, and Python with numpy/Pillow so `scripts/check.sh` runs inside it.
- `dev.sh`: one entry point for check / build / diff / VM / shell / claude. Never switches.
- `CLAUDE.md`, `.claude/settings.json`, `.envrc`, `docs/DEVELOPMENT.md`.
