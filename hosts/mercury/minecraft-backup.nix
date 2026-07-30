# minecraft-backup.nix
#
# Weekly backup of the sticker-shop Minecraft server's stateful data
# (world + nether + end + server configs - NOT the downloaded
# libraries/jars, which are reproducible from the Nix store and just
# waste backup space) onto the storage pool. Deliberately not exposed
# over Samba - restore is a manual/SSH job, not something to browse
# from a Windows client.
{ config, pkgs, lib, ... }: let
  serverName = "sticker-shop";
  serverDataDir = "/srv/minecraft-servers/${serverName}";
  backupRoot = "/mnt/storage/minecraft-backups/${serverName}";
  sock = "/run/minecraft/${serverName}.sock";

  # How many past backups to keep on disk (8 weekly ~= 2 months).
  keepBackups = 8;

  backupScript = pkgs.writeShellApplication {
    name = "minecraft-backup-${serverName}";
    runtimeInputs = [ pkgs.tmux pkgs.rsync pkgs.coreutils pkgs.findutils ];
    text = ''
      timestamp="$(date +%Y-%m-%d_%H%M%S)"
      dest="${backupRoot}/$timestamp"

      running=false
      if tmux -S "${sock}" has-session 2>/dev/null; then
        running=true
        session="$(tmux -S "${sock}" list-sessions -F '#{session_name}' | head -n1)"
        echo "Server is running - flushing world to disk before copying"
        tmux -S "${sock}" send-keys -t "$session" "save-off" Enter
        tmux -S "${sock}" send-keys -t "$session" "save-all flush" Enter
        # Give the flush a moment to actually finish writing before we
        # start copying files out from under it.
        sleep 10
      else
        echo "Server isn't running - copying world files as-is"
      fi

      mkdir -p "$dest"
      rsync -a \
        --exclude 'libraries' \
        --exclude 'cache' \
        --exclude 'logs' \
        --exclude 'crash-reports' \
        --exclude '*.jar' \
        "${serverDataDir}/" "$dest/"

      if [ "$running" = true ]; then
        tmux -S "${sock}" send-keys -t "$session" "save-on" Enter
      fi

      echo "Backup written to $dest"

      # Prune down to the newest ${toString keepBackups} backups.
      cd "${backupRoot}"
      ls -1t | tail -n "+$(( ${toString keepBackups} + 1 ))" | while read -r old; do
        echo "Pruning old backup: $old"
        rm -rf -- "$old"
      done
    '';
  };
in {
  systemd.services."minecraft-backup-${serverName}" = {
    description = "Back up Minecraft server ${serverName}";
    serviceConfig = {
      Type = "oneshot";
      User = "gemini";
      Group = "users";
      ExecStart = "${lib.getExe backupScript}";
    };
  };

  systemd.timers."minecraft-backup-${serverName}" = {
    description = "Weekly backup timer for ${serverName}";
    wantedBy = [ "timers.target" ];
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

  # dataDir root itself isn't managed by nix-minecraft (that module
  # only owns ${dataDir}/<servername>, same gap we hit with
  # /srv/minecraft-servers earlier) - own and create it here so
  # gemini (running the backup service) can write into it without
  # sudo. "d" both creates it if missing and fixes ownership/mode if
  # it already exists.
  systemd.tmpfiles.rules = [
    "d ${backupRoot} 0750 gemini users - -"
  ];

  # Same ordering requirement as the other datasets: tmpfiles runs
  # before ZFS mounts the pool unless told otherwise. The ordering
  # fix itself already lives in samba-shares.nix and applies globally
  # (systemd.services.systemd-tmpfiles-setup.after/wants merge across
  # files), so no need to repeat it here.
}
