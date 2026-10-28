#!/usr/bin/env python3
"""
xyz2extxyz.py
将 CP2K 输出的普通 XYZ 转为 Extended XYZ（添加晶格和 pbc 信息）。

默认只转换坐标轨迹 *-pos-*.xyz（力 *-frc-*、速度 *-vel-* 等不是坐标）；--all 转换所有 *.xyz。
逐帧流式读写，大轨迹也不会占用大量内存。

晶格来源（按优先级）：
  1. --cell 手动指定文件（cp2k.inp / *.restart / *-1.cell / POSCAR）
  2. 与轨迹同名的 <project>-1.cell（CELL_OPT/NPT：每一帧使用同一步的晶胞）
  3. 每个子目录内自动查找 cp2k.inp / *.restart，再逐级向上查找父目录
&CELL 支持 A/B/C、ABC + ALPHA_BETA_GAMMA、单位 [bohr]/[angstrom]、@SET 变量（由 cp2k_inp.py 解析）。

用法：
  python xyz2extxyz.py                              # 自动查找
  python xyz2extxyz.py -d /path/to/data             # 指定数据目录
  python xyz2extxyz.py --cell /path/to/cp2k.inp     # 指定晶格文件
  python xyz2extxyz.py -d /data --cell /ref/cp2k.inp  # 两者都指定
  python xyz2extxyz.py --all                        # 转换所有 .xyz（不只 *-pos-*.xyz）
"""

import os
import sys
import glob
import shutil
import argparse

# 共享模块 cp2k_inp.py / cp2k_xyz.py：先找本脚本所在目录，再找 PATH
_lib_dir = os.path.dirname(os.path.realpath(__file__))
if not os.path.isfile(os.path.join(_lib_dir, 'cp2k_inp.py')) and shutil.which('cp2k_inp.py'):
    _lib_dir = os.path.dirname(os.path.realpath(shutil.which('cp2k_inp.py')))
sys.path.insert(0, _lib_dir)
try:
    import cp2k_inp
    from cp2k_xyz import iter_xyz, parse_cp2k_comment
except ImportError:
    sys.exit('[错误] 找不到 cp2k_inp.py / cp2k_xyz.py（请放在本脚本同一目录或 PATH 中）')


# ──────────────────────────────────────────────
# 1. 解析晶格
# ──────────────────────────────────────────────

def parse_cell_from_cp2k_file(filepath):
    """
    从 cp2k.inp / .restart / POSCAR（或 .cell 的最后一步）读取晶格。
    返回 3×3 列表 [[ax,ay,az],[bx,by,bz],[cx,cy,cz]]，失败返回 None。
    """
    try:
        return cp2k_inp.get_cell(filepath)
    except (cp2k_inp.InputError, OSError, ValueError):
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


class CellTrajectory(object):
    """*-1.cell 中每一步的晶胞；按帧的步数 i 取晶胞（没有该步时用之前最近的一步）。"""

    def __init__(self, path):
        self.path = path
        self.frames = cp2k_inp.read_cell_file(path)

    def cell_for_step(self, step):
        best = self.frames[0][2]
        for s, _, cell in self.frames:
            if step is None or s > step:
                break
            best = cell
        return best


def cell_file_for(xyz_path):
    """<project>-pos-1.xyz → <project>-1.cell（存在时）。"""
    base = os.path.basename(xyz_path)
    if '-pos-' not in base:
        return None
    project = base.split('-pos-')[0]
    candidate = os.path.join(os.path.dirname(xyz_path), project + '-1.cell')
    return candidate if os.path.isfile(candidate) else None


# ──────────────────────────────────────────────
# 2. 转换单个 XYZ 文件
# ──────────────────────────────────────────────

def lattice_string(lattice):
    a, b, c = lattice
    return (
        f'{a[0]} {a[1]} {a[2]} '
        f'{b[0]} {b[1]} {b[2]} '
        f'{c[0]} {c[1]} {c[2]}'
    )


def convert_xyz_to_extxyz(input_xyz, output_xyz, lattice):
    """lattice: 3×3 列表（所有帧相同），或 CellTrajectory（每帧按步数取晶胞）。"""
    with open(output_xyz, 'w') as out:
        for frame in iter_xyz(input_xyz):
            if isinstance(lattice, CellTrajectory):
                cell = lattice.cell_for_step(parse_cp2k_comment(frame.comment).get('i'))
            else:
                cell = lattice
            comment_line = frame.comment.strip()

            new_comment = (
                f'Lattice="{lattice_string(cell)}" '
                f'Properties=species:S:1:pos:R:3 '
                f'pbc="T T T"'
            )
            if comment_line:
                new_comment += f' comment="{comment_line}"'

            out.write(f'{frame.natoms}\n')
            out.write(f'{new_comment}\n')
            out.writelines(line for line in frame.atom_lines if line)


# ──────────────────────────────────────────────
# 3. 批量处理
# ──────────────────────────────────────────────

def is_position_file(name):
    return '-pos-' in name


def process_directory(base_dir, global_lattice=None, convert_all=False):
    for root, dirs, files in os.walk(base_dir):
        xyz_files = [f for f in files if f.endswith('.xyz') and not f.endswith('.extxyz')]
        if not convert_all:
            skipped = [f for f in xyz_files if not is_position_file(f)]
            xyz_files = [f for f in xyz_files if is_position_file(f)]
            if skipped:
                print(f'[跳过] 非坐标轨迹（需要时用 --all）: {", ".join(os.path.join(root, f) for f in sorted(skipped))}')
        if not xyz_files:
            continue

        for xyz_file in sorted(xyz_files):
            input_path  = os.path.join(root, xyz_file)
            output_path = os.path.join(root, xyz_file.replace('.xyz', '.extxyz'))

            # 优先用命令行指定的晶格，其次同名 .cell（逐帧），否则自动查找
            lattice = global_lattice
            if lattice is None:
                cell_path = cell_file_for(input_path)
                if cell_path:
                    try:
                        lattice = CellTrajectory(cell_path)
                        print(f'[晶格] 逐帧使用 {cell_path}')
                    except (cp2k_inp.InputError, ValueError) as e:
                        print(f'[警告] 无法读取 {cell_path}: {e}')
                if lattice is None:
                    lattice = find_lattice_auto(root)

            if lattice is None:
                print(f'[跳过] 找不到晶格信息: {root}')
                continue

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
        help='手动指定晶格文件（cp2k.inp / *.restart / *-1.cell / POSCAR），优先于自动查找；'
             '*-1.cell 时每帧使用同一步的晶胞'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='转换所有 .xyz（默认只转换坐标轨迹 *-pos-*.xyz）'
    )
    args = parser.parse_args()

    # 如果手动指定了晶格文件，预先解析
    global_lattice = None
    if args.cell:
        if not os.path.isfile(args.cell):
            print(f'[错误] 找不到指定的晶格文件: {args.cell}')
            sys.exit(1)
        try:
            if args.cell.endswith('.cell') or cp2k_inp.is_cell_file(args.cell):
                global_lattice = CellTrajectory(args.cell)
            else:
                global_lattice = cp2k_inp.get_cell(args.cell)
        except (cp2k_inp.InputError, ValueError) as e:
            print(f'[错误] 无法从文件中解析晶格: {args.cell}（{e}）')
            sys.exit(1)
        print(f'[晶格] 使用指定文件: {args.cell}')
        if not isinstance(global_lattice, CellTrajectory):
            for name, vec in zip('ABC', global_lattice):
                print(f'       {name} = {vec}')

    process_directory(args.dir, global_lattice, convert_all=args.all)
