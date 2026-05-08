#!/usr/bin/env python3
"""
bond_length_traj.py
对多帧 XYZ 轨迹逐帧计算指定元素对的键长，再跨帧做统计聚合。

支持两种统计方法（同时输出供对比）：
  方法1: 每帧求均值 → 跨帧再平均（帧间标准差，反映帧与帧的波动）
  方法2: 所有键长 flatten → 直接平均（键间标准差，反映键长离散程度）

用法示例：
  # 最简单：从 traj.xyz 读取，指定元素对和第一壳截断
  python bond_length_traj.py -i traj.xyz -e Bi O --rmax 2.2

  # XYZ 不含晶胞时，从 POSCAR 补充晶胞信息
  python bond_length_traj.py -i traj.xyz -e Fe O --rmax 2.2 --cell POSCAR

  # 放宽截断半径（先看全分布，再定 rmax）
  python bond_length_traj.py -i traj.xyz -e Fe O --scale 1.5

  # 输出图像（自动保存为 bond_length_traj.png）
  python bond_length_traj.py -i traj.xyz -e Fe O --rmax 2.2 --plot

  # 保存图到指定路径
  python bond_length_traj.py -i traj.xyz -e Fe O --rmax 2.2 --plot --plot-output bi_o.png

  # 与 xyz_extractor.py 联用
  python xyz_extractor.py -i aimd.xyz -o sample.xyz -r 100 --start 2000
  python bond_length_traj.py -i sample.xyz -e Fe O --rmax 2.2 --cell POSCAR --plot
"""

import argparse
import sys
import warnings
import numpy as np
from pathlib import Path


# ──────────────────────────────────────────────────────────────────────────────
# 键长计算核心（支持 PBC）
# ──────────────────────────────────────────────────────────────────────────────

def calc_bond_lengths_pbc(atoms, elem1, elem2, scale: float = 1.0) -> list:
    from ase.neighborlist import NeighborList, natural_cutoffs

    cutoffs = natural_cutoffs(atoms, mult=scale)
    nl = NeighborList(cutoffs, self_interaction=False, bothways=True)
    nl.update(atoms)

    symbols = atoms.get_chemical_symbols()
    same_elem = (elem1 == elem2)
    seen = set()
    distances = []

    for i, sym_i in enumerate(symbols):
        if sym_i not in (elem1, elem2):
            continue
        indices, offsets = nl.get_neighbors(i)
        for j, offset in zip(indices, offsets):
            sym_j = symbols[j]
            if same_elem:
                if sym_i != elem1 or sym_j != elem1:
                    continue
            else:
                if {sym_i, sym_j} != {elem1, elem2}:
                    continue

            if i == j:
                neg = tuple(-o for o in offset)
                key = (i, j, min(tuple(offset), neg))
            elif i < j:
                key = (i, j, tuple(offset))
            else:
                key = (j, i, tuple(-o for o in offset))

            if key in seen:
                continue
            seen.add(key)

            pos_i = atoms.positions[i]
            pos_j = atoms.positions[j] + np.array(offset) @ atoms.cell
            distances.append(float(np.linalg.norm(pos_j - pos_i)))

    return distances


def calc_bond_lengths_no_pbc(atoms, elem1, elem2, rmax: float) -> list:
    symbols = np.array(atoms.get_chemical_symbols())
    pos = atoms.positions
    idx_a = np.where(symbols == elem1)[0]
    idx_b = np.where(symbols == elem2)[0]
    same_elem = (elem1 == elem2)

    distances = []
    for i in idx_a:
        for j in idx_b:
            if same_elem and j <= i:
                continue
            d = float(np.linalg.norm(pos[i] - pos[j]))
            if d < rmax:
                distances.append(d)
    return distances


# ──────────────────────────────────────────────────────────────────────────────
# 读取帧序列
# ──────────────────────────────────────────────────────────────────────────────

def load_frames(xyz_path: Path, cell_src):
    from ase.io import read

    print(f"读取轨迹: {xyz_path} ... ", end="", flush=True)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        frames = read(str(xyz_path), index=":", format="extxyz")

    if not isinstance(frames, list):
        frames = [frames]

    print(f"{len(frames)} 帧")

    cell0 = frames[0].get_cell()
    has_cell = (cell0.volume > 1e-3)

    if not has_cell and cell_src is None:
        print(
            "[警告] XYZ 文件不含晶胞信息，且未指定 --cell。\n"
            "       将退化为无 PBC 的暴力搜索（仅在 --rmax 限制下有效）。\n"
            "       建议用 --cell POSCAR 补充晶胞以获得正确 PBC 计算。"
        )

    if cell_src is not None:
        ref = read(str(cell_src), format="vasp")
        cell = ref.get_cell()
        pbc = [True, True, True]
        for atoms in frames:
            atoms.set_cell(cell)
            atoms.set_pbc(pbc)
        print(f"晶胞来源: {cell_src}  ({cell[0,0]:.3f} x {cell[1,1]:.3f} x {cell[2,2]:.3f} A^3)")
    elif has_cell:
        for atoms in frames:
            atoms.set_pbc([True, True, True])

    return frames, has_cell or (cell_src is not None)


# ──────────────────────────────────────────────────────────────────────────────
# 逐帧统计
# ──────────────────────────────────────────────────────────────────────────────

def process_frames(frames, elem1, elem2, scale, rmax, use_pbc):
    frame_means = []
    frame_counts = []
    all_raw = []   # 每帧筛选后的键长列表

    skipped = 0
    for fi, atoms in enumerate(frames):
        if use_pbc:
            dists = calc_bond_lengths_pbc(atoms, elem1, elem2, scale=scale)
        else:
            if rmax is None:
                sys.exit("错误: 无晶胞时必须指定 --rmax 以限制搜索范围。")
            dists = calc_bond_lengths_no_pbc(atoms, elem1, elem2, rmax=rmax * 1.5)

        dists = [d for d in dists if d >= 0.5]

        if rmax is not None:
            dists_shell = [d for d in dists if d < rmax]
        else:
            dists_shell = dists

        all_raw.append(dists_shell)

        if not dists_shell:
            skipped += 1
            continue

        frame_means.append(float(np.mean(dists_shell)))
        frame_counts.append(len(dists_shell))

    if skipped:
        print(f"[警告] {skipped} 帧未找到 {elem1}-{elem2} 键（可能需要调整 --scale 或 --rmax）。")

    return frame_means, frame_counts, all_raw


# ──────────────────────────────────────────────────────────────────────────────
# 输出统计摘要（同时展示两种方法）
# ──────────────────────────────────────────────────────────────────────────────

def print_summary(frame_means, frame_counts, all_raw, elem1, elem2, rmax):
    # 方法1：帧均值再平均
    m1_mean = float(np.mean(frame_means))
    m1_std  = float(np.std(frame_means, ddof=1)) if len(frame_means) > 1 else 0.0
    mean_count = float(np.mean(frame_counts))

    # 方法2：所有键长 flatten 后统计
    flat = [d for frame in all_raw for d in frame]
    m2_mean = float(np.mean(flat))
    m2_std  = float(np.std(flat, ddof=1)) if len(flat) > 1 else 0.0

    shell_str = f" < {rmax} A" if rmax else ""
    w = 54

    print(f"\n{'='*w}")
    print(f"  {elem1}-{elem2} 键长统计  ({len(frame_means)} 帧){shell_str}")
    print(f"{'='*w}")
    print(f"  有效帧数         : {len(frame_means)}")
    print(f"  总键数           : {len(flat)}")
    print(f"  平均键数/帧      : {mean_count:.1f}")

    print(f"\n  [方法1]  逐帧均值 -> 跨帧再平均")
    print(f"    均值           : {m1_mean:.4f} A")
    print(f"    标准差(帧间)   : {m1_std:.4f} A   <- 帧与帧之间的波动")
    print(f"    帧均值范围     : [{np.min(frame_means):.4f}, {np.max(frame_means):.4f}] A")
    print(f"    帧均值中位数   : {np.median(frame_means):.4f} A")

    print(f"\n  [方法2]  所有键长 flatten -> 直接平均")
    print(f"    均值           : {m2_mean:.4f} A")
    print(f"    标准差(键间)   : {m2_std:.4f} A   <- 所有键的离散程度")
    print(f"    键长范围       : [{np.min(flat):.4f}, {np.max(flat):.4f}] A")
    print(f"    键长中位数     : {np.median(flat):.4f} A")

    diff = abs(m1_mean - m2_mean)
    note = "一致" if diff < 0.0005 else "有差异（每帧键数不均匀）"
    print(f"\n  两种方法均值差   : {diff:.4f} A  ({note})")
    print(f"{'='*w}")

    return m1_mean, m1_std, m2_mean, m2_std, flat


# ──────────────────────────────────────────────────────────────────────────────
# 绘图（3 子图：逐帧曲线、帧均值分布、全部键长分布）
# ──────────────────────────────────────────────────────────────────────────────

def plot_results(frame_means, flat, elem1, elem2, rmax,
                 bin_width_frame=0.02, bin_width_bond=0.05, output_file=None):
    try:
        import matplotlib
        import matplotlib.pyplot as plt
        matplotlib.rcParams['font.family'] = 'Times New Roman'
        matplotlib.rcParams['font.size'] = 11
    except ImportError:
        print("[警告] 未找到 matplotlib，跳过绘图。")
        return

    m1_mean = np.mean(frame_means)
    m1_std  = np.std(frame_means, ddof=1) if len(frame_means) > 1 else 0.0
    m2_mean = np.mean(flat)
    m2_std  = np.std(flat, ddof=1) if len(flat) > 1 else 0.0

    fig, axes = plt.subplots(1, 3, figsize=(16, 4.5))

    # ── 图1：逐帧均值折线 ──
    ax = axes[0]
    ax.plot(frame_means, color="steelblue", linewidth=0.8, alpha=0.85, label="Per-frame mean")
    ax.axhline(m1_mean, color="crimson", linestyle="--", linewidth=1.2,
               label=f"Mean = {m1_mean:.4f} A")
    ax.axhline(m1_mean + m1_std, color="darkorange", linestyle=":", linewidth=1.0,
               label=f"±std = {m1_std:.4f} A")
    ax.axhline(m1_mean - m1_std, color="darkorange", linestyle=":", linewidth=1.0)
    ax.fill_between(range(len(frame_means)),
                    m1_mean - m1_std, m1_mean + m1_std,
                    color="darkorange", alpha=0.12)
    ax.set_xlabel("Frame index", fontsize=12)
    ax.set_ylabel("Mean bond length (A)", fontsize=12)
    ax.set_title(f"[Method 1]  {elem1}-{elem2}  per-frame mean", fontsize=12)
    ax.legend(fontsize=9)
    _style_ax(ax)

    # ── 图2：帧均值分布直方图（方法1）──
    ax = axes[1]
    lo = np.floor(min(frame_means) / bin_width_frame) * bin_width_frame
    hi = np.ceil( max(frame_means) / bin_width_frame) * bin_width_frame
    bins = np.arange(lo, hi + bin_width_frame, bin_width_frame)
    ax.hist(frame_means, bins=bins, color="steelblue", edgecolor="black", linewidth=0.6)
    ax.axvline(m1_mean, color="crimson", linestyle="--", linewidth=1.2,
               label=f"Mean = {m1_mean:.4f} A")
    ax.axvline(m1_mean + m1_std, color="darkorange", linestyle=":", linewidth=1.0,
               label=f"±1 std = {m1_std:.4f} A")
    ax.axvline(m1_mean - m1_std, color="darkorange", linestyle=":", linewidth=1.0)
    ax.set_xlabel("Mean bond length (A)", fontsize=12)
    ax.set_ylabel("Count (frames)", fontsize=12)
    rmax_str = f"  rmax={rmax} A" if rmax else ""
    ax.set_title(f"[Method 1]  distribution of frame means{rmax_str}", fontsize=12)
    ax.legend(fontsize=9)
    _style_ax(ax)

    # ── 图3：全部键长分布直方图（方法2）──
    ax = axes[2]
    lo = np.floor(min(flat) / bin_width_bond) * bin_width_bond
    hi = np.ceil( max(flat) / bin_width_bond) * bin_width_bond
    bins = np.arange(lo, hi + bin_width_bond, bin_width_bond)
    ax.hist(flat, bins=bins, color="mediumseagreen", edgecolor="black", linewidth=0.6)
    ax.axvline(m2_mean, color="crimson", linestyle="--", linewidth=1.2,
               label=f"Mean = {m2_mean:.4f} A")
    ax.axvline(m2_mean + m2_std, color="darkorange", linestyle=":", linewidth=1.0,
               label=f"±1 std = {m2_std:.4f} A")
    ax.axvline(m2_mean - m2_std, color="darkorange", linestyle=":", linewidth=1.0)
    ax.set_xlabel("Bond length (A)", fontsize=12)
    ax.set_ylabel("Count (bonds)", fontsize=12)
    ax.set_title(f"[Method 2]  all bonds flattened{rmax_str}", fontsize=12)
    ax.legend(fontsize=9)
    _style_ax(ax)

    plt.tight_layout()

    out = output_file if output_file else "bond_length_traj.png"
    fig.savefig(out, dpi=200, bbox_inches="tight")
    print(f"图像已保存: {out}")
    plt.close(fig)


def _style_ax(ax):
    for spine in ax.spines.values():
        spine.set_linewidth(0.8)
        spine.set_color("black")
    ax.tick_params(direction="in", top=True, right=True, labelsize=10)


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

def build_parser():
    p = argparse.ArgumentParser(
        description="对多帧 XYZ 轨迹逐帧统计指定键长，再跨帧聚合（双方法对比）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("-i", "--input",    required=True,
                   help="多帧 XYZ 轨迹文件")
    p.add_argument("-e", "--elements", nargs=2, metavar=("ELEM1", "ELEM2"), required=True,
                   help="要分析的元素对，例如 -e Fe O")
    p.add_argument("--cell",           default=None,
                   help="当 XYZ 不含晶胞时，从此 POSCAR/CONTCAR 读取晶胞（推荐）")
    p.add_argument("--scale",          type=float, default=1.0,
                   help="natural_cutoffs 缩放因子（默认 1.0；建议先用 1.5 看全分布）")
    p.add_argument("--rmax",           type=float, default=None,
                   help="只统计 < rmax (A) 的键（第一配位壳截断）")
    p.add_argument("--no-pbc",         action="store_true",
                   help="强制不使用 PBC（分子体系，必须配合 --rmax）")
    p.add_argument("--bin-width-frame", type=float, default=0.02,
                   help="图2（帧均值分布）直方图区间宽度，单位 A（默认 0.02）")
    p.add_argument("--bin-width-bond",  type=float, default=0.05,
                   help="图3（全部键长分布）直方图区间宽度，单位 A（默认 0.05）")
    p.add_argument("--plot",           action="store_true",
                   help="输出 3 张图（逐帧曲线、帧均值分布、全部键长分布）")
    p.add_argument("--plot-output",    default=None, metavar="FILE",
                   help="图像保存路径（默认: bond_length_traj.png）")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"错误: 找不到输入文件: {src}")

    cell_src = Path(args.cell) if args.cell else None
    if cell_src and not cell_src.exists():
        sys.exit(f"错误: 找不到晶胞文件: {cell_src}")

    frames, use_pbc = load_frames(src, cell_src)

    if args.no_pbc:
        use_pbc = False

    all_syms = set()
    for atoms in frames[:5]:
        all_syms.update(atoms.get_chemical_symbols())
    elem1, elem2 = args.elements
    for e in (elem1, elem2):
        if e not in all_syms:
            sys.exit(f"错误: 元素 {e} 在轨迹前几帧中未找到，可用元素: {sorted(all_syms)}")

    print(f"\n分析键对  : {elem1}-{elem2}")
    print(f"截断缩放  : x{args.scale}")
    print(f"PBC 模式  : {'是' if use_pbc else '否（无周期性边界）'}")
    if args.rmax:
        print(f"第一壳截断: rmax = {args.rmax} A")
    else:
        print("第一壳截断: 未设置（统计所有键，建议指定 --rmax）")

    print("\n逐帧计算中 ...")

    frame_means, frame_counts, all_raw = process_frames(
        frames, elem1, elem2,
        scale=args.scale,
        rmax=args.rmax,
        use_pbc=use_pbc,
    )

    if not frame_means:
        sys.exit(f"\n错误: 所有帧均未找到 {elem1}-{elem2} 键。\n"
                 f"请尝试: 增大 --scale（如 1.5），或检查元素名称。")

    m1_mean, m1_std, m2_mean, m2_std, flat = print_summary(
        frame_means, frame_counts, all_raw, elem1, elem2, args.rmax
    )

    if args.plot:
        plot_results(
            frame_means, flat,
            elem1, elem2,
            rmax=args.rmax,
            bin_width_frame=args.bin_width_frame,
            bin_width_bond=args.bin_width_bond,
            output_file=args.plot_output,
        )


if __name__ == "__main__":
    main()
