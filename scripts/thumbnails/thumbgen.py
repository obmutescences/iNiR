#!/usr/bin/env python3

# From https://github.com/difference-engine/thumbnail-generator-ubuntu (MIT License)
# Since the script is small and the maintainers seem inactive to accept my PR (#11) I decided to just copy it over.
# When it gets merged and the python package gets updated we can just use it

import os
import sys
import hashlib
import signal
import subprocess
import urllib.parse
from multiprocessing import Pool
from pathlib import Path
from typing import List, Union

import click
from loguru import logger
from tqdm import tqdm

# Pixel sizes for thumbnail directories (freedesktop spec)
thumbnail_pixel_sizes = {
    "normal": 128,
    "large": 256,
    "x-large": 512,
    "xx-large": 1024,
}

current_size = "large"
# iNiR's own cache, not ~/.cache/thumbnails. That one is shared with every other program on
# the desktop, so an entry there is not necessarily ours, not necessarily this file's
# picture, and not necessarily fresh; the shell passes its own root in, this default is for
# running the script by hand.
cache_root = str(
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "quickshell/user/generated/wallpaper/thumbs"
)
active_pool = None
logger.remove()
logger.add(sys.stdout, level="INFO")

# Not /tmp/thumbgen.log: that path is predictable in a world-writable directory,
# so on a shared host another user can pre-create it (or symlink it elsewhere) and
# logger.add() then raises at import time, killing every thumbnail run.
_log_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "inir"
_log_dir.mkdir(parents=True, exist_ok=True)
logger.add(_log_dir / "thumbgen.log", level="DEBUG", rotation="100 MB")


def _worker_init() -> None:
    """Workers use the default SIGTERM action; only the pool owner coordinates."""
    signal.signal(signal.SIGTERM, signal.SIG_DFL)


def _terminate_pool(_signum, _frame) -> None:
    """Do not leave multiprocessing workers in inir.service after QML exits."""
    global active_pool
    if active_pool is not None:
        active_pool.terminate()
        active_pool.join()
        active_pool = None
    raise SystemExit(143)


signal.signal(signal.SIGTERM, _terminate_pool)
signal.signal(signal.SIGINT, _terminate_pool)


def get_thumbnail_path(fpath: str, size_name: str) -> str:
    """Calculate thumbnail path using the same method as QML ThumbnailImage."""
    # Encode each path component (like QML's encodeURIComponent)
    parts = fpath.split("/")
    encoded = "/".join(urllib.parse.quote(p, safe="") for p in parts)
    url = f"file://{encoded}"
    md5 = hashlib.md5(url.encode()).hexdigest()
    return f"{cache_root}/{size_name}/{md5}.png"


def recorded_identity(thumb_path: str) -> str:
    """The source identity an entry was made from, empty when it records none."""
    result = subprocess.run(
        ["identify", "-format", "%[Thumb::MTime]|%[Thumb::Size]", thumb_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def source_identity(fpath: str) -> str:
    st = os.stat(fpath)
    return f"{int(st.st_mtime)}|{st.st_size}"


def make_thumbnail_imagemagick(fpath: str, size_name: str) -> bool:
    """Generate thumbnail using ImageMagick."""
    thumb_path = get_thumbnail_path(fpath, size_name)

    # An entry is only reused for the file as it is now. The key is the file's URI, so a
    # rename is a new entry, but a file replaced under the same name is not — a folder
    # renumbered or restored under its own names used to keep the old picture forever. An
    # entry that records no identity (a video's still frame, or one written before this) is
    # reused as it always was.
    identity = source_identity(fpath)
    if os.path.exists(thumb_path):
        recorded = recorded_identity(thumb_path)
        if not recorded or recorded == identity:
            logger.debug("FRESH       {}".format(fpath))
            return False

    os.makedirs(os.path.dirname(thumb_path), exist_ok=True)

    size = thumbnail_pixel_sizes[size_name]
    # Use [0] suffix to get first frame (works for images and animated gifs). The identity
    # is written into the PNG's text so the next reader can tell which file this is.
    mtime, byte_size = identity.split("|")
    cmd = [
        "magick",
        f"{fpath}[0]",
        "-resize",
        f"{size}x{size}",
        "-define",
        "png:include-chunk=tEXt",
        "-set",
        "Thumb::MTime",
        mtime,
        "-set",
        "Thumb::Size",
        byte_size,
        thumb_path,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, timeout=30)
        if result.returncode == 0:
            logger.debug("OK_MAGICK   {}".format(fpath))
            return True
        else:
            logger.debug("ERROR_MAGICK {}".format(fpath))
            return False
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logger.debug("ERROR_MAGICK {} - {}".format(fpath, str(e)))
        return False


def make_thumbnail(fpath: str) -> bool:
    # One unreadable file must not abort the pool and leave the rest of the folder without thumbnails.
    try:
        return make_thumbnail_imagemagick(fpath, current_size)
    except Exception as e:
        logger.debug("ERROR       {} - {}".format(fpath, e))
        return False


@logger.catch()
def thumbnail_folder(
    *,
    dir_path: Path,
    workers: int,
    only_images: bool,
    recursive: bool,
    machine_progress: bool = False,
) -> None:
    global active_pool
    all_files = get_all_files(dir_path=dir_path, recursive=recursive)
    if only_images:
        all_files = get_all_images(all_files=all_files)
    all_files = [str(fpath) for fpath in all_files]
    if machine_progress:
        completed = 0
        total = len(all_files)
        with Pool(processes=workers, initializer=_worker_init) as p:
            active_pool = p
            try:
                for result in p.imap(make_thumbnail, all_files):
                    completed += 1
                    print(f"PROGRESS {completed}/{total} FILE {all_files[completed - 1]}")
                    sys.stdout.flush()
            finally:
                active_pool = None
    else:
        with Pool(processes=workers, initializer=_worker_init) as p:
            active_pool = p
            try:
                list(tqdm(p.imap(make_thumbnail, all_files), total=len(all_files)))
            finally:
                active_pool = None


def get_all_images(*, all_files: List[Path]) -> List[Path]:
    img_suffixes = [
        ".jpg",
        ".jpeg",
        ".png",
        ".gif",
        ".mp4",
        ".webm",
        ".mkv",
        ".avi",
        ".mov",
    ]
    all_images = [fpath for fpath in all_files if fpath.suffix.lower() in img_suffixes]
    print("Found {} images/videos".format(len(all_images)))
    return all_images


def get_all_files(*, dir_path: Path, recursive: bool) -> List[Path]:
    if not (dir_path.exists() and dir_path.is_dir()):
        raise ValueError(
            "{} doesn't exist or isn't a valid directory!".format(dir_path.resolve())
        )
    if recursive:
        all_files = dir_path.rglob("*")
    else:
        all_files = dir_path.glob("*")
    all_files = [fpath for fpath in all_files if fpath.is_file()]
    print(
        "Found {} files in the directory: {}".format(len(all_files), dir_path.resolve())
    )
    return all_files


@click.command()
@click.option(
    "-d",
    "--img_dirs",
    required=True,
    help='directories to generate thumbnails seperated by space, eg: "dir1/dir2 dir3"',
)
@click.option(
    "-s",
    "--size",
    default="normal",
    type=click.Choice(["normal", "large", "x-large", "xx-large"]),
    help="Thumbnail size: normal, large, x-large, xx-large",
)
@click.option("-w", "--workers", default=1, help="no of cpus to use for processing")
@click.option(
    "-i",
    "--only_images",
    is_flag=True,
    default=False,
    help="Whether to only look for images to be thumbnailed",
)
@click.option(
    "-r",
    "--recursive",
    is_flag=True,
    default=False,
    help="Whether to recursively look for files",
)
@click.option(
    "--machine_progress",
    is_flag=True,
    default=False,
    help="Print machine-readable progress lines instead of a progress bar",
)
@click.option(
    "--cache-dir",
    default=cache_root,
    help="Where thumbnails are written; the shell passes its own root in",
)
def main(
    img_dirs: str,
    size: str,
    workers: str,
    only_images: bool,
    recursive: bool,
    machine_progress: bool,
    cache_dir: str,
) -> None:
    # A folder whose name has spaces is one folder, not several.
    img_dirs = [Path(img_dirs)] if Path(img_dirs).is_dir() else [Path(img_dir) for img_dir in img_dirs.split()]
    global current_size, cache_root
    current_size = size
    cache_root = cache_dir

    for img_dir in img_dirs:
        thumbnail_folder(
            dir_path=img_dir,
            workers=workers,
            only_images=only_images,
            recursive=recursive,
            machine_progress=machine_progress,
        )
    print("Thumbnail Generation Completed!")


if __name__ == "__main__":
    main()
