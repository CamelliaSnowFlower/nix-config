#!/usr/bin/env bash
# Non-destructive checks for this repository.
#
# This script never deploys, switches, formats disks, imports pools, mutates
# remote data (Google Drive), or restarts services. It only reads the repo,
# runs the Python/shell tests in disposable directories, and (when Nix is
# available) evaluates the flake without building host systems.
#
#   scripts/check.sh
#
# Without Nix the evaluation steps are skipped with a loud warning. That is
# NOT a pass: evaluate on a Nix machine before deploying. In CI (CI=true) a
# missing Nix is an error.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Python tests (sticker tool, shell scripts, n8n exports)"
python3 -m unittest discover -s sticker/tests -v

echo "== Shell syntax"
bash -n hosts/mercury/minecraft-backup.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck hosts/mercury/minecraft-backup.sh
else
  echo "shellcheck not found; skipping (the Nix build also runs it on writeShellApplication scripts)"
fi

if ! command -v nix >/dev/null 2>&1; then
  if [ "${CI:-}" = "true" ]; then
    echo "ERROR: nix is required in CI." >&2
    exit 1
  fi
  echo
  echo "WARNING: nix was not found. Flake evaluation, formatting, and the Minecraft"
  echo "package check were NOT run. Run this script again on a machine with Nix"
  echo "before deploying any host."
  exit 0
fi

echo "== Formatting (alejandra via the flake's formatter)"
nix fmt -- --check .

echo "== Flake check"
nix flake check --show-trace

echo "== Evaluate NixOS hosts (no build)"
for host in saturn uranus mercury; do
  nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath"
  echo
done

echo "== Evaluate Home Manager outputs (no build)"
for name in aquarius@saturn aquarius@uranus gemini@mercury; do
  nix eval --raw ".#homeConfigurations.\"${name}\".activationPackage.drvPath"
  echo
done

echo "== Minecraft package attribute at the locked input revision"
nix eval ".#nixosConfigurations.mercury.pkgs.minecraftServers" --apply builtins.attrNames

echo "All checks passed."
