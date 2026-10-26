# Show SMB mount failures in the logged-in graphical session. The NixOS
# system service writes /run/mercury-smb-mounts.status even when no user is
# logged in; this user unit catches failures both at login and while logged in.
{pkgs, ...}: let
  notificationScript = pkgs.writeShellApplication {
    name = "notify-mercury-smb-status";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      libnotify
    ];
    text = ''
      status_file=/run/mercury-smb-mounts.status
      [ -r "$status_file" ] || exit 0

      status_text="$(cat "$status_file")"
      fingerprint="$(printf '%s' "$status_text" | sha256sum | cut -d' ' -f1)"
      state_dir="$HOME/.cache"
      state_file="$state_dir/mercury-smb-notification.sha256"
      previous="$(cat "$state_file" 2>/dev/null || true)"
      [ "$fingerprint" = "$previous" ] && exit 0

      mkdir -p "$state_dir"
      if printf '%s\n' "$status_text" | grep -qx 'status=failed'; then
        failed_shares="$(printf '%s\n' "$status_text" | sed -n 's/^failed_shares=//p')"
        [ -n "$failed_shares" ] || failed_shares="unknown shares"

        # Only remember a failed status after notify-send succeeds. If the
        # desktop notification service is not ready yet, a later activation
        # can still deliver the alert.
        notify-send \
          --urgency=critical \
          --app-name="Sticker automation" \
          "Sticker automation unavailable" \
          "Mercury SMB mount failure: $failed_shares. n8n was not started. Mounts will be retried automatically."
      fi
      printf '%s\n' "$fingerprint" > "$state_file"
    '';
  };
in {
  systemd.user.services.mercury-smb-mount-notification = {
    Unit = {
      Description = "Notify when Mercury SMB mounts block sticker automation";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${notificationScript}/bin/notify-mercury-smb-status";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.paths.mercury-smb-mount-notification = {
    Unit.Description = "Watch the Mercury SMB mount status";
    Path = {
      PathExists = "/run/mercury-smb-mounts.status";
      PathChanged = "/run/mercury-smb-mounts.status";
      Unit = "mercury-smb-mount-notification.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
