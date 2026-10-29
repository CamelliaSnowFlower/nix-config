# minecraft-backup.nix
#
# Weekly backup of the sticker-shop Minecraft server's stateful data
# (world + nether + end + server configs - NOT the downloaded
# libraries/jars, which are reproducible from the Nix store and just
# waste backup space) onto the storage pool. Deliberately not exposed
# over Samba - restore is a manual/SSH job, not something to browse
# from a Windows client.
{
  config,
  pkgs,
  lib,
  ...
}: let
  serverName = "sticker-shop";
  serverDataDir = "/srv/minecraft-servers/${serverName}";
  backupDataset = "/mnt/storage/minecraft-backups";
  backupRoot = "${backupDataset}/${serverName}";
  sock = "/run/minecraft/${serverName}.sock";

  # How many past backups to keep on disk (8 weekly ~= 2 months).
  keepBackups = 8;

  # The backup logic lives in minecraft-backup.sh so it can be tested with
  # stubs (sticker/tests/test_shell_scripts.py). Paths come from the unit's
  # environment below.
  backupScript = pkgs.writeShellApplication {
    name = "minecraft-backup-${serverName}";
    runtimeInputs = with pkgs; [
      tmux
      rsync
      coreutils
      findutils
      gnugrep
    ];
    text = builtins.readFile ./minecraft-backup.sh;
  };

  # Runs as root before each backup. The backup directory is created only if
  # the ZFS dataset is really mounted, so a failed mount can never cause
  # backups to be written to (and hidden on) the root filesystem.
  prepareBackupDir = pkgs.writeShellApplication {
    name = "minecraft-backup-prepare";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    text = ''
      if ! mountpoint -q ${lib.escapeShellArg backupDataset}; then
        echo "ERROR: ${backupDataset} is not mounted; refusing to write backups to the root filesystem." >&2
        exit 1
      fi
      install -d -m 0750 -o gemini -g users ${lib.escapeShellArg backupRoot}
    '';
  };
in {
  systemd.services."minecraft-backup-${serverName}" = {
    description = "Back up Minecraft server ${serverName}";
    # ZFS datasets are mounted by zfs-mount.service, not by systemd mount
    # units, so RequiresMountsFor cannot express this; the ExecStartPre
    # check below is the real guard.
    after = ["zfs-mount.service"];
    environment = {
      BACKUP_ROOT = backupRoot;
      SERVER_DATA_DIR = serverDataDir;
      SOCK = sock;
      KEEP_BACKUPS = toString keepBackups;
    };
    serviceConfig = {
      Type = "oneshot";
      User = "gemini";
      Group = "users";
      # The "+" prefix runs the preparation step as root.
      ExecStartPre = "+${lib.getExe prepareBackupDir}";
      ExecStart = "${lib.getExe backupScript}";
    };
  };

  systemd.timers."minecraft-backup-${serverName}" = {
    description = "Weekly backup timer for ${serverName}";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-* 04:00:00";
      # Runs the backup on next boot if mercury happened to be off
      # at the scheduled time, instead of silently skipping a week.
      Persistent = true;
      # Spreads the exact run time out a bit so it's not perfectly
      # predictable/aligned with other weekly jobs.
      RandomizedDelaySec = "30m";
    };
  };
}
