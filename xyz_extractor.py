#!/usr/bin/env python3
"""
xyz_extractor.py — Extract frames from a multi-frame XYZ trajectory file.

Modes:
  -f / --frame      Extract one or more specific frames (0-indexed)
  -s / --stride     Extract every N-th frame
  -r / --random     Randomly extract N frames

All modes support:
  --start INT       First frame to consider (inclusive, default: 0)
  --end   INT       Last frame to consider (exclusive, default: last frame)

Examples:
  # Extract frames 0, 500, and 999
  xyz_extractor.py -i traj.xyz -o out.xyz -f 0 500 999

  # Every 10th frame, only from frame 2000 onward
  xyz_extractor.py -i traj.xyz -o out.xyz -s 10 --start 2000

  # 200 random frames from [1000, end)
  xyz_extractor.py -i traj.xyz -o out.xyz -r 200 --start 1000

  # 50 random frames from frames 1000–3000
  xyz_extractor.py -i traj.xyz -o out.xyz -r 50 --start 1000 --end 3000

  # Dry-run: show what would be extracted without writing
  xyz_extractor.py -i traj.xyz -r 50 --start 1000 --dry-run
"""

import argparse
import random
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# XYZ index builder (streaming — avoids loading the whole file into RAM)
# ---------------------------------------------------------------------------

def build_frame_index(path: Path) -> tuple[list[int], int]:
    """
    Scan the file once and return:
      offsets  — byte offset of the first line of each frame
      num_atoms — number of atoms (assumed constant across all frames)
    """
    offsets: list[int] = []
    num_atoms: int = -1

    with path.open("rb") as fh:
        while True:
            offset = fh.tell()
            header = fh.readline()
            if not header:
                break  # EOF

            try:
                n = int(header.strip())
            except ValueError:
                sys.exit(
                    f"Error: expected atom-count line, got: {header.decode().rstrip()!r}\n"
                    f"(near byte offset {offset})"
                )

            if num_atoms == -1:
                num_atoms = n
            elif n != num_atoms:
                sys.exit(
                    f"Error: inconsistent atom count at frame {len(offsets)} "
                    f"(expected {num_atoms}, got {n})."
                )

            offsets.append(offset)

            # Skip comment line + N atom lines
            for _ in range(n + 1):
                if not fh.readline():
                    sys.exit(f"Error: file truncated inside frame {len(offsets) - 1}.")

    return offsets, num_atoms


# ---------------------------------------------------------------------------
# Frame writer
# ---------------------------------------------------------------------------

def write_frames(
    src_path: Path,
    dst_path: Path,
    frame_indices: list[int],
    offsets: list[int],
    num_atoms: int,
    verbose: bool = True,
) -> None:
    lines_per_frame = num_atoms + 2  # header + comment + atoms
    bytes_per_line: int | None = None  # lazily estimated for seek optimisation

    with src_path.open("rb") as src, dst_path.open("wb") as dst:
        for fi in frame_indices:
            src.seek(offsets[fi])
            for _ in range(lines_per_frame):
                line = src.readline()
                if not line:
                    sys.exit(f"Error: unexpected EOF while reading frame {fi}.")
                dst.write(line)

    if verbose:
        print(f"  Written {len(frame_indices)} frame(s) → {dst_path}")


# ---------------------------------------------------------------------------
# Resolve the active frame window [start, end)
# ---------------------------------------------------------------------------

def resolve_window(total: int, start: int | None, end: int | None) -> tuple[int, int]:
    s = max(0, start) if start is not None else 0
    e = min(total, end) if end is not None else total

    if s >= total:
        sys.exit(
            f"Error: --start {s} is beyond the last frame index {total - 1}."
        )
    if e <= s:
        sys.exit(
            f"Error: effective window [{s}, {e}) is empty "
            f"(total frames: {total})."
        )
    return s, e


# ---------------------------------------------------------------------------
# Mode implementations
# ---------------------------------------------------------------------------

def mode_specific(
    frames_arg: list[int],
    offsets: list[int],
    start: int | None,
    end: int | None,
) -> list[int]:
    total = len(offsets)
    s, e = resolve_window(total, start, end)
    pool = set(range(s, e))

    selected: list[int] = []
    for f in frames_arg:
        if f < 0:
            sys.exit(f"Error: frame index {f} is negative.")
        if f >= total:
            sys.exit(f"Error: frame {f} does not exist (total frames: {total}).")
        if f not in pool:
            sys.exit(
                f"Error: frame {f} is outside the active window [{s}, {e}).\n"
                f"  Remove --start/--end constraints or choose a frame within the window."
            )
        selected.append(f)

    return sorted(set(selected))


def mode_stride(
    stride: int,
    offsets: list[int],
    start: int | None,
    end: int | None,
) -> list[int]:
    if stride < 1:
        sys.exit("Error: --stride must be ≥ 1.")
    total = len(offsets)
    s, e = resolve_window(total, start, end)
    return list(range(s, e, stride))


def mode_random(
    n: int,
    offsets: list[int],
    start: int | None,
    end: int | None,
    seed: int | None,
) -> list[int]:
    if n < 1:
        sys.exit("Error: --random must be ≥ 1.")
    total = len(offsets)
    s, e = resolve_window(total, start, end)
    pool = list(range(s, e))

    if n > len(pool):
        sys.exit(
            f"Error: requested {n} random frames but only {len(pool)} frames "
            f"are available in window [{s}, {e})."
        )

    rng = random.Random(seed)
    selected = sorted(rng.sample(pool, n))
    return selected


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("-i", "--input",  required=True,  help="Input XYZ trajectory file.")
    p.add_argument("-o", "--output", default=None,   help="Output XYZ file (omit with --dry-run).")

    # Extraction modes (mutually exclusive)
    modes = p.add_mutually_exclusive_group(required=True)
    modes.add_argument(
        "-f", "--frame", type=int, nargs="+", metavar="N",
        help="One or more frame indices to extract (0-indexed).",
    )
    modes.add_argument(
        "-s", "--stride", type=int, metavar="N",
        help="Extract every N-th frame.",
    )
    modes.add_argument(
        "-r", "--random", type=int, metavar="N",
        help="Randomly extract N frames.",
    )

    # Window constraints
    p.add_argument("--start", type=int, default=None,
                   help="First frame of the active window (inclusive, 0-indexed, default: 0).")
    p.add_argument("--end",   type=int, default=None,
                   help="Last frame of the active window (exclusive, default: last frame).")

    # Extras
    p.add_argument("--seed",    type=int, default=None,
                   help="Random seed for reproducibility (only used with -r).")
    p.add_argument("--dry-run", action="store_true",
                   help="Print what would be extracted without writing any file.")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Print extra information.")

    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"Error: input file not found: {src}")

    if not args.dry_run and args.output is None:
        sys.exit("Error: --output is required unless --dry-run is used.")

    # ---- Index the trajectory ----
    print(f"Indexing {src} …", end=" ", flush=True)
    offsets, num_atoms = build_frame_index(src)
    total = len(offsets)
    print(f"{total} frames found, {num_atoms} atoms each.")

    # ---- Resolve frame selection ----
    if args.frame is not None:
        selected = mode_specific(args.frame, offsets, args.start, args.end)
    elif args.stride is not None:
        selected = mode_stride(args.stride, offsets, args.start, args.end)
    else:
        selected = mode_random(args.random, offsets, args.start, args.end, args.seed)

    # ---- Report ----
    win_s = args.start if args.start is not None else 0
    win_e = args.end   if args.end   is not None else total
    print(
        f"Active window : frames [{win_s}, {min(win_e, total)})  "
        f"({min(win_e, total) - win_s} frames)"
    )
    print(f"Selected      : {len(selected)} frame(s)")
    if args.verbose or len(selected) <= 20:
        print(f"Frame indices : {selected}")
    else:
        head = selected[:10]
        tail = selected[-5:]
        print(f"Frame indices : {head} … {tail}  (use -v to suppress this summary)")

    if args.dry_run:
        print("[dry-run] No file written.")
        return

    # ---- Write ----
    dst = Path(args.output)
    write_frames(src, dst, selected, offsets, num_atoms, verbose=True)


if __name__ == "__main__":
    main()
