"""sticker-tool: deterministic helper for the sticker production workflow.

This is the single command n8n's Execute Command node calls. It is plain,
reviewable code: no network access, no AI image generation, and no step ever
alters artwork beyond resizing, background detection, and adding a border.

Trust boundary
--------------
n8n Execute Command is a shell. To keep that safe, this tool never takes
customer text on its command line. The only arguments are server-generated
identifiers (an execution id, a job id) and values from fixed enums. Customer
data (original filenames, size, quantity) travels in ``request.json`` and is
parsed and validated here.

Layout of the data it manages (paths are configurable through environment
variables so the tests can use disposable directories):

    $STICKER_OUTBOX/ABC000/          committed files, flat, named by SKU
    $STICKER_OUTBOX/.staging/<job>/  in-progress jobs (same filesystem, so
                                     the final rename is atomic)
    $STICKER_STATE/registry.db       SQLite registry (listing allocator)
    $STICKER_STATE/incoming/<exec>/  uploads written by n8n, consumed by intake

Subcommands: mkincoming, intake, process, nest, note-approval, commit,
reject, reprint, status, record-error.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import fcntl
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image

ALGORITHM_VERSION = 1
SCHEMA_VERSION = 1

PREFIX_RE = re.compile(r"^[A-Z]{3}$")
JOB_ID_RE = re.compile(r"^job_[0-9a-f]{12}$")
EXEC_ID_RE = re.compile(r"^[0-9]{1,12}$")
SKU_RE = re.compile(r"^([A-Z]{3})([0-9]{3})V([0-9]{3})$")
UPLOAD_NAME_RE = re.compile(r"^[0-9]{3}\.(png|jpg|jpeg)$")
NODE_NAME_RE = re.compile(r"^[A-Za-z0-9 _.\-]{1,60}$")
APPROVAL_URL_RE = re.compile(r"^https://[A-Za-z0-9.\-]+(:[0-9]{1,5})?/[A-Za-z0-9._~/?=&%\-]{1,400}$")

DEFAULT_CONFIG = {
    # Three-letter SKU prefix. The static production folder is <prefix>000.
    "prefix": "ABC",
    "dpi": 300,
    # Border growth around the artwork silhouette, in pixels at `dpi`.
    "border_px": 10,
    # Pixels at or above this brightness (0..1) count as background. This is
    # the same cutoff used with Inkscape's trace bitmap.
    "bg_brightness": 0.996,
    # JPEG compression adds noise near white, so JPEGs use a lower cutoff and
    # a small median filter. Tune these against real files.
    "bg_brightness_jpg": 0.97,
    "jpeg_median_radius": 1,
    # PNGs with real transparency use alpha >= this value as the silhouette.
    "alpha_threshold": 1,
    # Gap kept between neighbouring stickers on a sheet, in inches.
    "gap_in": 0.0625,
    # Resolution of the collision grid used while nesting. dpi must be a
    # multiple of this value.
    "nest_dpi": 50,
    "max_files_per_job": 50,
    "min_size_in": 0.5,
    "max_size_in": 12.0,
    "max_quantity": 100000,
    "max_pixels": 100_000_000,
    "max_copies_per_sheet": 400,
    # ASSUMPTION: full paper size minus a margin. Replace these with the
    # printable area Cricut Design Space actually allows for your setup.
    "sheets": {
        "letter": {"width_in": 8.5, "height_in": 11.0, "margin_in": 0.5},
        "tabloid": {"width_in": 11.0, "height_in": 17.0, "margin_in": 0.5},
    },
    # Nesting profiles. Each tries every rotation set and keeps the sheet that
    # fits the most copies (ties go to the earlier, simpler set).
    "profiles": {
        "default": {"gap_in": None, "rotation_sets": [[0, 180], [0, 90, 180, 270]]},
        "wide-gap": {"gap_in": 0.125, "rotation_sets": [[0, 90, 180, 270]]},
        "more-rotations": {
            "gap_in": None,
            "rotation_sets": [[0, 90, 180, 270], [0, 45, 90, 135, 180, 225, 270, 315]],
        },
    },
}


class ToolError(Exception):
    """A problem the operator can act on (bad input, conflict, missing tool)."""


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def deep_merge(base: dict, override: dict) -> dict:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fsync_dir(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass  # some network filesystems refuse directory fsync
    finally:
        os.close(fd)


def atomic_write_text(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)
    fsync_dir(path.parent)


def write_json(path: Path, data: object) -> None:
    atomic_write_text(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def read_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


@contextlib.contextmanager
def file_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def make_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    with contextlib.suppress(OSError):
        os.chmod(path, 0o775)


def make_file_shareable(path: Path) -> None:
    with contextlib.suppress(OSError):
        os.chmod(path, 0o664)


# --------------------------------------------------------------------------
# Environment and configuration
# --------------------------------------------------------------------------


class Env:
    def __init__(self, outbox: str | None = None, state: str | None = None):
        self.outbox = Path(outbox or os.environ.get("STICKER_OUTBOX", "/data/outbox"))
        self.state = Path(state or os.environ.get("STICKER_STATE", "/data/state"))
        self.cfg = self._load_config()
        self.prefix = self.cfg["prefix"]
        if not PREFIX_RE.match(self.prefix):
            raise ToolError("config prefix must be exactly three capital letters")
        if self.cfg["dpi"] % self.cfg["nest_dpi"] != 0:
            raise ToolError("config dpi must be a multiple of nest_dpi")
        self.prod = self.outbox / f"{self.prefix}000"
        self.staging = self.outbox / ".staging"
        self.incoming = self.state / "incoming"
        self.db_path = self.state / "registry.db"
        self.lock_path = self.state / "commit.lock"

    def _load_config(self) -> dict:
        cfg = copy.deepcopy(DEFAULT_CONFIG)
        override = os.environ.get("STICKER_CONFIG")
        path = Path(override) if override else self.state / "config.json"
        if path.is_file():
            deep_merge(cfg, read_json(path))
        return cfg

    def job_dir(self, job_id: str) -> Path:
        if not JOB_ID_RE.match(job_id):
            raise ToolError("invalid job id")
        return self.staging / job_id

    def sku(self, listing: int, variation: int) -> str:
        return f"{self.prefix}{listing:03d}V{variation:03d}"


# --------------------------------------------------------------------------
# Registry (single allocator for listing numbers)
# --------------------------------------------------------------------------

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS listings(
    listing INTEGER PRIMARY KEY CHECK (listing BETWEEN 1 AND 999),
    job_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('reserved', 'committed')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS jobs(
    job_id TEXT PRIMARY KEY,
    listing INTEGER NOT NULL REFERENCES listings(listing),
    state TEXT NOT NULL CHECK (state IN
        ('staged', 'processed', 'nested', 'committing', 'committed')),
    params_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS variants(
    sku TEXT PRIMARY KEY,
    job_id TEXT NOT NULL REFERENCES jobs(job_id),
    listing INTEGER NOT NULL,
    variation INTEGER NOT NULL CHECK (variation BETWEEN 1 AND 999),
    source_name TEXT NOT NULL,
    UNIQUE (listing, variation)
);
"""


class Registry:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path, timeout=60, isolation_level=None)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA foreign_keys=ON")
        self.conn.executescript(SCHEMA_SQL)

    def close(self) -> None:
        self.conn.close()

    @contextlib.contextmanager
    def transaction(self):
        self.conn.execute("BEGIN IMMEDIATE")
        try:
            yield self.conn
        except BaseException:
            self.conn.execute("ROLLBACK")
            raise
        else:
            self.conn.execute("COMMIT")

    def get_job(self, job_id: str):
        row = self.conn.execute(
            "SELECT job_id, listing, state, params_json FROM jobs WHERE job_id = ?",
            (job_id,),
        ).fetchone()
        if row is None:
            return None
        return {"job_id": row[0], "listing": row[1], "state": row[2], "params": json.loads(row[3])}

    def set_state(self, job_id: str, state: str) -> None:
        self.conn.execute(
            "UPDATE jobs SET state = ?, updated_at = ? WHERE job_id = ?",
            (state, now_iso(), job_id),
        )

    def reserve(self, job_id: str, params: dict, originals: list[str], folder_max: int, prefix: str):
        """Allocate the next listing number. Safe against concurrent callers.

        The database is the allocator. The highest listing number found in the
        production folder is only a reconciliation input, so files added by
        hand are never reused.
        """
        with self.transaction() as conn:
            existing = self.get_job(job_id)
            if existing is not None:
                return existing, True
            db_max = conn.execute("SELECT COALESCE(MAX(listing), 0) FROM listings").fetchone()[0]
            listing = max(db_max, folder_max) + 1
            if listing > 999:
                raise ToolError("listing numbers are exhausted (three digits, 999 maximum)")
            stamp = now_iso()
            conn.execute(
                "INSERT INTO listings(listing, job_id, status, created_at, updated_at)"
                " VALUES (?, ?, 'reserved', ?, ?)",
                (listing, job_id, stamp, stamp),
            )
            conn.execute(
                "INSERT INTO jobs(job_id, listing, state, params_json, created_at, updated_at)"
                " VALUES (?, ?, 'staged', ?, ?, ?)",
                (job_id, listing, json.dumps(params, sort_keys=True), stamp, stamp),
            )
            for variation, name in enumerate(originals, start=1):
                conn.execute(
                    "INSERT INTO variants(sku, job_id, listing, variation, source_name)"
                    " VALUES (?, ?, ?, ?, ?)",
                    (f"{prefix}{listing:03d}V{variation:03d}", job_id, listing, variation, name),
                )
        return self.get_job(job_id), False

    def release(self, job_id: str) -> None:
        with self.transaction() as conn:
            conn.execute("DELETE FROM variants WHERE job_id = ?", (job_id,))
            conn.execute("DELETE FROM jobs WHERE job_id = ?", (job_id,))
            conn.execute("DELETE FROM listings WHERE job_id = ? AND status = 'reserved'", (job_id,))

    def finish(self, job_id: str) -> None:
        with self.transaction() as conn:
            stamp = now_iso()
            conn.execute(
                "UPDATE listings SET status = 'committed', updated_at = ? WHERE job_id = ?",
                (stamp, job_id),
            )
            conn.execute(
                "UPDATE jobs SET state = 'committed', updated_at = ? WHERE job_id = ?",
                (stamp, job_id),
            )

    def all_jobs(self):
        rows = self.conn.execute(
            "SELECT job_id, listing, state FROM jobs ORDER BY listing"
        ).fetchall()
        return [{"job_id": r[0], "listing": r[1], "state": r[2]} for r in rows]


def scan_folder_max(env: Env) -> int:
    rx = re.compile(rf"^{env.prefix}([0-9]{{3}})V[0-9]{{3}}")
    best = 0
    if env.prod.is_dir():
        for name in os.listdir(env.prod):
            match = rx.match(name)
            if match:
                best = max(best, int(match.group(1)))
    return best


# --------------------------------------------------------------------------
# ImageMagick helpers
# --------------------------------------------------------------------------


def im_command() -> list[str]:
    override = os.environ.get("STICKER_IM")
    if override:
        return override.split()
    for name in ("magick", "convert"):
        found = shutil.which(name)
        if found:
            return [found]
    raise ToolError("ImageMagick (magick or convert) was not found on PATH")


def run_im(args: list[str]) -> None:
    try:
        subprocess.run(
            im_command() + args,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=900,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", "replace").strip()[:500]
        raise ToolError(f"ImageMagick failed: {detail}") from error
    except subprocess.TimeoutExpired as error:
        raise ToolError("ImageMagick timed out") from error


def open_checked(path: Path, cfg: dict) -> Image.Image:
    Image.MAX_IMAGE_PIXELS = cfg["max_pixels"]
    try:
        image = Image.open(path)
        image.verify()
        image = Image.open(path)
        image.load()
    except Exception as error:  # Pillow raises many types for bad files
        raise ToolError("file is not a readable PNG or JPEG image") from error
    if image.format not in ("PNG", "JPEG"):
        raise ToolError("only PNG and JPEG uploads are accepted")
    if min(image.size) < 16:
        raise ToolError("image is too small to be artwork")
    return image


def has_real_alpha(image: Image.Image) -> bool:
    if "A" in image.getbands():
        return image.getchannel("A").getextrema()[0] < 255
    return "transparency" in image.info


def opaque_foreground_mask(norm_png: Path, work: Path, cutoff: float, median: int) -> np.ndarray:
    """Foreground = everything except near-white pixels connected to the edge.

    ImageMagick thresholds brightness (the same idea as Inkscape's trace
    cutoff), pads the image with white, and flood-fills the outer background.
    Near-white areas enclosed by artwork stay foreground, so the silhouette is
    solid with no holes.
    """
    out = work / "mask_opaque.png"
    args = [str(norm_png), "-background", "white", "-alpha", "remove", "-alpha", "off"]
    if median:
        args += ["-median", str(median)]
    args += [
        "-colorspace", "Gray",
        "-threshold", f"{cutoff * 100:g}%",
        "-bordercolor", "white", "-border", "1",
        "-fill", "gray50", "-draw", "color 0,0 floodfill",
        "-shave", "1x1",
        "-type", "Grayscale", "-depth", "8",
        f"PNG:{out}",
    ]
    run_im(args)
    gray = np.array(Image.open(out).convert("L"))
    background = (gray >= 100) & (gray <= 160)
    return ~background


def alpha_foreground_mask(image: Image.Image, threshold: int) -> np.ndarray:
    return np.array(image.getchannel("A")) >= threshold


def dilate_with_imagemagick(mask: np.ndarray, radius: int, work: Path):
    pad = radius + 2
    src = work / "mask_in.png"
    out = work / "mask_dilated.png"
    Image.fromarray((mask * 255).astype("uint8")).save(src)
    run_im([
        str(src),
        "-bordercolor", "black", "-border", f"{pad}x{pad}",
        "-morphology", "Dilate", f"Disk:{radius}",
        "-blur", "0x0.8", "-threshold", "50%",
        "-type", "Grayscale", "-depth", "8",
        f"PNG:{out}",
    ])
    dilated = np.array(Image.open(out).convert("L")) > 127
    return dilated, pad


def build_sticker(source: Path, out_png: Path, size_in: float, cfg: dict) -> dict:
    """Source artwork -> finished sticker PNG (artwork + white border)."""
    dpi = cfg["dpi"]
    work = out_png.parent / f".work-{out_png.stem}"
    work.mkdir(parents=True, exist_ok=True)
    try:
        image = open_checked(source, cfg)
        is_jpeg = image.format == "JPEG"
        use_alpha = has_real_alpha(image)
        norm = work / "norm.png"
        run_im([
            str(source), "-auto-orient", "-strip",
            "-density", str(dpi), "-units", "PixelsPerInch",
            f"PNG32:{norm}",
        ])
        cutoff = cfg["bg_brightness_jpg"] if is_jpeg else cfg["bg_brightness"]
        median = cfg["jpeg_median_radius"] if is_jpeg else 0

        def foreground(png: Path) -> np.ndarray:
            if use_alpha:
                return alpha_foreground_mask(Image.open(png).convert("RGBA"), cfg["alpha_threshold"])
            return opaque_foreground_mask(png, work, cutoff, median)

        mask = foreground(norm)
        ys, xs = np.nonzero(mask)
        if ys.size == 0:
            raise ToolError("no artwork was found (the image looks blank)")
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()) + 1, int(ys.min()), int(ys.max()) + 1
        cropped = work / "cropped.png"
        run_im([str(norm), "-crop", f"{x1 - x0}x{y1 - y0}+{x0}+{y0}", "+repage", f"PNG32:{cropped}"])

        target = max(1, round(size_in * dpi))
        resized = work / "resized.png"
        run_im([
            str(cropped), "-filter", "Lanczos", "-resize", f"{target}x{target}", "+repage",
            "-density", str(dpi), "-units", "PixelsPerInch", f"PNG32:{resized}",
        ])

        art = Image.open(resized).convert("RGBA")
        fg = foreground(resized)
        dilated, pad = dilate_with_imagemagick(fg, cfg["border_px"], work)

        height, width = fg.shape
        big_h, big_w = dilated.shape
        border_layer = np.zeros((big_h, big_w, 4), dtype=np.uint8)
        border_layer[dilated] = (255, 255, 255, 255)
        art_layer = np.zeros((big_h, big_w, 4), dtype=np.uint8)
        art_pixels = np.array(art)
        art_layer[pad:pad + height, pad:pad + width, :3] = art_pixels[:, :, :3]
        art_layer[pad:pad + height, pad:pad + width, 3] = art_pixels[:, :, 3] if use_alpha else (fg * 255).astype(np.uint8)
        sticker = Image.alpha_composite(
            Image.fromarray(border_layer), Image.fromarray(art_layer)
        )
        box = sticker.getchannel("A").getbbox()
        sticker = sticker.crop(box)
        sticker.save(out_png, format="PNG", dpi=(dpi, dpi), compress_level=6)
        make_file_shareable(out_png)
        return {
            "width_px": sticker.size[0],
            "height_px": sticker.size[1],
            "used_alpha": use_alpha,
            "sha256": sha256_file(out_png),
        }
    finally:
        shutil.rmtree(work, ignore_errors=True)


# --------------------------------------------------------------------------
# Nesting: true-shape packing of identical copies on a sheet
# --------------------------------------------------------------------------


def rotate_rgba(image: Image.Image, angle: int) -> Image.Image:
    angle %= 360
    if angle == 0:
        rotated = image
    elif angle == 90:
        rotated = image.transpose(Image.Transpose.ROTATE_90)
    elif angle == 180:
        rotated = image.transpose(Image.Transpose.ROTATE_180)
    elif angle == 270:
        rotated = image.transpose(Image.Transpose.ROTATE_270)
    else:
        rotated = image.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    box = rotated.getchannel("A").getbbox()
    return rotated.crop(box)


def pool_max(mask: np.ndarray, factor: int) -> np.ndarray:
    """Shrink a boolean mask by `factor`, never losing an occupied pixel."""
    height, width = mask.shape
    padded_h = -(-height // factor) * factor
    padded_w = -(-width // factor) * factor
    padded = np.zeros((padded_h, padded_w), dtype=bool)
    padded[:height, :width] = mask
    return padded.reshape(padded_h // factor, factor, padded_w // factor, factor).any(axis=(1, 3))


def dilate_square(mask: np.ndarray, radius: int) -> np.ndarray:
    """Grow a mask by `radius` cells on every side (output is larger)."""
    if radius <= 0:
        return mask
    padded = np.pad(mask, radius)
    horizontal = np.zeros_like(padded)
    for shift in range(-radius, radius + 1):
        horizontal |= np.roll(padded, shift, axis=1)
    result = np.zeros_like(padded)
    for shift in range(-radius, radius + 1):
        result |= np.roll(horizontal, shift, axis=0)
    return result


def nest_sheet(sticker: Image.Image, sheet: dict, gap_in: float, rotations: list[int], cfg: dict) -> dict:
    """Greedy first-fit packing using real outlines, not bounding boxes.

    Every copy is placed where its (slightly grown) silhouette overlaps nothing
    already placed. Collision tests run as FFT cross-correlations on a coarse
    grid. Silhouettes are pooled with `max`, so the coarse mask always covers
    the true outline and placements never overlap at full resolution.
    Fully deterministic: no randomness anywhere.
    """
    dpi = cfg["dpi"]
    factor = dpi // cfg["nest_dpi"]
    margin = round(sheet["margin_in"] * dpi)
    canvas_w = round(sheet["width_in"] * dpi)
    canvas_h = round(sheet["height_in"] * dpi)
    grid_w = (canvas_w - 2 * margin) // factor
    grid_h = (canvas_h - 2 * margin) // factor
    if grid_w <= 0 or grid_h <= 0:
        raise ToolError("sheet margins leave no printable area")
    gap_cells = math.ceil(round(gap_in * dpi) / factor / 2)

    shapes = []
    for index, angle in enumerate(rotations):
        rotated = rotate_rgba(sticker, angle)
        alpha = np.array(rotated.getchannel("A")) > 0
        coarse = dilate_square(pool_max(alpha, factor), gap_cells)
        height, width = coarse.shape
        if height > grid_h or width > grid_w:
            continue
        padded = np.zeros((grid_h, grid_w), dtype=np.float64)
        padded[:height, :width] = coarse
        shapes.append({
            "angle": angle,
            "index": index,
            "mask": coarse,
            "fconj": np.conj(np.fft.rfft2(padded)),
            "area_px": int(alpha.sum()),
        })
    if not shapes:
        raise ToolError("the sticker does not fit on this sheet at any allowed rotation")

    occupied = np.zeros((grid_h, grid_w), dtype=np.float64)
    placements = []
    covered_px = 0
    while len(placements) < cfg["max_copies_per_sheet"]:
        spectrum = np.fft.rfft2(occupied)
        best = None
        for shape in shapes:
            height, width = shape["mask"].shape
            overlap = np.fft.irfft2(spectrum * shape["fconj"], s=(grid_h, grid_w))
            valid = overlap[: grid_h - height + 1, : grid_w - width + 1] < 0.5
            flat = np.flatnonzero(valid)
            if flat.size == 0:
                continue
            row, col = divmod(int(flat[0]), valid.shape[1])
            key = (row + height, col, shape["index"])
            if best is None or key < best[0]:
                best = (key, shape, row, col)
        if best is None:
            break
        _, shape, row, col = best
        height, width = shape["mask"].shape
        region = occupied[row:row + height, col:col + width]
        np.maximum(region, shape["mask"], out=region)
        placements.append({
            "x": margin + (col + gap_cells) * factor,
            "y": margin + (row + gap_cells) * factor,
            "rotation": shape["angle"],
        })
        covered_px += shape["area_px"]
    printable = (canvas_w - 2 * margin) * (canvas_h - 2 * margin)
    return {
        "canvas_px": [canvas_w, canvas_h],
        "margin_px": margin,
        "gap_in": gap_in,
        "rotation_set": rotations,
        "nest_dpi": cfg["nest_dpi"],
        "copies": len(placements),
        "fill_percent": round(100.0 * covered_px / printable, 2),
        "placements": placements,
    }


def render_sheet(sticker: Image.Image, layout: dict, dpi: int) -> Image.Image:
    width, height = layout["canvas_px"]
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    cache: dict[int, Image.Image] = {}
    for place in layout["placements"]:
        angle = place["rotation"]
        if angle not in cache:
            cache[angle] = rotate_rgba(sticker, angle)
        canvas.alpha_composite(cache[angle], dest=(place["x"], place["y"]))
    return canvas


def save_sheet(canvas: Image.Image, path: Path, dpi: int) -> str:
    canvas.save(path, format="PNG", dpi=(dpi, dpi), compress_level=6)
    make_file_shareable(path)
    return sha256_file(path)


def save_preview(canvas: Image.Image, path: Path) -> None:
    paper = Image.new("RGBA", canvas.size, (225, 225, 225, 255))
    paper.alpha_composite(canvas)
    preview = paper.convert("RGB")
    preview.thumbnail((1400, 1400))
    preview.save(path, format="JPEG", quality=85)
    make_file_shareable(path)


def best_layout(sticker: Image.Image, sheet: dict, profile: dict, cfg: dict) -> dict:
    gap = profile["gap_in"] if profile.get("gap_in") is not None else cfg["gap_in"]
    best = None
    for rotation_set in profile["rotation_sets"]:
        candidate = nest_sheet(sticker, sheet, gap, rotation_set, cfg)
        if best is None or candidate["copies"] > best["copies"]:
            best = candidate
    return best


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def require_exec_id(value: str) -> str:
    if not EXEC_ID_RE.match(value):
        raise ToolError("invalid execution id")
    return value


def cmd_mkincoming(env: Env, args) -> dict:
    exec_id = require_exec_id(args.exec_id)
    path = env.incoming / exec_id
    make_dir(env.incoming)
    make_dir(path)
    return {"incoming": str(path)}


def validate_request(env: Env, request: dict, directory: Path) -> tuple[dict, list[dict]]:
    cfg = env.cfg
    allowed = {"size_in", "sheets", "quantity", "files"}
    if not isinstance(request, dict) or set(request) - allowed:
        raise ToolError("request.json has missing or unexpected fields")
    size_in = request.get("size_in")
    if isinstance(size_in, bool) or not isinstance(size_in, (int, float)):
        raise ToolError("size_in must be a number")
    if not (cfg["min_size_in"] <= size_in <= cfg["max_size_in"]):
        raise ToolError(f"size_in must be between {cfg['min_size_in']} and {cfg['max_size_in']} inches")
    sheets = request.get("sheets")
    if not isinstance(sheets, list) or not sheets or len(set(sheets)) != len(sheets):
        raise ToolError("sheets must be a non-empty list without duplicates")
    for name in sheets:
        if name not in cfg["sheets"]:
            raise ToolError("unknown sheet type")
    quantity = request.get("quantity")
    if quantity is not None:
        if isinstance(quantity, bool) or not isinstance(quantity, int) or not (1 <= quantity <= cfg["max_quantity"]):
            raise ToolError("quantity must be a whole number within the allowed range")
    files = request.get("files")
    if not isinstance(files, list) or not (1 <= len(files) <= cfg["max_files_per_job"]):
        raise ToolError(f"between 1 and {cfg['max_files_per_job']} files are required")
    cleaned = []
    seen = set()
    for item in files:
        if not isinstance(item, dict) or set(item) - {"file", "original_name"}:
            raise ToolError("each file entry needs only 'file' and 'original_name'")
        name = item.get("file")
        if not isinstance(name, str) or not UPLOAD_NAME_RE.match(name) or name in seen:
            raise ToolError("upload file names must look like 001.png and be unique")
        seen.add(name)
        original = item.get("original_name", "")
        if not isinstance(original, str):
            raise ToolError("original_name must be text")
        original = "".join(ch for ch in original if ch.isprintable())[:255]
        path = directory / name
        if not path.is_file() or path.is_symlink():
            raise ToolError("a listed upload is missing")
        image = open_checked(path, cfg)
        cleaned.append({"path": path, "format": image.format, "original_name": original})
    params = {"size_in": float(size_in), "sheets": sheets, "quantity": quantity}
    return params, cleaned


def derive_job_id(exec_id: str) -> str:
    return "job_" + hashlib.sha256(f"exec:{exec_id}".encode()).hexdigest()[:12]


def cmd_intake(env: Env, args) -> dict:
    exec_id = require_exec_id(args.exec_id)
    job_id = derive_job_id(exec_id)
    registry = Registry(env.db_path)
    try:
        existing = registry.get_job(job_id)
        if existing is not None:
            return describe_job(env, registry, job_id, note="job already exists")
        directory = env.incoming / exec_id
        request_path = directory / "request.json"
        if not request_path.is_file():
            raise ToolError("request.json was not found in the incoming directory")
        try:
            request = read_json(request_path)
        except (ValueError, OSError) as error:
            raise ToolError("request.json is not valid JSON") from error
        params, uploads = validate_request(env, request, directory)
        make_dir(env.staging)
        make_dir(env.prod)
        job, _ = registry.reserve(
            job_id, params, [u["original_name"] for u in uploads], scan_folder_max(env), env.prefix
        )
        stage = env.job_dir(job_id)
        make_dir(stage)
        variants = []
        for variation, upload in enumerate(uploads, start=1):
            sku = env.sku(job["listing"], variation)
            extension = ".png" if upload["format"] == "PNG" else ".jpg"
            source_name = f"{sku}_source{extension}"
            shutil.copyfile(upload["path"], stage / source_name)
            make_file_shareable(stage / source_name)
            variants.append({
                "variation": variation,
                "sku": sku,
                "source_file": source_name,
                "source_sha256": sha256_file(stage / source_name),
                "original_name": upload["original_name"],
            })
        write_json(stage / "manifest.json", {
            "schema": SCHEMA_VERSION,
            "job_id": job_id,
            "listing": job["listing"],
            "prefix": env.prefix,
            "params": params,
            "variants": variants,
            "state": "staged",
        })
        shutil.rmtree(directory, ignore_errors=True)
        return describe_job(env, registry, job_id)
    finally:
        registry.close()


def load_manifest(env: Env, job_id: str) -> tuple[Path, dict]:
    stage = env.job_dir(job_id)
    manifest_path = stage / "manifest.json"
    if not manifest_path.is_file():
        raise ToolError("staging manifest not found for this job")
    return stage, read_json(manifest_path)


def describe_job(env: Env, registry: Registry, job_id: str, note: str | None = None) -> dict:
    job = registry.get_job(job_id)
    if job is None:
        raise ToolError("unknown job")
    result = {"job_id": job_id, "listing": job["listing"], "state": job["state"]}
    manifest_path = env.job_dir(job_id) / "manifest.json"
    if manifest_path.is_file():
        manifest = read_json(manifest_path)
        result["skus"] = [v["sku"] for v in manifest["variants"]]
        result["sheets"] = manifest["params"]["sheets"]
        result["staging"] = str(env.job_dir(job_id))
    if note:
        result["note"] = note
    return result


def cmd_process(env: Env, args) -> dict:
    registry = Registry(env.db_path)
    try:
        job = registry.get_job(args.job)
        if job is None:
            raise ToolError("unknown job")
        if job["state"] in ("committing", "committed"):
            raise ToolError("job is already being committed")
        stage, manifest = load_manifest(env, args.job)
        results = []
        for variant in manifest["variants"]:
            out = stage / f"{variant['sku']}.png"
            info = build_sticker(stage / variant["source_file"], out, manifest["params"]["size_in"], env.cfg)
            variant["sticker_file"] = out.name
            variant["sticker"] = info
            results.append({"sku": variant["sku"], **info})
        manifest["state"] = "processed"
        write_json(stage / "manifest.json", manifest)
        registry.set_state(args.job, "processed")
        return {"job_id": args.job, "stickers": results}
    finally:
        registry.close()


def cmd_nest(env: Env, args) -> dict:
    profile_name = args.profile
    profile = env.cfg["profiles"].get(profile_name)
    if profile is None:
        raise ToolError("unknown nesting profile")
    registry = Registry(env.db_path)
    try:
        job = registry.get_job(args.job)
        if job is None:
            raise ToolError("unknown job")
        if job["state"] in ("staged", "committing", "committed"):
            raise ToolError("run process before nest, and do not re-nest a committed job")
        stage, manifest = load_manifest(env, args.job)
        quantity = manifest["params"]["quantity"]
        summary = []
        for variant in manifest["variants"]:
            sticker = Image.open(stage / variant["sticker_file"]).convert("RGBA")
            layout = {
                "schema": SCHEMA_VERSION,
                "algorithm_version": ALGORITHM_VERSION,
                "sku": variant["sku"],
                "sticker_sha256": variant["sticker"]["sha256"],
                "dpi": env.cfg["dpi"],
                "profile": profile_name,
                "sheets": {},
            }
            for sheet_name in manifest["params"]["sheets"]:
                result = best_layout(sticker, env.cfg["sheets"][sheet_name], profile, env.cfg)
                canvas = render_sheet(sticker, result, env.cfg["dpi"])
                sheet_path = stage / f"{variant['sku']}_{sheet_name}.png"
                result["sheet_sha256"] = save_sheet(canvas, sheet_path, env.cfg["dpi"])
                save_preview(canvas, stage / f"{variant['sku']}_{sheet_name}_preview.jpg")
                layout["sheets"][sheet_name] = result
                entry = {
                    "sku": variant["sku"],
                    "sheet": sheet_name,
                    "copies": result["copies"],
                    "fill_percent": result["fill_percent"],
                    "preview": f"{variant['sku']}_{sheet_name}_preview.jpg",
                }
                if quantity is not None and result["copies"] > 0:
                    entry["sheets_needed"] = math.ceil(quantity / result["copies"])
                summary.append(entry)
            write_json(stage / f"{variant['sku']}_layout.json", layout)
        manifest["state"] = "nested"
        manifest["nest_profile"] = profile_name
        write_json(stage / "manifest.json", manifest)
        registry.set_state(args.job, "nested")
        return {"job_id": args.job, "profile": profile_name, "staging": str(stage), "sheets": summary}
    finally:
        registry.close()


def cmd_note_approval(env: Env, args) -> dict:
    if not APPROVAL_URL_RE.match(args.url):
        raise ToolError("approval URL has unexpected characters")
    stage, _ = load_manifest(env, args.job)
    atomic_write_text(
        stage / "APPROVAL-LINK.txt",
        "Open this link (on the tailnet) to approve, re-run, or reject this job:\n" + args.url + "\n",
    )
    return {"job_id": args.job, "approval_file": str(stage / "APPROVAL-LINK.txt")}


def commit_entries(manifest: dict) -> list[str]:
    names = []
    for variant in manifest["variants"]:
        sku = variant["sku"]
        names.append(variant["source_file"])
        names.append(f"{sku}_layout.json")
        for sheet in manifest["params"]["sheets"]:
            names.append(f"{sku}_{sheet}.png")
        names.append(f"{sku}.png")  # the finished sticker is published last
    return names


def cmd_commit(env: Env, args) -> dict:
    registry = Registry(env.db_path)
    try:
        with file_lock(env.lock_path):
            job = registry.get_job(args.job)
            if job is None:
                raise ToolError("unknown job")
            if job["state"] == "committed":
                return {"job_id": args.job, "state": "committed", "note": "already committed"}
            if job["state"] not in ("nested", "committing"):
                raise ToolError("job must be nested (and approved) before it can be committed")
            stage, manifest = load_manifest(env, args.job)
            journal_path = stage / "journal.json"
            make_dir(env.prod)
            if journal_path.is_file():
                journal = read_json(journal_path)
            else:
                entries = []
                for name in commit_entries(manifest):
                    source = stage / name
                    if not source.is_file():
                        raise ToolError(f"missing staged file: {name}")
                    if (env.prod / name).exists():
                        raise ToolError(f"refusing to overwrite existing file: {name}")
                    entries.append({"name": name, "sha256": sha256_file(source), "done": False})
                journal = {"job_id": args.job, "entries": entries}
                write_json(journal_path, journal)
                registry.set_state(args.job, "committing")
            for entry in journal["entries"]:
                if entry["done"]:
                    continue
                source = stage / entry["name"]
                target = env.prod / entry["name"]
                if not source.exists():
                    if target.exists() and sha256_file(target) == entry["sha256"]:
                        entry["done"] = True
                        write_json(journal_path, journal)
                        continue
                    raise ToolError(f"staged file vanished before publish: {entry['name']}")
                if target.exists():
                    raise ToolError(f"refusing to overwrite existing file: {entry['name']}")
                os.rename(source, target)
                make_file_shareable(target)
                entry["done"] = True
                write_json(journal_path, journal)
            fsync_dir(env.prod)
            registry.finish(args.job)
            shutil.rmtree(stage, ignore_errors=True)
            return {"job_id": args.job, "state": "committed", "files": [e["name"] for e in journal["entries"]]}
    finally:
        registry.close()


def cmd_reject(env: Env, args) -> dict:
    registry = Registry(env.db_path)
    try:
        with file_lock(env.lock_path):
            job = registry.get_job(args.job)
            if job is None:
                shutil.rmtree(env.job_dir(args.job), ignore_errors=True)
                return {"job_id": args.job, "state": "rejected", "note": "nothing to roll back"}
            if job["state"] in ("committing", "committed"):
                raise ToolError("a committing or committed job cannot be rejected; finish the commit first")
            shutil.rmtree(env.job_dir(args.job), ignore_errors=True)
            registry.release(args.job)
            return {"job_id": args.job, "state": "rejected", "released_listing": job["listing"]}
    finally:
        registry.close()


def cmd_reprint(env: Env, args) -> dict:
    match = SKU_RE.match(args.sku)
    if not match or match.group(1) != env.prefix:
        raise ToolError("invalid SKU")
    if args.sheet not in env.cfg["sheets"]:
        raise ToolError("unknown sheet type")
    layout_path = env.prod / f"{args.sku}_layout.json"
    sticker_path = env.prod / f"{args.sku}.png"
    if not layout_path.is_file() or not sticker_path.is_file():
        raise ToolError("that SKU is not in the production folder")
    layout = read_json(layout_path)
    if sha256_file(sticker_path) != layout["sticker_sha256"]:
        raise ToolError("the sticker file no longer matches its saved layout")
    sheet = layout["sheets"].get(args.sheet)
    if sheet is None:
        raise ToolError("no saved layout for that sheet type")
    sticker = Image.open(sticker_path).convert("RGBA")
    canvas = render_sheet(sticker, sheet, layout["dpi"])
    out_dir = env.staging / "reprints"
    make_dir(env.staging)
    make_dir(out_dir)
    out = out_dir / f"{args.sku}_{args.sheet}_reprint.png"
    digest = save_sheet(canvas, out, layout["dpi"])
    return {
        "sku": args.sku,
        "sheet": args.sheet,
        "output": str(out),
        "copies": sheet["copies"],
        "matches_saved_sheet": digest == sheet["sheet_sha256"],
    }


def cmd_status(env: Env, args) -> dict:
    registry = Registry(env.db_path)
    try:
        if args.job:
            return describe_job(env, registry, args.job)
        return {
            "jobs": registry.all_jobs(),
            "folder_max_listing": scan_folder_max(env),
        }
    finally:
        registry.close()


def cmd_record_error(env: Env, args) -> dict:
    exec_id = require_exec_id(args.exec_id)
    node = args.node if NODE_NAME_RE.match(args.node) else "unknown"
    make_dir(env.state)
    write_json(env.state / "last-error.json", {
        "exec_id": exec_id,
        "node": node,
        "time": now_iso(),
        "message": "A sticker workflow run failed. Open n8n and check the execution list.",
    })
    return {"recorded": True}


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="sticker-tool", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("mkincoming", help="create the incoming directory for an n8n execution")
    p.add_argument("--exec-id", required=True)
    p.set_defaults(func=cmd_mkincoming)

    p = sub.add_parser("intake", help="validate an upload, reserve a listing number, stage the sources")
    p.add_argument("--exec-id", required=True)
    p.set_defaults(func=cmd_intake)

    p = sub.add_parser("process", help="build finished stickers (silhouette and border)")
    p.add_argument("--job", required=True)
    p.set_defaults(func=cmd_process)

    p = sub.add_parser("nest", help="pack copies onto sheets and render previews")
    p.add_argument("--job", required=True)
    p.add_argument("--profile", default="default")
    p.set_defaults(func=cmd_nest)

    p = sub.add_parser("note-approval", help="record the approval link beside the staged job")
    p.add_argument("--job", required=True)
    p.add_argument("--url", required=True)
    p.set_defaults(func=cmd_note_approval)

    p = sub.add_parser("commit", help="publish a nested job into the production folder (restartable)")
    p.add_argument("--job", required=True)
    p.set_defaults(func=cmd_commit)

    p = sub.add_parser("reject", help="discard a staged job and release its listing number")
    p.add_argument("--job", required=True)
    p.set_defaults(func=cmd_reject)

    p = sub.add_parser("reprint", help="re-render a sheet from saved placement coordinates")
    p.add_argument("--sku", required=True)
    p.add_argument("--sheet", required=True)
    p.set_defaults(func=cmd_reprint)

    p = sub.add_parser("status", help="show one job or all jobs")
    p.add_argument("--job")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("record-error", help="note a failed workflow run for the desktop notification")
    p.add_argument("--exec-id", required=True)
    p.add_argument("--node", default="unknown")
    p.set_defaults(func=cmd_record_error)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        env = Env()
        result = args.func(env, args)
    except ToolError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
