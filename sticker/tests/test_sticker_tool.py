"""Tests for sticker_tool using disposable directories and synthetic art.

Run from the repository root:

    python3 -m unittest discover -s sticker/tests -v

Requires ImageMagick (magick or convert), numpy, and Pillow. Nothing here
touches real shares, the real outbox, or Google Drive.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sticker_tool as st  # noqa: E402

TOOL = Path(st.__file__).resolve()
SMALL_CONFIG = {
    # Small sheets and a coarse grid keep the tests fast.
    "sheets": {
        "letter": {"width_in": 4.0, "height_in": 5.0, "margin_in": 0.25},
        "tabloid": {"width_in": 5.0, "height_in": 7.0, "margin_in": 0.25},
    },
    "max_copies_per_sheet": 200,
}


def ring_art(path, size=400, white_background=True):
    """Black ring with an enclosed white hole, to prove holes get filled."""
    mode = "RGB" if white_background else "RGBA"
    background = (255, 255, 255) if white_background else (0, 0, 0, 0)
    image = Image.new(mode, (size, size), background)
    draw = ImageDraw.Draw(image)
    outline = (0, 0, 0) if white_background else (0, 0, 0, 255)
    draw.ellipse((60, 60, size - 60, size - 60), outline=outline, width=24)
    image.save(path)


def star_alpha_art(path, size=400):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    points = []
    for i in range(10):
        angle = np.pi / 5 * i - np.pi / 2
        radius = 150 if i % 2 == 0 else 60
        points.append((size / 2 + radius * np.cos(angle), size / 2 + radius * np.sin(angle)))
    draw.polygon(points, fill=(200, 30, 30, 255))
    image.save(path)


class ToolTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sticker-test-"))
        self.outbox = self.tmp / "outbox"
        self.state = self.tmp / "state"
        self.outbox.mkdir()
        self.state.mkdir()
        (self.state / "config.json").write_text(json.dumps(SMALL_CONFIG))
        self.env_patch = mock.patch.dict(
            os.environ,
            {"STICKER_OUTBOX": str(self.outbox), "STICKER_STATE": str(self.state)},
        )
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.addCleanup(shutil.rmtree, self.tmp, True)

    # helpers -------------------------------------------------------------
    def run_tool(self, *argv):
        return st.main(list(argv))

    def call(self, *argv):
        """Run a subcommand and return its parsed JSON output."""
        with mock.patch("builtins.print") as printed:
            code = st.main(list(argv))
        self.assertEqual(code, 0, f"command failed: {argv}")
        return json.loads(printed.call_args[0][0])

    def fail(self, *argv):
        with mock.patch("builtins.print") as printed:
            code = st.main(list(argv))
        self.assertEqual(code, 2)
        return printed.call_args[0][0] if printed.call_args else ""

    def make_upload(self, exec_id, count=1, size_in=1.0, sheets=("letter",), quantity=None, art="ring"):
        directory = self.state / "incoming" / str(exec_id)
        self.call("mkincoming", "--exec-id", str(exec_id))
        files = []
        for index in range(1, count + 1):
            name = f"{index:03d}.png"
            if art == "ring":
                ring_art(directory / name)
            else:
                star_alpha_art(directory / name)
            files.append({"file": name, "original_name": f"customer file {index}; rm -rf / .png"})
        request = {"size_in": size_in, "sheets": list(sheets), "quantity": quantity, "files": files}
        (directory / "request.json").write_text(json.dumps(request))
        return directory

    def full_job(self, exec_id, **kwargs):
        self.make_upload(exec_id, **kwargs)
        job = self.call("intake", "--exec-id", str(exec_id))
        self.call("process", "--job", job["job_id"])
        self.call("nest", "--job", job["job_id"])
        return job


class IntakeValidationTests(ToolTestCase):
    def test_rejects_bad_exec_id_and_missing_request(self):
        self.fail("mkincoming", "--exec-id", "12;rm")
        (self.state / "incoming" / "5").mkdir(parents=True)
        self.fail("intake", "--exec-id", "5")

    def test_rejects_unexpected_fields_sizes_and_sheets(self):
        for bad in (
            {"size_in": 99, "sheets": ["letter"], "quantity": None, "files": []},
            {"size_in": 1, "sheets": ["poster"], "quantity": None, "files": []},
            {"size_in": 1, "sheets": ["letter"], "quantity": 0, "files": []},
            {"size_in": 1, "sheets": ["letter"], "quantity": None, "files": [], "extra": 1},
        ):
            directory = self.state / "incoming" / "7"
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "request.json").write_text(json.dumps(bad))
            self.fail("intake", "--exec-id", "7")

    def test_rejects_non_image_and_traversal_names(self):
        directory = self.make_upload(8)
        (directory / "001.png").write_bytes(b"not an image at all")
        self.fail("intake", "--exec-id", "8")
        request = json.loads((directory / "request.json").read_text())
        request["files"][0]["file"] = "../../etc/passwd"
        (directory / "request.json").write_text(json.dumps(request))
        self.fail("intake", "--exec-id", "8")

    def test_customer_text_never_reaches_filenames(self):
        self.make_upload(9)
        job = self.call("intake", "--exec-id", "9")
        stage = Path(job["staging"])
        names = sorted(p.name for p in stage.iterdir())
        self.assertEqual(names, ["ABC001V001_source.png", "manifest.json"])


class NamingAndRegistryTests(ToolTestCase):
    def test_numbering_starts_at_001_and_counts_variations(self):
        self.make_upload(10, count=3)
        job = self.call("intake", "--exec-id", "10")
        self.assertEqual(job["listing"], 1)
        self.assertEqual(job["skus"], ["ABC001V001", "ABC001V002", "ABC001V003"])

    def test_existing_files_in_folder_are_respected(self):
        prod = self.outbox / "ABC000"
        prod.mkdir()
        (prod / "ABC007V002.png").write_bytes(b"x")
        self.make_upload(11, count=2)
        job = self.call("intake", "--exec-id", "11")
        self.assertEqual(job["skus"], ["ABC008V001", "ABC008V002"])

    def test_intake_is_idempotent_for_the_same_execution(self):
        self.make_upload(12)
        first = self.call("intake", "--exec-id", "12")
        second = self.call("intake", "--exec-id", "12")
        self.assertEqual(first["listing"], second["listing"])
        self.assertEqual(second["note"], "job already exists")

    def test_concurrent_intakes_get_unique_listings(self):
        for exec_id in range(100, 108):
            self.make_upload(exec_id)

        def run(exec_id):
            result = subprocess.run(
                [sys.executable, str(TOOL), "intake", "--exec-id", str(exec_id)],
                capture_output=True,
                text=True,
                env=os.environ.copy(),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)["listing"]

        with ThreadPoolExecutor(max_workers=8) as pool:
            listings = list(pool.map(run, range(100, 108)))
        self.assertEqual(sorted(listings), list(range(1, 9)))

    def test_reject_releases_the_number(self):
        self.make_upload(13)
        job = self.call("intake", "--exec-id", "13")
        rejected = self.call("reject", "--job", job["job_id"])
        self.assertEqual(rejected["released_listing"], 1)
        self.assertFalse(Path(job["staging"]).exists())
        self.make_upload(14)
        again = self.call("intake", "--exec-id", "14")
        self.assertEqual(again["listing"], 1)


class ProcessingTests(ToolTestCase):
    def test_white_background_ring_becomes_solid_with_border(self):
        self.make_upload(20, size_in=1.0)
        job = self.call("intake", "--exec-id", "20")
        self.call("process", "--job", job["job_id"])
        sticker = Image.open(Path(job["staging"]) / "ABC001V001.png")
        self.assertEqual(sticker.mode, "RGBA")
        # Artwork is 300 px (1 inch at 300 dpi); the border adds about 10 px per side.
        self.assertTrue(318 <= sticker.size[0] <= 324, sticker.size)
        alpha = np.array(sticker.getchannel("A"))
        centre = alpha[alpha.shape[0] // 2, alpha.shape[1] // 2]
        self.assertEqual(centre, 255, "enclosed white hole must be filled")
        self.assertEqual(alpha[0, 0], 0, "corner must stay transparent")
        self.assertAlmostEqual(sticker.info.get("dpi", (0, 0))[0], 300, delta=0.01)

    def test_jpeg_upload_is_accepted_and_saved_with_its_own_extension(self):
        directory = self.state / "incoming" / "22"
        self.call("mkincoming", "--exec-id", "22")
        ring_art(directory / "001.png")
        Image.open(directory / "001.png").convert("RGB").save(directory / "001.jpg", quality=90)
        (directory / "001.png").unlink()
        request = {
            "size_in": 1.0,
            "sheets": ["letter"],
            "quantity": None,
            "files": [{"file": "001.jpg", "original_name": "ring.jpg"}],
        }
        (directory / "request.json").write_text(json.dumps(request))
        job = self.call("intake", "--exec-id", "22")
        self.assertTrue((Path(job["staging"]) / "ABC001V001_source.jpg").is_file())
        self.call("process", "--job", job["job_id"])
        alpha = np.array(Image.open(Path(job["staging"]) / "ABC001V001.png").getchannel("A"))
        self.assertEqual(alpha[alpha.shape[0] // 2, alpha.shape[1] // 2], 255)

    def test_transparent_png_keeps_its_alpha_artwork(self):
        self.make_upload(21, size_in=1.0, art="star")
        job = self.call("intake", "--exec-id", "21")
        result = self.call("process", "--job", job["job_id"])
        self.assertTrue(result["stickers"][0]["used_alpha"])
        sticker = np.array(Image.open(Path(job["staging"]) / "ABC001V001.png"))
        red = (sticker[..., 0] > 150) & (sticker[..., 1] < 80) & (sticker[..., 3] == 255)
        white = (sticker[..., :3].min(axis=2) == 255) & (sticker[..., 3] == 255)
        self.assertGreater(red.sum(), 1000)
        self.assertGreater(white.sum(), 500, "white border should surround the art")


class NestingTests(ToolTestCase):
    def test_true_shape_nesting_has_no_overlap_stays_inside_and_is_deterministic(self):
        job = self.full_job(30, size_in=1.0, art="star", sheets=("letter",))
        stage = Path(job["staging"])
        layout = json.loads((stage / "ABC001V001_layout.json").read_text())
        sheet = layout["sheets"]["letter"]
        sticker = Image.open(stage / "ABC001V001.png").convert("RGBA")
        width, height = sheet["canvas_px"]
        margin = sheet["margin_px"]
        coverage = np.zeros((height, width), dtype=np.int32)
        for place in sheet["placements"]:
            rotated = st.rotate_rgba(sticker, place["rotation"])
            alpha = np.array(rotated.getchannel("A")) > 0
            h, w = alpha.shape
            x, y = place["x"], place["y"]
            self.assertGreaterEqual(x, margin)
            self.assertGreaterEqual(y, margin)
            self.assertLessEqual(x + w, width - margin)
            self.assertLessEqual(y + h, height - margin)
            coverage[y:y + h, x:x + w] += alpha
        self.assertEqual(int(coverage.max()), 1, "no two stickers may overlap")
        self.assertGreaterEqual(sheet["copies"], 2)

        # Beats a simple bounding-box grid for the same sticker and sheet.
        printable_w = width - 2 * margin
        printable_h = height - 2 * margin
        sw, sh = sticker.size
        grid_count = (printable_w // sw) * (printable_h // sh)
        self.assertGreaterEqual(sheet["copies"], grid_count)

        # Same inputs, same layout.
        again = st.best_layout(
            sticker,
            st.DEFAULT_CONFIG["sheets"]["letter"] | SMALL_CONFIG["sheets"]["letter"],
            st.DEFAULT_CONFIG["profiles"]["default"],
            {**st.DEFAULT_CONFIG, **SMALL_CONFIG},
        )
        self.assertEqual(again["placements"], sheet["placements"])

    def test_sticker_too_large_for_sheet_is_an_error(self):
        self.make_upload(31, size_in=6.0, sheets=("letter",))
        job = self.call("intake", "--exec-id", "31")
        self.call("process", "--job", job["job_id"])
        message = self.fail("nest", "--job", job["job_id"])
        self.assertIn("does not fit", message)

    def test_sheets_needed_uses_quantity(self):
        job = self.full_job(32, size_in=1.0, quantity=100, sheets=("letter",))
        summary = self.call("nest", "--job", job["job_id"], "--profile", "wide-gap")
        entry = summary["sheets"][0]
        self.assertEqual(entry["sheets_needed"], -(-100 // entry["copies"]))

    def test_unknown_profile_is_rejected(self):
        job = self.full_job(33)
        self.fail("nest", "--job", job["job_id"], "--profile", "../../x")


class CommitAndReprintTests(ToolTestCase):
    def test_commit_publishes_files_atomically_and_reprint_is_identical(self):
        job = self.full_job(40, sheets=("letter", "tabloid"))
        stage = Path(job["staging"])
        layout_before = json.loads((stage / "ABC001V001_layout.json").read_text())
        result = self.call("commit", "--job", job["job_id"])
        self.assertEqual(result["state"], "committed")
        prod = self.outbox / "ABC000"
        expected = {
            "ABC001V001.png",
            "ABC001V001_source.png",
            "ABC001V001_layout.json",
            "ABC001V001_letter.png",
            "ABC001V001_tabloid.png",
        }
        self.assertEqual({p.name for p in prod.iterdir()}, expected)
        self.assertFalse(stage.exists(), "staging must be cleaned up")
        self.assertEqual(json.loads((prod / "ABC001V001_layout.json").read_text()), layout_before)

        for sheet in ("letter", "tabloid"):
            reprint = self.call("reprint", "--sku", "ABC001V001", "--sheet", sheet)
            self.assertTrue(reprint["matches_saved_sheet"])
            self.assertEqual(
                st.sha256_file(Path(reprint["output"])),
                st.sha256_file(prod / f"ABC001V001_{sheet}.png"),
            )
        self.assertEqual(self.call("commit", "--job", job["job_id"])["note"], "already committed")

    def test_commit_recovers_after_a_crash_midway(self):
        job = self.full_job(41)
        real_rename = os.rename
        calls = {"n": 0}

        def flaky(src, dst):
            calls["n"] += 1
            if calls["n"] == 3:
                raise OSError("simulated crash")
            return real_rename(src, dst)

        with mock.patch("sticker_tool.os.rename", side_effect=flaky):
            with self.assertRaises(OSError):
                st.main(["commit", "--job", job["job_id"]])
        prod = self.outbox / "ABC000"
        self.assertEqual(len(list(prod.iterdir())), 2, "two files were published before the crash")
        status = self.call("status", "--job", job["job_id"])
        self.assertEqual(status["state"], "committing")
        self.fail("reject", "--job", job["job_id"])  # cannot discard a half-committed job

        recovered = self.call("commit", "--job", job["job_id"])
        self.assertEqual(recovered["state"], "committed")
        names = {p.name for p in prod.iterdir()}
        self.assertEqual(
            names,
            {"ABC001V001.png", "ABC001V001_source.png", "ABC001V001_layout.json", "ABC001V001_letter.png"},
        )

    def test_commit_never_overwrites_existing_files(self):
        job = self.full_job(42)
        prod = self.outbox / "ABC000"
        prod.mkdir(exist_ok=True)
        (prod / "ABC001V001_letter.png").write_bytes(b"precious")
        message = self.fail("commit", "--job", job["job_id"])
        self.assertIn("refusing to overwrite", message)
        self.assertEqual((prod / "ABC001V001_letter.png").read_bytes(), b"precious")

    def test_reprint_detects_a_changed_sticker_and_bad_input(self):
        job = self.full_job(43)
        self.call("commit", "--job", job["job_id"])
        self.fail("reprint", "--sku", "ABC001V001; ls", "--sheet", "letter")
        self.fail("reprint", "--sku", "XYZ001V001", "--sheet", "letter")
        (self.outbox / "ABC000" / "ABC001V001.png").write_bytes(b"changed")
        self.fail("reprint", "--sku", "ABC001V001", "--sheet", "letter")


class SmallCommandTests(ToolTestCase):
    def test_note_approval_validates_the_url(self):
        self.make_upload(50)
        job = self.call("intake", "--exec-id", "50")
        self.fail("note-approval", "--job", job["job_id"], "--url", "http://x/$(id)")
        ok = self.call(
            "note-approval", "--job", job["job_id"],
            "--url", "https://uranus.example.ts.net/form-waiting/123?signature=abc123",
        )
        self.assertTrue(Path(ok["approval_file"]).is_file())

    def test_record_error_sanitises_node_name(self):
        self.call("record-error", "--exec-id", "77", "--node", "bad;name$(x)")
        data = json.loads((self.state / "last-error.json").read_text())
        self.assertEqual(data["node"], "unknown")
        self.call("record-error", "--exec-id", "78", "--node", "Process stickers")
        data = json.loads((self.state / "last-error.json").read_text())
        self.assertEqual(data["node"], "Process stickers")

    def test_bad_job_id_is_rejected(self):
        self.fail("process", "--job", "../../etc")


if __name__ == "__main__":
    unittest.main()
