# storage-permissions.nix
#
# One place that sets ownership and mode on the root directory of each ZFS
# dataset shared over Samba. disko-zfs creates datasets as root:root 0755, and
# Samba's "force group" / "force create mode" settings only affect files made
# *inside* a share, never the share's own root. Without this, a new or freshly
# recreated share starts out unwritable by the users group.
#
# This replaces the earlier systemd-tmpfiles `z` rules (and the global
# systemd-tmpfiles-setup ordering override that supported them). tmpfiles runs
# early in boot, so it needed a workaround to wait for the ZFS pool. A normal
# service orders itself after zfs-mount.service, checks each path really is a
# mounted dataset, and reports a failed unit when one is not, instead of
# silently touching a bare mountpoint directory.
#
# Shop-Accounting is deliberately NOT listed: it stays root-owned and private
# (see the open decision in TODO.md about its Samba write access).
#
# 2775 = group-writable plus setgid, so anything created directly at a dataset
# root inherits the "users" group.
{
  lib,
  pkgs,
  ...
}: let
  managed = [
    {
      path = "/mnt/storage/shop-designs";
      owner = "root";
      group = "users";
      mode = "2775";
    }
    {
      path = "/mnt/storage/shop-assets";
      owner = "root";
      group = "users";
      mode = "2775";
    }
    {
      path = "/mnt/storage/shop-3d";
      owner = "root";
      group = "users";
      mode = "2775";
    }
    {
      path = "/mnt/storage/shop-videos";
      owner = "root";
      group = "users";
      mode = "2775";
    }
    {
      # Shop-Outbox: finished-goods output, shared over Samba in
      # samba-shares.nix (admin-only, reachable over the LAN and Tailscale).
      path = "/mnt/storage/outbox";
      owner = "root";
      group = "users";
      mode = "2775";
    }
    {
      # Shop-Inbox. Group is "artists", not "users" - artist accounts stay
      # scoped to this one share (see configuration.nix, samba-shares.nix).
      path = "/mnt/storage/shop-inbox";
      owner = "root";
      group = "artists";
      mode = "2775";
    }
  ];

  applyScript = pkgs.writeShellApplication {
    name = "apply-storage-permissions";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    text = ''
      failed=0

      apply() {
        if ! mountpoint -q "$1"; then
          echo "ERROR: $1 is not a mounted dataset; leaving it untouched." >&2
          failed=1
          return 0
        fi
        chown "$2:$3" "$1"
        chmod "$4" "$1"
        echo "Set $1 to $2:$3 mode $4"
      }

      ${lib.concatMapStringsSep "\n" (
          entry: "apply ${lib.escapeShellArg entry.path} ${entry.owner} ${entry.group} ${entry.mode}"
        )
        managed}

      exit "$failed"
    '';
  };
in {
  systemd.services.storage-permissions = {
    description = "Set ownership and mode on shared ZFS dataset roots";
    wantedBy = ["multi-user.target"];
    after = ["zfs-mount.service"];
    wants = ["zfs-mount.service"];
    # Ordering only: Samba and the sync still start if this unit fails, using
    # the permissions already stored on the datasets.
    before = [
      "samba-smbd.service"
      "outbox-sync.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe applyScript}";
    };
  };
}
