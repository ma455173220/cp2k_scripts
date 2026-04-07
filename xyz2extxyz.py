#!/usr/bin/env python3
"""
xyz2extxyz.py
将 CP2K 输出的普通 XYZ 转为 Extended XYZ（添加晶格和 pbc 信息）。

晶格来源（三选一，按优先级）：
  1. --cell 手动指定文件路径（cp2k.inp 或 .restart）
  2. 每个子目录内自动查找 cp2k.inp / *.restart
  3. 逐级向上查找父目录

用法：
  python xyz2extxyz.py                              # 自动查找
  python xyz2extxyz.py -d /path/to/data             # 指定数据目录
  python xyz2extxyz.py --cell /path/to/cp2k.inp     # 指定晶格文件
  python xyz2extxyz.py -d /data --cell /ref/cp2k.inp  # 两者都指定
"""

import os
import re
import sys
import glob
import argparse


# ──────────────────────────────────────────────
# 1. 解析晶格
# ──────────────────────────────────────────────

def parse_cell_from_cp2k_file(filepath):
    """
    从 cp2k.inp 或 .restart 文件中读取 &CELL 段的 A/B/C 矢量。
    返回 3×3 列表 [[ax,ay,az],[bx,by,bz],[cx,cy,cz]]，失败返回 None。
    """
    with open(filepath, 'r') as f:
        content = f.read()

    cell_match = re.search(
        r'&CELL\b(.*?)&END\s+CELL',
        content, re.IGNORECASE | re.DOTALL
    )
    if not cell_match:
        return None

    cell_block = cell_match.group(1)
    vectors = {}
    for key in ('A', 'B', 'C'):
        m = re.search(
            rf'^\s*{key}\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)',
            cell_block, re.MULTILINE
        )
        if m:
            vectors[key] = [float(m.group(1)), float(m.group(2)), float(m.group(3))]

    if len(vectors) == 3:
        return [vectors['A'], vectors['B'], vectors['C']]
    return None


def find_lattice_auto(directory):
    """在目录内及父目录中自动查找晶格。"""
    search_dir = directory
    while True:
        # 优先 cp2k.inp
        inp_path = os.path.join(search_dir, 'cp2k.inp')
        if os.path.isfile(inp_path):
            lattice = parse_cell_from_cp2k_file(inp_path)
            if lattice:
                return lattice

        # 其次 *.restart
        for rf in sorted(glob.glob(os.path.join(search_dir, '*.restart'))):
            lattice = parse_cell_from_cp2k_file(rf)
            if lattice:
                return lattice

        parent = os.path.dirname(search_dir)
        if parent == search_dir:
            break
        search_dir = parent

    return None


# ──────────────────────────────────────────────
# 2. 转换单个 XYZ 文件
# ──────────────────────────────────────────────

def convert_xyz_to_extxyz(input_xyz, output_xyz, lattice):
    a, b, c = lattice
    lattice_str = (
        f'{a[0]} {a[1]} {a[2]} '
        f'{b[0]} {b[1]} {b[2]} '
        f'{c[0]} {c[1]} {c[2]}'
    )

    with open(input_xyz, 'r') as f:
        lines = f.readlines()

    out_lines = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue

        try:
            n_atoms = int(line)
        except ValueError:
            i += 1
            continue

        comment_line = lines[i + 1].strip() if (i + 1) < len(lines) else ''

        new_comment = (
            f'Lattice="{lattice_str}" '
            f'Properties=species:S:1:pos:R:3 '
            f'pbc="T T T"'
        )
        if comment_line:
            new_comment += f' comment="{comment_line}"'

        out_lines.append(f'{n_atoms}\n')
        out_lines.append(f'{new_comment}\n')

        for j in range(i + 2, i + 2 + n_atoms):
            if j < len(lines):
                out_lines.append(lines[j])

        i += 2 + n_atoms

    with open(output_xyz, 'w') as f:
        f.writelines(out_lines)


# ──────────────────────────────────────────────
# 3. 批量处理
# ──────────────────────────────────────────────

def process_directory(base_dir, global_lattice=None):
    for root, dirs, files in os.walk(base_dir):
        xyz_files = [f for f in files if f.endswith('.xyz') and not f.endswith('.extxyz')]
        if not xyz_files:
            continue

        # 优先用命令行指定的晶格，否则自动查找
        lattice = global_lattice or find_lattice_auto(root)

        if lattice is None:
            print(f'[跳过] 找不到晶格信息: {root}')
            continue

        for xyz_file in xyz_files:
            input_path  = os.path.join(root, xyz_file)
            output_path = os.path.join(root, xyz_file.replace('.xyz', '.extxyz'))
            try:
                convert_xyz_to_extxyz(input_path, output_path, lattice)
                print(f'[完成] {input_path} → {output_path}')
            except Exception as e:
                print(f'[错误] {input_path}: {e}')


# ──────────────────────────────────────────────
# 入口
# ──────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='将 CP2K XYZ 转为 Extended XYZ（添加晶格周期性）'
    )
    parser.add_argument(
        '-d', '--dir',
        default='.',
        help='要处理的根目录（默认：当前目录）'
    )
    parser.add_argument(
        '--cell',
        default=None,
        help='手动指定晶格文件路径（cp2k.inp 或 *.restart），优先于自动查找'
    )
    args = parser.parse_args()

    # 如果手动指定了晶格文件，预先解析
    global_lattice = None
    if args.cell:
        if not os.path.isfile(args.cell):
            print(f'[错误] 找不到指定的晶格文件: {args.cell}')
            sys.exit(1)
        global_lattice = parse_cell_from_cp2k_file(args.cell)
        if global_lattice is None:
            print(f'[错误] 无法从文件中解析 &CELL 段: {args.cell}')
            sys.exit(1)
        print(f'[晶格] 使用指定文件: {args.cell}')
        for name, vec in zip('ABC', global_lattice):
            print(f'       {name} = {vec}')

    process_directory(args.dir, global_lattice)
