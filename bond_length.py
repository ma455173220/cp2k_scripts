#!/usr/bin/env python3
"""
bond_length.py
计算 POSCAR/CONTCAR 中指定两种元素之间的平均键长。

用法：
  python bond_length.py                                        # 读当前目录 POSCAR，交互输入元素
  python bond_length.py -f CONTCAR                            # 指定结构文件
  python bond_length.py -f POSCAR -e Fe O                     # 直接指定元素对
  python bond_length.py -f POSCAR -e Fe O --scale 1.5        # 放宽截断半径，查看全部键分布
  python bond_length.py -f POSCAR -e Fe O --scale 1.5 --rmax 2.5   # 只统计第一壳（< 2.5 Å）
  python bond_length.py -f POSCAR -e Fe O --rmax 2.5 --plot  # 同时输出 matplotlib 分布图
"""

import argparse
import os
import sys
import numpy as np
from ase.io import read
from ase.neighborlist import NeighborList, natural_cutoffs


def calc_bond_lengths(atoms, elem1, elem2, scale=1.0):
    """
    计算 atoms 中 elem1-elem2 之间所有键长（考虑周期性边界条件）。
    scale: 对 natural_cutoffs 的缩放因子，默认 1.0
    """
    cutoffs = natural_cutoffs(atoms, mult=scale)
    nl = NeighborList(cutoffs, self_interaction=False, bothways=True)
    nl.update(atoms)

    symbols = atoms.get_chemical_symbols()
    same_elem = (elem1 == elem2)
    seen = set()
    bond_lengths = []

    for i, sym_i in enumerate(symbols):
        if sym_i not in (elem1, elem2):
            continue

        indices, offsets = nl.get_neighbors(i)

        for j, offset in zip(indices, offsets):
            sym_j = symbols[j]

            # 判断是否为目标元素对
            if same_elem:
                if sym_i != elem1 or sym_j != elem1:
                    continue
            else:
                if {sym_i, sym_j} != {elem1, elem2}:
                    continue

            # 归一化键对标识，正确处理跨边界自镜像（i==j）
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

            # 考虑 PBC 的实际距离
            pos_i = atoms.positions[i]
            pos_j = atoms.positions[j] + np.array(offset) @ atoms.cell
            dist = np.linalg.norm(pos_j - pos_i)
            bond_lengths.append((i, j, dist))

    return bond_lengths


def print_text_histogram(distances, elem1, elem2, bin_width=0.1, bar_max_width=40):
    """
    在终端打印键长分布的文本直方图。
    bin_width: 每个区间的宽度（Å），默认 0.1 Å
    """
    if not distances:
        return

    d_min = np.floor(min(distances) / bin_width) * bin_width
    d_max = np.ceil(max(distances) / bin_width) * bin_width
    bins = np.arange(d_min, d_max + bin_width, bin_width)
    counts, edges = np.histogram(distances, bins=bins)

    max_count = max(counts) if max(counts) > 0 else 1

    print(f'\n── 键长分布直方图（{elem1}-{elem2}，区间宽度 {bin_width} Å）──')
    print(f'  {"区间 (Å)":<18} {"数量":>5}  分布')
    print(f'  {"-"*18}  {"-"*5}  {"-"*bar_max_width}')

    for i, count in enumerate(counts):
        if count == 0:
            continue
        lo, hi = edges[i], edges[i + 1]
        bar_len = int(count / max_count * bar_max_width)
        bar = '█' * bar_len
        print(f'  {lo:.2f} – {hi:.2f} Å    {count:>5}  {bar}')

    print()


def plot_distribution(distances, elem1, elem2, rmax=None, bin_width=0.1, output_file=None):
    """
    使用 matplotlib 绘制键长分布直方图并保存/显示。
    """
    try:
        import matplotlib
        matplotlib.rcParams['font.family'] = 'Times New Roman'
        import matplotlib.pyplot as plt
    except ImportError:
        print('[警告] 未找到 matplotlib，跳过绘图。请安装：pip install matplotlib')
        return

    d_min = np.floor(min(distances) / bin_width) * bin_width
    d_max = np.ceil(max(distances) / bin_width) * bin_width
    bins = np.arange(d_min, d_max + bin_width, bin_width)

    fig, ax = plt.subplots(figsize=(7, 4))

    ax.hist(distances, bins=bins, color='steelblue', edgecolor='black', linewidth=0.6)

    # 标出平均值
    mean_d = np.mean(distances)
    ax.axvline(mean_d, color='crimson', linestyle='--', linewidth=1.2,
               label=f'Mean = {mean_d:.4f} Å')

    # 如果有 rmax，标出截断线
    if rmax is not None:
        ax.axvline(rmax, color='gray', linestyle=':', linewidth=1.2,
                   label=f'--rmax = {rmax:.2f} Å')

    ax.set_xlabel('Bond Length (Å)', fontsize=12)
    ax.set_ylabel('Count', fontsize=12)
    ax.set_title(f'{elem1}–{elem2} Bond Length Distribution', fontsize=13)
    ax.legend(fontsize=10)

    # 黑色坐标轴，内刻度
    for spine in ax.spines.values():
        spine.set_linewidth(1.0)
        spine.set_color('black')
    ax.tick_params(direction='in', top=True, right=True)

    plt.tight_layout()

    if output_file:
        fig.savefig(output_file, dpi=200, bbox_inches='tight')
        print(f'分布图已保存至：{output_file}')
    else:
        plt.show()

    plt.close(fig)


def print_summary(distances, label='全部键'):
    """打印统计摘要"""
    print(f'\n── 统计摘要（{label}）──')
    print(f'  键数   : {len(distances)}')
    print(f'  平均   : {np.mean(distances):.4f} Å')
    print(f'  最短   : {np.min(distances):.4f} Å')
    print(f'  最长   : {np.max(distances):.4f} Å')
    print(f'  标准差 : {np.std(distances):.4f} Å')


def main():
    parser = argparse.ArgumentParser(
        description='计算 POSCAR/CONTCAR 中两种元素之间的键长分布'
    )
    parser.add_argument(
        '-f', '--file',
        default='POSCAR',
        help='结构文件路径（默认：POSCAR）'
    )
    parser.add_argument(
        '-e', '--elements',
        nargs=2,
        metavar=('ELEM1', 'ELEM2'),
        default=None,
        help='要分析的元素对，例如 -e Fe O'
    )
    parser.add_argument(
        '--scale',
        type=float,
        default=1.0,
        help='截断半径缩放因子（默认 1.0；建议先用 1.5 查看全部分布，再用 --rmax 截取第一壳）'
    )
    parser.add_argument(
        '--rmax',
        type=float,
        default=None,
        help='只统计键长 < rmax（Å）的键，用于单独提取第一配位壳层'
    )
    parser.add_argument(
        '--bin-width',
        type=float,
        default=0.1,
        help='直方图区间宽度，单位 Å（默认 0.1）'
    )
    parser.add_argument(
        '--plot',
        action='store_true',
        help='用 matplotlib 输出键长分布图'
    )
    parser.add_argument(
        '--plot-output',
        type=str,
        default=None,
        metavar='FILE',
        help='分布图保存路径（如 bond_dist.png）；不指定则弹窗显示'
    )
    args = parser.parse_args()

    # 校验
    if args.scale <= 0:
        raise ValueError(f'--scale 必须为正数，当前值：{args.scale}')
    if args.rmax is not None and args.rmax <= 0:
        raise ValueError(f'--rmax 必须为正数，当前值：{args.rmax}')
    if not os.path.isfile(args.file):
        raise FileNotFoundError(f'找不到结构文件：{args.file}')

    # 读结构
    atoms = read(args.file, format='vasp')
    symbols_set = sorted(set(atoms.get_chemical_symbols()))
    print(f'结构文件 : {args.file}')
    print(f'包含元素 : {", ".join(symbols_set)}')
    print(f'原子总数 : {len(atoms)}')

    # 确定元素对
    if args.elements:
        elem1, elem2 = args.elements
    else:
        elem1 = input('请输入第一个元素（如 Fe）: ').strip()
        elem2 = input('请输入第二个元素（如 O ）: ').strip()

    for e in (elem1, elem2):
        if e not in symbols_set:
            raise ValueError(f'元素 {e} 不在结构中，可用元素：{", ".join(symbols_set)}')

    print(f'\n分析键对 : {elem1}-{elem2}')
    print(f'截断缩放 : ×{args.scale}')
    if args.rmax:
        print(f'第一壳截断 : rmax = {args.rmax} Å')

    # 计算所有键
    bonds = calc_bond_lengths(atoms, elem1, elem2, scale=args.scale)

    if not bonds:
        print(f'\n未找到 {elem1}-{elem2} 键，尝试增大 --scale（如 --scale 1.5）')
        sys.exit(1)

    all_distances = [d for _, _, d in bonds]

    # 过滤异常短键
    MIN_DIST = 0.5  # Å
    suspicious = [d for d in all_distances if d < MIN_DIST]
    if suspicious:
        print(f'[警告] 发现 {len(suspicious)} 个异常短键（< {MIN_DIST} Å），请检查结构！')
    all_distances = sorted([d for d in all_distances if d >= MIN_DIST])

    # 始终打印全部键的文本直方图（用于判断壳层分界）
    print_text_histogram(all_distances, elem1, elem2, bin_width=args.bin_width)
    print_summary(all_distances, label='全部键')

    # 若指定 --rmax，额外单独统计第一壳
    if args.rmax is not None:
        first_shell = [d for d in all_distances if d < args.rmax]
        if not first_shell:
            print(f'\n[警告] rmax={args.rmax} Å 范围内没有找到键，请调整 --rmax 值')
        else:
            print_summary(first_shell, label=f'第一壳（< {args.rmax} Å）')

    # matplotlib 分布图
    if args.plot:
        plot_distances = all_distances  # 始终画全部，用虚线标出 rmax
        plot_distribution(
            plot_distances, elem1, elem2,
            rmax=args.rmax,
            bin_width=args.bin_width,
            output_file=args.plot_output
        )


if __name__ == '__main__':
    main()
