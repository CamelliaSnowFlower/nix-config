# Show sticker-automation problems in the logged-in graphical session:
#   - SMB mount failures: the NixOS system services write
#     /run/mercury-smb-mounts.status even when no user is logged in; this user
#     unit catches failures both at login and while logged in.
#   - Failed n8n runs: the error workflow records the run with
#     `sticker-tool record-error`, which writes last-error.json in the n8n
#     state directory. It exists only on Uranus, so the unit is inert elsewhere.
#   - Jobs awaiting approval: `sticker-tool note-approval` writes
#     latest-approval.json alongside last-error.json. A click on the
#     notification opens the approval link in the default browser instead of
#     making you dig for it in n8n or over Samba.
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
          "Mercury SMB problem: $failed_shares. Sticker automation is blocked (n8n is stopped or was not started). Shares are re-checked every five minutes."
      fi
      printf '%s\n' "$fingerprint" > "$state_file"
    '';
  };

  errorNotificationScript = pkgs.writeShellApplication {
    name = "notify-sticker-workflow-error";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      libnotify
    ];
    text = ''
      error_file=/var/lib/sticker-automation/last-error.json
      [ -r "$error_file" ] || exit 0

      fingerprint="$(sha256sum "$error_file" | cut -d' ' -f1)"
      state_dir="$HOME/.cache"
      state_file="$state_dir/sticker-workflow-error.sha256"
      previous="$(cat "$state_file" 2>/dev/null || true)"
      [ "$fingerprint" = "$previous" ] && exit 0

      mkdir -p "$state_dir"
      exec_id="$(jq -r '.exec_id' "$error_file")"
      node="$(jq -r '.node' "$error_file")"

      # Remember the error only after the notification was delivered.
      notify-send \
        --urgency=critical \
        --app-name="Sticker automation" \
        "Sticker workflow failed" \
        "Execution $exec_id stopped at: $node. Open n8n to review the failed run."
      printf '%s\n' "$fingerprint" > "$state_file"
    '';
  };
  approvalNotificationScript = pkgs.writeShellApplication {
    name = "notify-sticker-approval";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      libnotify
      xdg-utils
    ];
    text = ''
      approval_file=/var/lib/sticker-automation/latest-approval.json
      [ -r "$approval_file" ] || exit 0

      fingerprint="$(sha256sum "$approval_file" | cut -d' ' -f1)"
      state_dir="$HOME/.cache"
      state_file="$state_dir/sticker-approval-notification.sha256"
      previous="$(cat "$state_file" 2>/dev/null || true)"
      [ "$fingerprint" = "$previous" ] && exit 0

      mkdir -p "$state_dir"
      job_id="$(jq -r '.job_id' "$approval_file")"
      url="$(jq -r '.url' "$approval_file")"

      # -A implies --wait: notify-send blocks until the notification is
      # dismissed or an action is clicked, and prints the clicked action's
      # name. A plain `notify-send` with no action would return immediately
      # and give us no way to tell if the link was opened.
      action="$(notify-send \
        --app-name="Sticker automation" \
        --urgency=normal \
        -A "open=Open approval link" \
        "Sticker job ready for approval" \
        "Job $job_id is staged and waiting for approval.")"

      if [ "$action" = "open" ]; then
        xdg-open "$url"
      fi
      # Remember this job regardless of whether the link was opened, so
      # dismissing the popup doesn't make it reappear on the next check.
      printf '%s\n' "$fingerprint" > "$state_file"
    '';
  };
in {
  systemd.user.services.sticker-workflow-error-notification = {
    Unit = {
      Description = "Notify when a sticker workflow run fails";
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${errorNotificationScript}/bin/notify-sticker-workflow-error";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.paths.sticker-workflow-error-notification = {
    Unit.Description = "Watch for failed sticker workflow runs";
    Path = {
      PathExists = "/var/lib/sticker-automation/last-error.json";
      PathChanged = "/var/lib/sticker-automation/last-error.json";
      Unit = "sticker-workflow-error-notification.service";
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.mercury-smb-mount-notification = {
    Unit = {
      Description = "Notify when Mercury SMB mounts block sticker automation";
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${notificationScript}/bin/notify-mercury-smb-status";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.paths.mercury-smb-mount-notification = {
    Unit.Description = "Watch the Mercury SMB mount status";
    Path = {
      PathExists = "/run/mercury-smb-mounts.status";
      PathChanged = "/run/mercury-smb-mounts.status";
      Unit = "mercury-smb-mount-notification.service";
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.sticker-approval-notification = {
    Unit = {
      Description = "Notify when a sticker job is waiting for approval";
      After = ["graphical-session.target"];
    };
    Service = {
      # notify-send -A blocks until the popup is dismissed/clicked, so this
      # is not a quick oneshot in practice; give it room rather than letting
      # systemd kill it mid-wait.
      Type = "oneshot";
      TimeoutStartSec = "0";
      ExecStart = "${approvalNotificationScript}/bin/notify-sticker-approval";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.paths.sticker-approval-notification = {
    Unit.Description = "Watch for sticker jobs awaiting approval";
    Path = {
      PathExists = "/var/lib/sticker-automation/latest-approval.json";
      PathChanged = "/var/lib/sticker-automation/latest-approval.json";
      Unit = "sticker-approval-notification.service";
    };
    Install.WantedBy = ["default.target"];
  };
}
