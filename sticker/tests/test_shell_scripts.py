"""Behaviour tests for the shell scripts embedded in the NixOS modules.

The scripts are extracted from the .nix files (or read from minecraft-backup.sh),
Nix interpolations are replaced with test values, and the scripts run against
stub commands in a temporary directory. Nothing here mounts a share, touches
systemd, or writes outside the temp directory.

This does NOT replace evaluating the flake or running shellcheck, which the
Nix build does (writeShellApplication). It proves the control flow.

Run from the repository root:

    python3 -m unittest discover -s sticker/tests -v
"""

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
URANUS_NIX = ROOT / "hosts/uranus/sticker-automation.nix"
MERCURY = ROOT / "hosts/mercury"
SHARES = ["Shop-Designs", "Shop-Assets", "Shop-3DModels", "Shop-Videos", "Shop-Accounting", "Shop-Outbox"]


def extract_nix_script(nix_file: Path, name: str) -> str:
    text = nix_file.read_text()
    start = text.index(f'name = "{name}";')
    begin = text.index("text = ''\n", start) + len("text = ''\n")
    end = text.index("\n    '';", begin)
    lines = text[begin:end].split("\n")
    indent = min(len(line) - len(line.lstrip()) for line in lines if line.strip())
    return "\n".join(line[indent:] for line in lines) + "\n"


def nix_string(nix_file: Path, variable: str) -> str:
    match = re.search(rf'{variable} = "([^"]+)";', nix_file.read_text())
    assert match, variable
    return match.group(1)


def write_stub(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text("#!/usr/bin/env bash\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="shell-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.stubs = self.tmp / "stubs"
        self.stubs.mkdir()

    def run_script(self, script_path: Path, env_extra: dict, strict=True):
        env = {"PATH": f"{self.stubs}:{os.environ['PATH']}", "HOME": str(self.tmp)}
        env.update(env_extra)
        flags = ["-euo", "pipefail"] if strict else []
        return subprocess.run(
            ["bash", *flags, str(script_path)], env=env, capture_output=True, text=True, timeout=120
        )


class SmbHealthCheckTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.state = self.tmp / "state"
        self.state.mkdir()
        raw = extract_nix_script(URANUS_NIX, "check-mercury-smb-shares")
        raw = raw.replace("${lib.escapeShellArgs requiredShares}", " ".join(SHARES))
        raw = raw.replace("${mercuryAddress}", nix_string(URANUS_NIX, "mercuryAddress"))
        raw = raw.replace("${blockedMessage}", nix_string(URANUS_NIX, "blockedMessage"))
        raw = raw.replace("/run/mercury-smb-mounts.status", str(self.state / "status"))
        self.assertNotIn("${lib", raw)
        self.script = self.tmp / "health.sh"
        self.script.write_text(raw)
        self.address = nix_string(URANUS_NIX, "mercuryAddress")

        write_stub(self.stubs, "mountpoint", f'''
base="$(basename "$2")"; [ "$base" = outbox ] && base=Shop-Outbox
grep -qx "$base" "{self.state}/mounted"
''')
        write_stub(self.stubs, "findmnt", f'''
base="$(basename "${{!#}}")"; [ "$base" = outbox ] && base=Shop-Outbox
if [ -f "{self.state}/wrong-source" ] && grep -qx "$base" "{self.state}/wrong-source"; then
  echo "//10.9.9.9/$base"; else echo "//{self.address}/$base"; fi
''')
        write_stub(self.stubs, "ls", f'''
base="$(basename "${{!#}}")"; [ "$base" = outbox ] && base=Shop-Outbox
if [ -f "{self.state}/lsfail" ] && grep -qx "$base" "{self.state}/lsfail"; then exit 2; fi
exit 0
''')
        write_stub(self.stubs, "umount", f'echo "umount $*" >> "{self.state}/calls"\n')
        write_stub(self.stubs, "systemctl", f'''
echo "systemctl $*" >> "{self.state}/calls"
case "$1 $2" in
  "is-active --quiet") [ -f "{self.state}/n8n_active" ]; exit $? ;;
  "start podman-n8n-sticker.service") touch "{self.state}/n8n_active" ;;
  "stop podman-n8n-sticker.service") rm -f "{self.state}/n8n_active" ;;
  "restart mercury-smb-mounts.service")
    if [ -f "{self.state}/recover" ]; then printf '%s\\n' {" ".join(SHARES)} > "{self.state}/mounted"; fi ;;
esac
exit 0
''')
        self.set_mounted(SHARES)

    def set_mounted(self, shares):
        (self.state / "mounted").write_text("\n".join(shares) + "\n")

    def calls(self):
        path = self.state / "calls"
        return path.read_text() if path.exists() else ""

    def status(self):
        return (self.state / "status").read_text()

    def run_check(self):
        return self.run_script(self.script, {})

    def test_all_healthy_publishes_ok_and_starts_n8n(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("status=ok", self.status())
        self.assertIn("systemctl start podman-n8n-sticker.service", self.calls())
        self.assertNotIn("restart", self.calls())

    def test_unchanged_status_is_not_rewritten(self):
        self.run_check()
        before = (self.state / "status").stat().st_ino
        self.run_check()
        self.assertEqual((self.state / "status").stat().st_ino, before)

    def test_missing_share_is_recovered_by_remount(self):
        self.set_mounted([s for s in SHARES if s != "Shop-Videos"])
        (self.state / "recover").touch()
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn("umount -l /srv/sticker-automation/assets/Shop-Videos", calls)
        self.assertIn("systemctl restart mercury-smb-mounts.service", calls)
        self.assertIn("status=ok", self.status())

    def test_unrecoverable_share_blocks_n8n_and_reports_failure(self):
        self.set_mounted([s for s in SHARES if s != "Shop-Outbox"])
        (self.state / "n8n_active").touch()
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        status = self.status()
        self.assertIn("status=failed", status)
        self.assertIn("failed_shares=Shop-Outbox", status)
        self.assertIn("Sticker automation is blocked", status)
        self.assertIn("systemctl stop podman-n8n-sticker.service", self.calls())
        self.assertFalse((self.state / "n8n_active").exists())
        self.assertIn("umount -l /srv/sticker-automation/outbox", self.calls())

    def test_stale_or_wrong_source_mount_counts_as_unhealthy(self):
        (self.state / "lsfail").write_text("Shop-Assets\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("failed_shares=Shop-Assets", self.status())
        (self.state / "lsfail").unlink()
        (self.state / "wrong-source").write_text("Shop-Designs\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("failed_shares=Shop-Designs", self.status())

    def test_recovery_restarts_n8n_only_when_it_is_down(self):
        (self.state / "n8n_active").touch()
        self.run_check()
        self.assertNotIn("systemctl start podman-n8n-sticker.service", self.calls())


class StaticScriptChecks(TempDirCase):
    def test_mount_script_and_storage_permissions_parse(self):
        mount = extract_nix_script(URANUS_NIX, "mount-mercury-smb-shares")
        mount = mount.replace("${lib.escapeShellArgs shares}", " ".join(SHARES))
        mount = mount.replace("${mercuryAddress}", "192.168.1.80")
        mount = mount.replace("${credentialsFile}", "/tmp/creds").replace("${blockedMessage}", "blocked")
        self.assertNotIn("${lib", mount)
        path = self.tmp / "mount.sh"
        path.write_text(mount)
        self.assertEqual(subprocess.run(["bash", "-n", str(path)]).returncode, 0)

        perms = extract_nix_script(MERCURY / "storage-permissions.nix", "apply-storage-permissions")
        perms = re.sub(
            r"\$\{lib\.concatMapStringsSep.*?\n\s*managed\}",
            "apply /mnt/storage/shop-designs root users 2775",
            perms,
            flags=re.S,
        )
        self.assertNotIn("${lib", perms)
        path = self.tmp / "perms.sh"
        path.write_text(perms)
        self.assertEqual(subprocess.run(["bash", "-n", str(path)]).returncode, 0)
        write_stub(self.stubs, "mountpoint", "exit 1\n")
        for tool in ("chown", "chmod"):
            write_stub(self.stubs, tool, f'echo "{tool} $*" >> "{self.tmp}/calls"\n')
        result = self.run_script(path, {})
        self.assertEqual(result.returncode, 1, "an unmounted dataset must fail the unit")
        self.assertFalse((self.tmp / "calls").exists(), "nothing may be changed when not mounted")
        write_stub(self.stubs, "mountpoint", "exit 0\n")
        result = self.run_script(path, {})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("chmod 2775 /mnt/storage/shop-designs", (self.tmp / "calls").read_text())


class MinecraftBackupTests(TempDirCase):
    def setUp(self):
        super().setUp()
        self.script = MERCURY / "minecraft-backup.sh"
        self.data = self.tmp / "server"
        (self.data / "world").mkdir(parents=True)
        (self.data / "logs").mkdir()
        (self.data / "world/level.dat").write_text("world data")
        (self.data / "server.properties").write_text("motd=test")
        (self.data / "logs/latest.log").write_text("")
        self.root = self.tmp / "backups"
        self.root.mkdir()
        self.tmux_log = self.tmp / "tmux.log"
        write_stub(self.stubs, "tmux", f'''
shift 2
case "$1" in
  has-session) [ "${{TMUX_RUNNING:-0}}" = 1 ]; exit $? ;;
  list-sessions) echo mc ;;
  send-keys)
    echo "$4" >> "{self.tmux_log}"
    if [ "$4" = "save-all flush" ] && [ "${{FLUSH_CONFIRM:-0}}" = 1 ]; then
      echo "[12:00:00] [Server thread/INFO]: Saved the game" >> "$SERVER_DATA_DIR/logs/latest.log"
    fi ;;
esac
''')
        write_stub(self.stubs, "rsync", '''
dst="${@: -1}"; src="${@: -2:1}"
cp -a "$src." "$dst"
if [ "${RSYNC_FAIL:-0}" = 1 ]; then echo "rsync: simulated failure" >&2; exit 23; fi
''')

    def env(self, **extra):
        base = {
            "BACKUP_ROOT": str(self.root),
            "SERVER_DATA_DIR": str(self.data),
            "SOCK": str(self.tmp / "mc.sock"),
            "KEEP_BACKUPS": "2",
            "FLUSH_TIMEOUT": "2",
            "FLUSH_FALLBACK_SLEEP": "0",
        }
        base.update(extra)
        return base

    def backups(self):
        return sorted(p.name for p in self.root.iterdir())

    def test_stopped_server_backup_prunes_only_old_timestamped_dirs(self):
        for name in ("2026-01-01_000000", "2026-01-02_000000", "2026-01-03_000000", "notes", ".partial-old"):
            (self.root / name).mkdir()
        result = self.run_script(self.script, self.env())
        self.assertEqual(result.returncode, 0, result.stderr)
        names = self.backups()
        self.assertIn("notes", names, "unrelated directories must never be pruned")
        self.assertNotIn(".partial-old", names, "stale partial directories are cleaned")
        timestamped = [n for n in names if re.match(r"\d{4}-\d{2}-\d{2}_\d{6}$", n)]
        self.assertEqual(len(timestamped), 2)
        self.assertIn("2026-01-03_000000", timestamped)
        newest = max(timestamped)
        self.assertEqual((self.root / newest / "world/level.dat").read_text(), "world data")
        self.assertFalse(self.tmux_log.exists(), "a stopped server must not be sent commands")

    def test_running_server_is_flushed_then_saving_is_restored(self):
        result = self.run_script(self.script, self.env(TMUX_RUNNING="1", FLUSH_CONFIRM="1"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tmux_log.read_text().split("\n")[:3], ["save-off", "save-all flush", "save-on"])
        self.assertNotIn("WARNING", result.stderr)

    def test_unconfirmed_flush_warns_but_still_completes(self):
        result = self.run_script(self.script, self.env(TMUX_RUNNING="1", FLUSH_CONFIRM="0", FLUSH_TIMEOUT="1"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not confirmed", result.stderr)
        self.assertIn("save-on", self.tmux_log.read_text())

    def test_failed_copy_restores_saving_publishes_nothing_and_prunes_nothing(self):
        for name in ("2026-01-01_000000", "2026-01-02_000000", "2026-01-03_000000"):
            (self.root / name).mkdir()
        result = self.run_script(self.script, self.env(TMUX_RUNNING="1", FLUSH_CONFIRM="1", RSYNC_FAIL="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("save-on", self.tmux_log.read_text(), "saving must be re-enabled after a failure")
        self.assertEqual(self.backups(), ["2026-01-01_000000", "2026-01-02_000000", "2026-01-03_000000"])
        self.assertIn("nothing was published", result.stderr)

    def test_missing_backup_root_is_never_created(self):
        missing = self.tmp / "not-mounted" / "sticker-shop"
        result = self.run_script(self.script, self.env(BACKUP_ROOT=str(missing)))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(missing.exists())
        self.assertFalse((self.tmp / "not-mounted").exists())

    def test_missing_server_directory_fails_cleanly(self):
        result = self.run_script(self.script, self.env(SERVER_DATA_DIR=str(self.tmp / "nope")))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.backups(), [])


if __name__ == "__main__":
    unittest.main()
