# outbox-sync.nix
#
# Pushes /mnt/storage/outbox (the storage/outbox ZFS dataset from
# disko-zfs.nix) one-way to a Google Drive folder on a timer. Outside
# collaborators get access through Drive's own sharing, so mercury never
# accepts a connection from the internet - it only makes outbound ones.
#
# Design notes:
#   - One-way `rclone sync`: Drive can never write back to mercury, and
#     deleting a file from the outbox removes it from Drive on the next
#     run (deleted files land in Drive's trash).
#   - The local .staging directory is excluded so incomplete sticker jobs
#     are never exposed through Google Drive before approval/commit.
#   - rclone is limited to the `drive.file` scope, so even if the token
#     leaks it can only touch files rclone itself created - not the rest
#     of your Google Drive.
#   - The OAuth token lives in /var/lib/rclone/rclone.conf (root-only
#     home of the rclone-sync user), NOT in the Nix store, which is
#     world-readable.
#   - Safety nets: the service refuses to run if the outbox isn't
#     actually mounted (an empty mountpoint would otherwise make rclone
#     delete everything on Drive), and --max-delete aborts a run that
#     would delete more than 100 files.
#
# =====================================================================
# FIRST-TIME SETUP
# =====================================================================
#
# 0. Add this file to the imports in hosts/mercury/configuration.nix:
#        ./outbox-sync.nix
#    Make sure the storage/outbox dataset from the updated
#    disko-zfs.nix is in your config too.
#
# 1. Create a Google OAuth client (one time, in a browser):
#      a. https://console.cloud.google.com -> create a new project.
#      b. APIs & Services -> Library -> enable "Google Drive API".
#      c. APIs & Services -> OAuth consent screen: User type "External",
#         fill in the app name and your email, and add your own Google
#         account as a test user.
#      d. IMPORTANT: on the consent screen, click "Publish app" (move it
#         from "Testing" to "In production"). As far as I know, tokens
#         for apps left in Testing expire after 7 days, which would
#         silently break the sync every week. The drive.file scope is
#         non-sensitive, so no Google review is needed for personal use.
#      e. APIs & Services -> Credentials -> Create credentials ->
#         OAuth client ID -> Application type "Desktop app".
#         Copy the Client ID and Client secret.
#
# 2. Preview, then apply the config on mercury (this also creates the
#    storage/outbox dataset via disko-zfs):
#        sudo nixos-rebuild --flake .#mercury --sudo dry-activate
#        sudo nixos-rebuild switch --flake .#mercury
#    Confirm it mounted:  mountpoint /mnt/storage/outbox
#
# 3. Create the rclone remote. Run this ON mercury, as the sync user:
#        sudo -u rclone-sync rclone config --config /var/lib/rclone/rclone.conf
#    Then answer the prompts:
#        n) New remote
#        name>            gdrive            (must match `remote` below)
#        Storage>         drive             (Google Drive)
#        client_id>       <Client ID from step 1e>
#        client_secret>   <Client secret from step 1e>
#        scope>           3 / drive.file    ("access to files created
#                                            by rclone only")
#        service_account_file>  (leave blank)
#        Edit advanced config?  n
#        Use web browser to automatically authenticate rclone with
#        remote?                n           (mercury is headless)
#    rclone now prints a command that starts with `rclone authorize
#    "drive" ...`. Run that exact command on a machine WITH a browser
#    (e.g. uranus; if rclone isn't installed there, prefix with
#    `nix shell nixpkgs#rclone -c`). Sign in with the Google account
#    that should own the shared files, approve access, then paste the
#    token it prints back into the mercury prompt.
#        Configure as Shared Drive (Team Drive)?  n
#        y) Yes this is OK
#        q) Quit config
#
# 4. Preview first, then test the real sync by hand:
#        sudo systemctl start outbox-sync-preview.service
#        journalctl -u outbox-sync-preview.service -o cat
#    The preview is a dry run of the exact same command (nothing is
#    changed on Drive). Each file it would delete is logged as
#    "Skipped delete"; count them with
#        journalctl -u outbox-sync-preview.service -o cat | grep -c "Skipped delete"
#    When the preview looks right:
#        sudo systemctl start outbox-sync.service
#        journalctl -u outbox-sync.service -e
#    (Put a test file in the outbox first. An empty outbox is fine too
#    - it just creates the empty "Outbox" folder on Drive.)
#
# 5. Share it: open Google Drive in a browser, find the "Outbox" folder,
#    and share THE FOLDER with the people who need access. Share the
#    folder rather than individual files, so new files are covered
#    automatically.
#
# 6. Check the timer is scheduled:
#        systemctl list-timers outbox-sync.timer
#
# =====================================================================
# DAY-TO-DAY
# =====================================================================
#   - Copy files you want to share into \\shopnas\Shop-Outbox (or
#     /mnt/storage/outbox over SSH). They appear on Drive within the
#     hour, or immediately with:
#         sudo systemctl start outbox-sync.service
#   - To stop sharing something, delete it from the outbox.
#   - Never put anything private here (e.g. Shop-Accounting): the
#     outbox is meant to be a disposable copy of things that are safe
#     to share. The originals stay in the shop-* datasets.
#   - If syncs start failing with auth errors, re-run step 3 (or just
#     `rclone config reconnect gdrive:` as the rclone-sync user).
{
  lib,
  pkgs,
  ...
}: let
  outbox = "/mnt/storage/outbox";
  remote = "gdrive:Outbox"; # "gdrive" = remote name from step 3
  configFile = "/var/lib/rclone/rclone.conf";

  # One command line shared by the real sync and the preview, so the preview
  # always reflects exactly what the real run would do.
  syncCommand = extraArgs:
    lib.concatStringsSep " " ([
        "${pkgs.rclone}/bin/rclone"
        "sync"
        outbox
        remote
        "--config ${configFile}"
        # Sticker jobs stage beneath the outbox share so final renames are
        # same-filesystem, but unfinished work must never be mirrored to Drive.
        "--exclude /.staging/**"
        "--max-delete 100"
      ]
      ++ extraArgs);

  # Hardening - the service only needs to read the outbox, write
  # its own token refreshes, and talk to the network.
  syncServiceConfig = {
    Type = "oneshot";
    User = "rclone-sync";
    Group = "rclone-sync";

    # Refuse to run if the dataset isn't mounted: syncing an empty
    # directory would wipe everything on Drive.
    ExecStartPre = "${pkgs.util-linux}/bin/mountpoint -q ${outbox}";

    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    NoNewPrivileges = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ReadWritePaths = ["/var/lib/rclone"];
  };
in {
  environment.systemPackages = [pkgs.rclone];

  # Dedicated no-login account that only runs the sync. Its home holds
  # the rclone config/token, readable by nobody else.
  users.users.rclone-sync = {
    isSystemUser = true;
    group = "rclone-sync";
    home = "/var/lib/rclone";
    createHome = true;
    homeMode = "700";
    description = "Outbox -> Google Drive sync";
  };
  users.groups.rclone-sync = {};

  systemd.services.outbox-sync = {
    description = "Push ${outbox} to Google Drive";
    after = ["zfs-mount.service" "network-online.target"];
    wants = ["network-online.target"];
    # Don't start unless the remote has actually been configured
    # (step 3), so a fresh rebuild doesn't spam failures.
    unitConfig.ConditionPathExists = configFile;
    serviceConfig = syncServiceConfig // {ExecStart = syncCommand [];};
  };

  # Dry run of the exact same command: nothing is copied, changed, or
  # deleted on Drive. Start it by hand before trusting the timer, and again
  # before any large reorganisation of the outbox:
  #     sudo systemctl start outbox-sync-preview.service
  #     journalctl -u outbox-sync-preview.service -o cat
  # Each file rclone would remove from Drive appears as a "Skipped delete"
  # line, so a quick count is:
  #     journalctl -u outbox-sync-preview.service -o cat | grep -c "Skipped delete"
  # Nothing starts this unit automatically.
  systemd.services.outbox-sync-preview = {
    description = "Preview (dry run) of the outbox -> Google Drive sync";
    after = ["zfs-mount.service" "network-online.target"];
    wants = ["network-online.target"];
    unitConfig.ConditionPathExists = configFile;
    serviceConfig =
      syncServiceConfig
      // {
        ExecStart = syncCommand ["--dry-run" "-v" "--stats-one-line"];
      };
  };

  systemd.timers.outbox-sync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5m";
      Persistent = true; # catch up after downtime
    };
  };

  # ---------------------------------------------------------------
  # Getting files INTO the outbox: a Samba share, same pattern as the
  # Shop-* shares in samba-shares.nix. Delete this block (and the
  # /mnt/storage/outbox entry in storage-permissions.nix) if you'd
  # rather copy files in over SSH.
  # ---------------------------------------------------------------
  services.samba.settings."Shop-Outbox" = {
    path = outbox;
    browseable = "yes";
    "read only" = "no";
    "guest ok" = "no";
    "create mask" = "0664";
    "force create mode" = "0664";
    "directory mask" = "0775";
    "force directory mode" = "0775";
    "force group" = "users";
  };

  # The dataset root's ownership and mode (group-writable for "users", setgid)
  # are set by storage-permissions.nix.
}
