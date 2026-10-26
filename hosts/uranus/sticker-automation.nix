# Sticker automation on Uranus.
#
# Mercury's asset shares are mounted beneath assets/, while generated
# production files and staging are stored in Mercury's Shop-Outbox share.
# Shop-Outbox is mirrored one-way to Google Drive by Mercury's outbox-sync
# service; the .staging directory is excluded from that sync. n8n is bound
# to loopback and can only be reached remotely through Tailscale Serve.
{
  config,
  lib,
  pkgs,
  ...
}: let
  mercuryAddress = "192.168.1.80"; # Also used by home-manager/common/sysadmin.nix.
  credentialsFile = "/etc/nixos/secrets/mercury-smb-credentials";
  n8nEnvironmentFile = "/etc/nixos/secrets/n8n-sticker.env";

  assetShares = [
    "Shop-Designs"
    "Shop-Assets"
    "Shop-3DModels"
    "Shop-Videos"
    "Shop-Accounting"
  ];
  # Mercury's Google Drive-synced outbox is the production output location.
  # Keep staging beneath it so commit renames stay on the same SMB filesystem;
  # outbox-sync.nix excludes .staging from the Google Drive mirror.
  shares = assetShares ++ ["Shop-Outbox"];

  stickerTools = pkgs.buildEnv {
    name = "sticker-automation-tools";
    paths = [
      pkgs.imagemagick
      (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
        numpy
        pillow
        shapely
      ]))
    ];
    pathsToLink = [ "/bin" ];
  };

  mountMercuryShares = pkgs.writeShellApplication {
    name = "mount-mercury-smb-shares";
    runtimeInputs = with pkgs; [
      coreutils
      cifs-utils
      gnused
      util-linux
    ];
    text = ''
      status_file=/run/mercury-smb-mounts.status
      status_tmp="$(mktemp /run/mercury-smb-mounts.status.XXXXXX)"
      failures=""
      mounted=""

      # Publish one complete status update only after every share has been
      # attempted. The GNOME-side watcher listens for this file.
      publish_status() {
        printf '%s\n' "$@" > "$status_tmp"
        chmod 0644 "$status_tmp"
        mv -f "$status_tmp" "$status_file"
      }

      for share in ${lib.escapeShellArgs shares}; do
        if [ "$share" = "Shop-Outbox" ]; then
          target="/srv/sticker-automation/outbox"
        else
          target="/srv/sticker-automation/assets/$share"
        fi
        source="//${mercuryAddress}/$share"
        mkdir -p "$target"

        if mountpoint -q "$target"; then
          current_source="$(findmnt -rn -o SOURCE --target "$target" 2>/dev/null || true)"
          if [ "$current_source" = "$source" ]; then
            echo "Already mounted: $source -> $target"
            mounted="$mounted $share"
          else
            echo "ERROR: $target is mounted from '$current_source', not '$source'." >&2
            failures="$failures $share"
          fi
          continue
        fi

        case "$share" in
          Shop-Accounting)
            permission_options="file_mode=0600,dir_mode=0700"
            ;;
          *)
            permission_options="file_mode=0664,dir_mode=0775"
            ;;
        esac

        mount_options="credentials=${credentialsFile},vers=3.1.1,iocharset=utf8,uid=1000,gid=100,noserverino,$permission_options"
        echo "Mounting $source at $target"
        if timeout --kill-after=5s 35s mount -t cifs "$source" "$target" -o "$mount_options"; then
          mounted="$mounted $share"
          echo "Mounted: $share"
        else
          echo "ERROR: Failed to mount $share; continuing with remaining shares." >&2
          failures="$failures $share"
        fi
      done

      if [ -n "$failures" ]; then
        publish_status \
          "status=failed" \
          "failed_shares=$(printf '%s' "$failures" | sed 's/^ *//')" \
          "mounted_shares=$(printf '%s' "$mounted" | sed 's/^ *//')" \
          "message=n8n sticker automation was not started because one or more Mercury shares failed to mount"
        echo "Mercury SMB mount failures:$failures" >&2
        exit 1
      fi

      # The outbox is a remote share. Create the production and staging
      # directories only after it has been mounted, so they are created on
      # Mercury rather than hidden beneath the mountpoint on Uranus.
      mkdir -p /srv/sticker-automation/outbox/ABC000
      mkdir -p /srv/sticker-automation/outbox/.staging

      publish_status \
        "status=ok" \
        "mounted_shares=$(printf '%s' "$mounted" | sed 's/^ *//')"
      echo "All Mercury SMB shares are mounted."
    '';
  };
in {
  services.tailscale.enable = true;
  boot.supportedFilesystems = [ "cifs" ];

  environment.systemPackages = with pkgs; [
    cifs-utils
    tailscale
  ];

  # The first two shares are mounted into n8n read-only. The remaining
  # shares are mounted under assets/ for local access, but are deliberately
  # not exposed to the sticker workflow container.
  systemd.tmpfiles.rules = [
    "d /etc/nixos/secrets 0700 root root - -"
    "f ${credentialsFile} 0600 root root - -"
    "f ${n8nEnvironmentFile} 0600 root root - -"

    "d /srv/sticker-automation 0755 root root - -"
    "d /srv/sticker-automation/assets 0755 root root - -"
    "d /srv/sticker-automation/assets/Shop-Designs 0755 root root - -"
    "d /srv/sticker-automation/assets/Shop-Assets 0755 root root - -"
    "d /srv/sticker-automation/assets/Shop-3DModels 0755 root root - -"
    "d /srv/sticker-automation/assets/Shop-Videos 0755 root root - -"
    "d /srv/sticker-automation/assets/Shop-Accounting 0700 aquarius users - -"

    # The outbox mountpoint is created here; ABC000 and .staging are
    # created by the mount service after Shop-Outbox is mounted on Mercury.
    "d /srv/sticker-automation/outbox 0775 aquarius users - -"
    "d /srv/sticker-automation/scripts 0755 root root - -"
    "d /var/lib/sticker-automation 0770 aquarius users - -"
    # n8n's node user is UID 1000 in the official container image.
    "d /var/lib/n8n-sticker 0700 aquarius users - -"
  ];

  systemd.services.mercury-smb-mounts = {
    description = "Mount all sticker-shop SMB shares from Mercury";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    before = [ "podman-n8n-sticker.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mountMercuryShares}/bin/mount-mercury-smb-shares";
      TimeoutStartSec = "240s";
    };
  };

  virtualisation.oci-containers = {
    backend = "podman";

    containers.n8n-sticker = {
      # Version-pinned n8n image. Upgrade deliberately after testing the
      # workflow against the new release.
      image = "docker.n8n.io/n8nio/n8n:2.44.7";
      autoStart = true;
      ports = [ "127.0.0.1:5678:5678" ];

      # Mount the Nix store read-only so n8n's Execute Command node can invoke
      # Nix-built ImageMagick/Python tools and their shared-library closures.
      # The container has no writable host filesystem access beyond the paths
      # listed below.
      volumes = [
        "/var/lib/n8n-sticker:/home/node/.n8n:rw"
        "/srv/sticker-automation/outbox:/data/outbox:rw"
        "/srv/sticker-automation/assets/Shop-Assets:/data/assets/Shop-Assets:ro"
        "/srv/sticker-automation/assets/Shop-Designs:/data/assets/Shop-Designs:ro"
        "/srv/sticker-automation/scripts:/opt/sticker-scripts:ro"
        "/var/lib/sticker-automation:/data/state:rw"
        "${stickerTools}:/host-tools:ro"
        "/nix/store:/nix/store:ro"
      ];

      environmentFiles = [ n8nEnvironmentFile ];
      environment = {
        TZ = "America/Chicago";
        GENERIC_TIMEZONE = "America/Chicago";
        N8N_PORT = "5678";
        N8N_LISTEN_ADDRESS = "0.0.0.0";
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
        N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES = "true";
        N8N_RESTRICT_FILE_ACCESS_TO = "/data/outbox;/data/assets;/data/state;/opt/sticker-scripts";
        # In n8n 2.x, setting this list explicitly leaves Execute Command
        # enabled while keeping Local File Trigger disabled.
        NODES_EXCLUDE = "[\"n8n-nodes-base.localFileTrigger\"]";
        # Keep the image's standard paths available alongside Nix tools.
        PATH = "/host-tools/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";
      };
    };
  };

  # A failed SMB check should not prevent the rest of multi-user.target from
  # reaching its normal state, but it must block n8n from starting.
  systemd.services.podman-n8n-sticker = {
    requires = [ "mercury-smb-mounts.service" ];
    after = [ "mercury-smb-mounts.service" ];
  };

  # Retry mounting every five minutes. If all shares recover, start n8n
  # automatically rather than requiring a manual service restart.
  systemd.services.mercury-smb-retry = {
    description = "Retry Mercury SMB mounts and resume sticker automation";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      if systemctl is-active --quiet mercury-smb-mounts.service; then
        exit 0
      fi

      systemctl reset-failed mercury-smb-mounts.service >/dev/null 2>&1 || true
      if systemctl start mercury-smb-mounts.service; then
        if ! systemctl is-active --quiet podman-n8n-sticker.service; then
          systemctl reset-failed podman-n8n-sticker.service >/dev/null 2>&1 || true
          systemctl start podman-n8n-sticker.service
        fi
      fi
    '';
  };

  systemd.timers.mercury-smb-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "mercury-smb-retry.service";
    };
  };
}
