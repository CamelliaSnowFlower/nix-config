# Sticker automation on Uranus.
#
# Mercury's asset shares are mounted beneath assets/, while generated
# production files and staging are stored in Mercury's Shop-Outbox share.
# Admins pull finished output directly from Shop-Outbox over the LAN or
# Tailscale (see hosts/mercury/tailscale.nix); it's no longer mirrored to
# Google Drive - that sync was removed as unreliable. n8n is bound to
# loopback and can only be reached remotely through Tailscale Serve.
#
# The workflow calls one command, `sticker-tool` (see ../../sticker/), which
# n8n's Execute Command node runs. See STICKER-AUTOMATION.md for the workflow
# import steps and the trust boundary around Execute Command.
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
  # Mercury's outbox is the production output location. Keep staging
  # beneath it so commit renames stay on the same SMB filesystem.
  shares = assetShares ++ ["Shop-Outbox"];

  # Shares that must be healthy for sticker automation to run. The mount script
  # still mounts every share; this list drives the periodic health check.
  # Whether every share should be mandatory is an open decision in TODO.md.
  requiredShares = shares;

  blockedMessage = "Sticker automation is blocked: one or more Mercury shares are missing or stale, so n8n is stopped or was not started";

  stickerPython = pkgs.python3.withPackages (pythonPackages:
    with pythonPackages; [
      numpy
      pillow
    ]);

  # The job tool is plain Python kept in sticker/ and covered by the tests in
  # sticker/tests. Its shebang is pinned to the Nix-built interpreter above.
  # Flakes only see git-tracked files, so `git add sticker/` before building.
  stickerTool = pkgs.writeScriptBin "sticker-tool" (
    "#!${stickerPython}/bin/python3\n" + builtins.readFile ../../sticker/sticker_tool.py
  );

  # Cricut print-then-cut templates (sticker/boundaries/) defining each
  # sheet's real printable area -- a plain Nix path, so referencing it below
  # copies the directory into the store; the container gets its path via
  # STICKER_ASSETS's sibling STICKER_BOUNDARIES env var.
  stickerBoundaries = ../../sticker/boundaries;

  stickerTools = pkgs.buildEnv {
    name = "sticker-automation-tools";
    paths = [
      pkgs.imagemagick
      stickerPython
      stickerTool
    ];
    pathsToLink = ["/bin"];
  };

  checkMercuryShares = pkgs.writeShellApplication {
    name = "check-mercury-smb-shares";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      gnused
      systemd
      util-linux
    ];
    text = ''
      status_file=/run/mercury-smb-mounts.status
      failures=""
      healthy=""

      share_target() {
        if [ "$1" = "Shop-Outbox" ]; then
          printf '%s\n' /srv/sticker-automation/outbox
        else
          printf '%s\n' "/srv/sticker-automation/assets/$1"
        fi
      }

      # Healthy means: mounted, from the expected source, and answering a
      # bounded directory listing (a stale CIFS mount hangs without a timeout).
      share_healthy() {
        target="$(share_target "$1")"
        expected="//${mercuryAddress}/$1"
        timeout 10 mountpoint -q "$target" || return 1
        current="$(timeout 10 findmnt -rn -o SOURCE --target "$target" 2>/dev/null || true)"
        [ "$current" = "$expected" ] || return 1
        timeout 10 ls -- "$target" >/dev/null 2>&1
      }

      check_all() {
        failures=""
        healthy=""
        for share in ${lib.escapeShellArgs requiredShares}; do
          if share_healthy "$share"; then
            healthy="$healthy $share"
          else
            failures="$failures $share"
          fi
        done
      }

      # Only replace the status file when its content changes, so the desktop
      # watcher is not triggered every few minutes.
      publish_status() {
        tmp="$(mktemp /run/mercury-smb-mounts.status.XXXXXX)"
        printf '%s\n' "$@" > "$tmp"
        chmod 0644 "$tmp"
        if [ -f "$status_file" ] && cmp -s "$tmp" "$status_file"; then
          rm -f "$tmp"
        else
          mv -f "$tmp" "$status_file"
        fi
      }

      check_all
      if [ -n "$failures" ]; then
        echo "Unhealthy Mercury shares:$failures; attempting recovery." >&2
        for share in ${lib.escapeShellArgs requiredShares}; do
          case " $failures " in
            *" $share "*)
              # Lazy unmount clears stale or wrongly sourced mounts. It fails
              # harmlessly when nothing is mounted.
              timeout 20 umount -l "$(share_target "$share")" >/dev/null 2>&1 || true
              ;;
          esac
        done
        systemctl reset-failed mercury-smb-mounts.service >/dev/null 2>&1 || true
        systemctl restart mercury-smb-mounts.service || true
        check_all
      fi

      if [ -n "$failures" ]; then
        publish_status \
          "status=failed" \
          "failed_shares=$(printf '%s' "$failures" | sed 's/^ *//')" \
          "mounted_shares=$(printf '%s' "$healthy" | sed 's/^ *//')" \
          "message=${blockedMessage}"
        echo "Stopping n8n until these shares recover:$failures" >&2
        systemctl stop podman-n8n-sticker.service || true
        exit 1
      fi

      publish_status \
        "status=ok" \
        "mounted_shares=$(printf '%s' "$healthy" | sed 's/^ *//')"
      if ! systemctl is-active --quiet podman-n8n-sticker.service; then
        systemctl reset-failed podman-n8n-sticker.service >/dev/null 2>&1 || true
        systemctl start podman-n8n-sticker.service
      fi
    '';
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

        if timeout 10 mountpoint -q "$target"; then
          current_source="$(timeout 10 findmnt -rn -o SOURCE --target "$target" 2>/dev/null || true)"
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

        # uid=1000/gid=100 must match aquarius and the users group on this
        # host; the n8n container's node user is also UID 1000. Verify with
        # `id aquarius`, or declare the UID explicitly (open item in TODO.md).
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
          "message=${blockedMessage}"
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
  boot.supportedFilesystems = ["cifs"];

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
    "d /var/lib/sticker-automation 0770 aquarius users - -"
    # n8n's node user is UID 1000 in the official container image.
    "d /var/lib/n8n-sticker 0700 aquarius users - -"
  ];

  systemd.services.mercury-smb-mounts = {
    description = "Mount all sticker-shop SMB shares from Mercury";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    before = ["podman-n8n-sticker.service"];

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
      ports = ["127.0.0.1:5678:5678"];

      # Mount the Nix store read-only so n8n's Execute Command node can invoke
      # Nix-built ImageMagick/Python tools and their shared-library closures.
      # The container has no writable host filesystem access beyond the paths
      # listed below.
      volumes = [
        "/var/lib/n8n-sticker:/home/node/.n8n:rw"
        "/srv/sticker-automation/outbox:/data/outbox:rw"
        "/srv/sticker-automation/assets/Shop-Assets:/data/assets/Shop-Assets:ro"
        "/srv/sticker-automation/assets/Shop-Designs:/data/assets/Shop-Designs:ro"
        "/var/lib/sticker-automation:/data/state:rw"
        "${stickerTools}:/host-tools:ro"
        "/nix/store:/nix/store:ro"
      ];

      environmentFiles = [n8nEnvironmentFile];
      environment = {
        TZ = "America/Chicago";
        GENERIC_TIMEZONE = "America/Chicago";
        N8N_PORT = "5678";
        # Defaults baked into sticker-tool; stated here so the paths are explicit.
        STICKER_OUTBOX = "/data/outbox";
        STICKER_STATE = "/data/state";
        STICKER_ASSETS = "/data/assets/Shop-Assets";
        # A /nix/store path, not a bind-mounted /data path like the above --
        # already reachable in the container via the existing read-only
        # /nix/store mount below, no separate volume needed.
        STICKER_BOUNDARIES = "${stickerBoundaries}";
        N8N_LISTEN_ADDRESS = "0.0.0.0";
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
        N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES = "true";
        N8N_RESTRICT_FILE_ACCESS_TO = "/data/outbox;/data/assets;/data/state";
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
    requires = ["mercury-smb-mounts.service"];
    after = ["mercury-smb-mounts.service"];
  };

  # Every five minutes, check that each required Mercury share is still mounted
  # from the expected source and answers a bounded probe. Stale or missing
  # mounts are lazily unmounted and remounted (which also restarts n8n, since
  # it requires the mount service). If a share stays unhealthy, a failed status
  # is published and n8n is stopped so jobs cannot write to a missing or stale
  # outbox. When everything is healthy again, n8n is started. Unfinished
  # commits resume safely: `sticker-tool commit` is journaled and restartable.
  systemd.services.mercury-smb-retry = {
    description = "Check Mercury SMB mounts and gate sticker automation";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${checkMercuryShares}/bin/check-mercury-smb-shares";
      TimeoutStartSec = "420s";
    };
  };

  systemd.timers.mercury-smb-retry = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "mercury-smb-retry.service";
    };
  };
}
