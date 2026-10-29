#!/usr/bin/env bash
# dev.sh - one entry point for testing this config. Never switches, never
# uses sudo, never touches disks or remote data.
#
#   ./dev.sh              checks + build + diff for this host (default: uranus)
#   ./dev.sh check        only scripts/check.sh (tests, fmt, flake eval)
#   ./dev.sh build [host] only build + diff, skipping the checks
#   ./dev.sh vm [host]    build a QEMU VM of the host and boot it
#   ./dev.sh shell        enter the dev shell
#   ./dev.sh claude       start Claude Code inside the dev shell
#
# Host defaults to this machine's hostname if it's one of ours, else uranus.
set -euo pipefail
cd "$(dirname "$0")"

NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
HOSTS="saturn uranus mercury"

default_host() {
  local h
  h="$(hostname 2>/dev/null || echo)"
  if [[ " $HOSTS " == *" $h "* ]]; then echo "$h"; else echo uranus; fi
}

require_nix() {
  if ! command -v nix >/dev/null 2>&1; then
    echo "ERROR: nix not found. Run this on a NixOS machine." >&2
    exit 1
  fi
}

in_shell() { nix "${NIX_FLAGS[@]}" develop .#default --command "$@"; }

# Flakes only see files git tracks. Stage new files (no commit) so they
# aren't silently ignored.
stage_untracked() {
  local new
  new="$(git ls-files --others --exclude-standard)"
  if [ -n "$new" ]; then
    echo "== Staging untracked files so the flake can see them (not committing):"
    echo "$new" | sed 's/^/   /'
    git ls-files -z --others --exclude-standard | xargs -0 git add --
  fi
}

do_check() {
  echo "== Running scripts/check.sh inside the dev shell"
  if ! in_shell ./scripts/check.sh; then
    echo
    echo "Checks failed. Fix the errors above, or run './dev.sh build' to skip"
    echo "the checks and only build. (A fresh 'nix fmt' failure just means files"
    echo "need formatting: run 'nix fmt' and look at the diff.)"
    exit 1
  fi
}

do_build() {
  local host="$1"
  echo "== Building $host (nothing is activated)"
  nixos-rebuild build --flake ".#$host"
  echo
  if [ "$host" = "$(hostname 2>/dev/null || echo)" ] && [ -e /run/current-system ]; then
    echo "== What would change on this machine"
    in_shell nvd diff /run/current-system ./result
  else
    echo "Built $host; skipping the diff because this machine isn't $host."
  fi
  echo
  echo "Next, when you're happy:"
  echo "  sudo nixos-rebuild test   --flake .#$host   # live, undone by reboot"
  echo "  git commit -m '...' && sudo nixos-rebuild switch --flake .#$host"
}

require_nix
cmd="${1:-all}"
case "$cmd" in
  all)
    stage_untracked
    do_check
    do_build "${2:-$(default_host)}"
    ;;
  check)
    stage_untracked
    do_check
    ;;
  build)
    stage_untracked
    do_build "${2:-$(default_host)}"
    ;;
  vm)
    host="${2:-$(default_host)}"
    stage_untracked
    nixos-rebuild build-vm --flake ".#$host"
    echo "== Booting $host VM (close the window or Ctrl-A X to quit)"
    "./result/bin/run-$host-vm"
    ;;
  shell)
    stage_untracked
    nix "${NIX_FLAGS[@]}" develop .#default
    ;;
  claude)
    stage_untracked
    if ! command -v claude >/dev/null 2>&1; then
      echo "claude isn't installed yet. Run './dev.sh', then" >&2
      echo "'sudo nixos-rebuild switch --flake .#uranus' to install it." >&2
      exit 1
    fi
    in_shell claude
    ;;
  -h | --help | help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "Unknown command: $cmd (try ./dev.sh help)" >&2
    exit 1
    ;;
esac
