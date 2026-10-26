# Prompt 8 — Add Non-Destructive CI and Quality Checks

Add practical checks for formatting, flake metadata/evaluation, `saturn`/`uranus`/`mercury` toplevel evaluation, all Home Manager activation outputs, the Minecraft package attribute, and shell/script tests. Use the current `flake.lock`; do not update inputs as a side effect.

CI must never run `nixos-rebuild switch`, `nixos-anywhere`, disko, `mkfs`, `zpool create/destroy`, `rclone sync` against production, or commands mutating live hosts. Separate pull-request checks from manual hardware/service tests. Make the job fail on missing package attributes, formatting differences, or shell wrapper failures. Document prerequisites and ensure secrets are never emitted in logs.

Deliver the CI/check script and local invocation. Validate the workflow itself. If Nix is unavailable, do not claim the checks passed; list the commands the owner needs to run.
