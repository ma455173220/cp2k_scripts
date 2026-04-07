#!/usr/bin/env python3
"""
bond_length.py
计算 POSCAR/CONTCAR 中指定两种元素之间的平均键长。

用法：
  python bond_length.py                                  # 读当前目录 POSCAR，交互输入元素
  python bond_length.py -f CONTCAR                      # 指定结构文件
  python bond_length.py -f POSCAR -e Fe O               # 直接指定元素对
  python bond_length.py -f POSCAR -e Fe O --scale 1.2   # 放宽截断半径 20%
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


def main():
    parser = argparse.ArgumentParser(
        description='计算 POSCAR/CONTCAR 中两种元素之间的平均键长'
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
        help='截断半径缩放因子（默认 1.0，增大可捕获更长的键）'
    )
    args = parser.parse_args()

    # 校验参数
    if args.scale <= 0:
        raise ValueError(f'--scale 必须为正数，当前值：{args.scale}')

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

    bonds = calc_bond_lengths(atoms, elem1, elem2, scale=args.scale)

    if not bonds:
        print(f'\n未找到 {elem1}-{elem2} 键，尝试增大 --scale（如 --scale 1.2）')
        sys.exit(1)

    distances = [d for _, _, d in bonds]

    # 过滤异常短键
    MIN_DIST = 0.5  # Å
    suspicious = [d for d in distances if d < MIN_DIST]
    if suspicious:
        print(f'[警告] 发现 {len(suspicious)} 个异常短键（< {MIN_DIST} Å），请检查结构！')
    distances = [d for d in distances if d >= MIN_DIST]

    print(f'\n找到键数 : {len(distances)}')
    print(f'平均键长 : {np.mean(distances):.4f} Å')
    print(f'最短键长 : {np.min(distances):.4f} Å')
    print(f'最长键长 : {np.max(distances):.4f} Å')
    print(f'标准差   : {np.std(distances):.4f} Å')


if __name__ == '__main__':
    main()
