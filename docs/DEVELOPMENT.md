# Developing and testing this config

Everything goes through `./dev.sh`. It never uses sudo, never switches,
and never touches disks or remote data.

## One command

```sh
./dev.sh
```

This stages any untracked files (flakes ignore files git doesn't know
about; nothing is committed), runs `scripts/check.sh` inside the dev
shell (sticker/shell tests, `nix fmt --check`, `nix flake check`, and an
evaluation of every host and home), builds this machine's system without
activating it, and shows what would change with `nvd`.

## Other commands

```sh
./dev.sh check          # only the checks
./dev.sh build mercury  # only build + diff (any host: saturn, uranus, mercury)
./dev.sh vm uranus      # boot the host in a QEMU VM (GPU stuff won't match real hardware)
./dev.sh shell          # enter the dev shell (or use direnv: `direnv allow` once)
./dev.sh claude         # start Claude Code inside the dev shell
```

## Applying a change (you, not Claude)

```sh
sudo nixos-rebuild test --flake .#uranus     # live, a reboot undoes it
git commit -m "describe the change"
sudo nixos-rebuild switch --flake .#uranus   # permanent
sudo nixos-rebuild switch --rollback         # undo; or pick an older generation at boot
```

## Tidy-up tools (inside the dev shell)

```sh
nix fmt         # format everything with alejandra
statix check    # lint
deadnix         # unused code
```

## Claude Code setup

`CLAUDE.md` loads `AGENTS.md`. `.claude/settings.json` lets Claude run
the checks, builds, and diffs on its own, and blocks `sudo`,
`nixos-rebuild test/switch/boot`, `nixos-anywhere`, disko, `zpool`, and
`rclone`.
