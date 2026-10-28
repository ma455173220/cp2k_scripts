#!/usr/bin/env python3
"""
cp2k_inp.py -- small toolkit for CP2K input/restart files (importable module + command line).

Input parsing follows the CP2K input rules that matter for editing:
  * section and keyword names are case-insensitive
  * "#" and "!" start a comment (anywhere on the line, outside quotes)
  * "&END" closes the innermost section, with or without the section name
  * sections nest; a path such as FORCE_EVAL/SUBSYS/CELL or just SUBSYS/CELL
    (matched against the end of the full path) selects a section; "/FORCE_EVAL/..." is anchored
  * preprocessor lines (@SET, @INCLUDE, @IF ...) and ${var} values are left untouched when editing;
    get_cell() substitutes simple @SET variables

Cells (3x3, rows = a, b, c in Angstrom) can be read from
  * a CP2K input or restart file (&CELL: A/B/C vectors or ABC [+ ALPHA_BETA_GAMMA], units [angstrom]/[bohr]/[nm],
    MULTIPLE_UNIT_CELL)
  * a CP2K *-1.cell file (one cell per MD/optimisation step; --step selects one, default: the last)
  * a POSCAR/CONTCAR (*.vasp)

Command line:
  cp2k_inp.py get-cell FILE [--step N] [--format vectors|lengths|cellpar|lattice|cp2k] [--fmt .10f]
  cp2k_inp.py has-section FILE SECTION/PATH                 (prints the number of matches; exit 1 if none)
  cp2k_inp.py set-key FILE SECTION/PATH KEY VALUE [-o OUT | -i] [--check]
        VALUE "none" comments the keyword out; a commented-out keyword is uncommented;
        a missing keyword is inserted before the section's &END. Output goes to stdout unless -o/-i.
        --check only prints how many active/commented KEY lines the section has (section must exist once).
  cp2k_inp.py replace-section SRC DST SECTION/PATH [-o OUT | -i]
        replace the section in DST by the same section of SRC (each must exist exactly once)
"""

import argparse
import math
import os
import re
import sys

BOHR = 0.529177210903  # Angstrom
UNITS = {'angstrom': 1.0, 'bohr': BOHR, 'nm': 10.0, 'pm': 0.01}


class InputError(Exception):
    pass


# ----------------------------------------------------------------------------- tokenizer

def split_comment(line):
    """Split a line into (code, comment). The comment starts at the first # or ! outside quotes."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
        elif ch in '#!':
            return line[:i], line[i:]
    return line, ''


class Keyword(object):
    def __init__(self, idx, name, value, commented=False):
        self.idx = idx            # 0-based line index
        self.name = name.upper()
        self.value = value
        self.commented = commented


class Section(object):
    def __init__(self, name, params, start, parent):
        self.name = name.upper()
        self.params = params
        self.start = start        # 0-based index of the &NAME line
        self.end = None           # 0-based index of the &END line
        self.parent = parent
        self.children = []
        self.keywords = []        # direct keywords (active and commented-out ones)
        self.path = (parent.path + [self.name]) if parent is not None and parent.name != '' else [self.name]

    def keyword(self, name, commented=False):
        name = name.upper()
        return [k for k in self.keywords if k.name == name and k.commented == commented]


def parse(lines):
    """Parse a list of lines into a tree of Sections. Returns the root (a pseudo-section named '')."""
    root = Section('', '', -1, None)
    root.path = []
    stack = [root]
    for idx, raw in enumerate(lines):
        code, comment = split_comment(raw.rstrip('\r\n'))
        text = code.strip()
        cur = stack[-1]
        if not text:
            # a commented-out keyword ("# KEY value") is remembered so it can be re-enabled
            m = re.match(r'^\s*[#!]+\s*([A-Za-z_][A-Za-z0-9_\-]*)(?:\s+(.*?))?\s*$', raw.rstrip('\r\n'))
            if m and not raw.lstrip().lstrip('#!').lstrip().startswith('&') and cur is not root:
                cur.keywords.append(Keyword(idx, m.group(1), m.group(2) or '', commented=True))
            continue
        if text.startswith('@'):
            continue  # preprocessor directive
        if text.startswith('&'):
            words = text[1:].split(None, 1)
            name = words[0] if words else ''
            if name.upper() == 'END':
                end_name = words[1].split()[0].upper() if len(words) > 1 else ''
                if cur is root:
                    raise InputError('line %d: "%s" without an open section' % (idx + 1, text))
                if end_name and end_name != cur.name:
                    raise InputError('line %d: "%s" closes &%s (opened on line %d)'
                                     % (idx + 1, text, cur.name, cur.start + 1))
                cur.end = idx
                stack.pop()
            else:
                sec = Section(name, words[1] if len(words) > 1 else '', idx, cur)
                cur.children.append(sec)
                stack.append(sec)
            continue
        words = text.split(None, 1)
        if cur is not root:
            cur.keywords.append(Keyword(idx, words[0], words[1] if len(words) > 1 else ''))
    if len(stack) > 1:
        raise InputError('section &%s (line %d) is never closed' % (stack[-1].name, stack[-1].start + 1))
    return root


def walk(section):
    for child in section.children:
        yield child
        for sub in walk(child):
            yield sub


def find_sections(root, pattern):
    """All sections whose path ends with the given pattern ("A/B/C"); a leading "/" anchors it at the top."""
    anchored = pattern.startswith('/')
    parts = [p.upper() for p in pattern.strip('/').split('/') if p]
    if not parts:
        raise InputError('empty section path')
    found = []
    for sec in walk(root):
        if anchored:
            if sec.path == parts:
                found.append(sec)
        elif sec.path[-len(parts):] == parts:
            found.append(sec)
    return found


def find_one_section(root, pattern, label='file'):
    secs = find_sections(root, pattern)
    if not secs:
        raise InputError('section %s not found in %s' % (pattern, label))
    if len(secs) > 1:
        raise InputError('section %s found %d times in %s (lines %s); give a longer path'
                         % (pattern, len(secs), label, ', '.join(str(s.start + 1) for s in secs)))
    return secs[0]


def read_lines(path):
    with open(path, 'r') as fh:
        return fh.readlines()


# ----------------------------------------------------------------------------- cells

def _variables(lines):
    """Simple @SET variables (name -> value)."""
    variables = {}
    for raw in lines:
        m = re.match(r'^\s*@SET\s+(\S+)\s+(.*?)\s*$', split_comment(raw)[0], re.IGNORECASE)
        if m:
            variables[m.group(1)] = m.group(2)
    return variables


def _numbers(value, variables, what):
    """Parse '[unit] x y z' -> (list of floats, scale to Angstrom)."""
    def subst(m):
        name = m.group(1) or m.group(2)
        for key in (name, name.upper(), name.lower()):
            if key in variables:
                return variables[key]
        raise InputError('%s uses the undefined variable %s' % (what, m.group(0)))
    value = re.sub(r'\$\{(\w+)\}|\$(\w+)', subst, value)
    words = value.split()
    scale = 1.0
    if words and words[0].startswith('['):
        unit = words.pop(0).strip('[]').lower()
        if unit not in UNITS:
            raise InputError('%s: unsupported unit [%s]' % (what, unit))
        scale = UNITS[unit]
    try:
        return [float(w) for w in words], scale
    except ValueError:
        raise InputError('%s: cannot read numbers from "%s"' % (what, value))


def cellpar_to_matrix(a, b, c, alpha, beta, gamma):
    """Cell lengths and angles (degrees) -> 3x3 matrix, a along x, b in the xy plane (CP2K/ASE convention)."""
    al, be, ga = (math.radians(x) for x in (alpha, beta, gamma))
    cx = c * math.cos(be)
    cy = c * (math.cos(al) - math.cos(be) * math.cos(ga)) / math.sin(ga)
    cz2 = c * c - cx * cx - cy * cy
    if cz2 <= 0:
        raise InputError('impossible cell angles %s %s %s' % (alpha, beta, gamma))
    return [[a, 0.0, 0.0], [b * math.cos(ga), b * math.sin(ga), 0.0], [cx, cy, math.sqrt(cz2)]]


def cell_from_section(lines, sec, label='file'):
    variables = _variables(lines)
    vec, abc, angles, multiple = {}, None, [90.0, 90.0, 90.0], [1, 1, 1]
    for kw in sec.keywords:
        if kw.commented:
            continue
        what = '%s line %d (%s)' % (label, kw.idx + 1, kw.name)
        if kw.name in ('A', 'B', 'C'):
            nums, scale = _numbers(kw.value, variables, what)
            if len(nums) != 3:
                raise InputError('%s: expected 3 numbers' % what)
            vec[kw.name] = [x * scale for x in nums]
        elif kw.name == 'ABC':
            nums, scale = _numbers(kw.value, variables, what)
            if len(nums) != 3:
                raise InputError('%s: expected 3 numbers' % what)
            abc = [x * scale for x in nums]
        elif kw.name == 'ALPHA_BETA_GAMMA':
            nums, scale = _numbers(re.sub(r'\[\s*deg\s*\]', '', kw.value, flags=re.IGNORECASE), variables, what)
            if len(nums) != 3:
                raise InputError('%s: expected 3 numbers' % what)
            angles = nums
        elif kw.name == 'MULTIPLE_UNIT_CELL':
            nums, _ = _numbers(kw.value, variables, what)
            multiple = [int(round(x)) for x in nums]
        elif kw.name == 'CELL_FILE_NAME':
            if not (vec or abc):
                raise InputError('%s: CELL_FILE_NAME is not supported, give A/B/C or ABC' % what)
    if len(vec) == 3:
        cell = [vec['A'], vec['B'], vec['C']]
    elif abc is not None:
        cell = cellpar_to_matrix(abc[0], abc[1], abc[2], *angles)
    else:
        raise InputError('no A/B/C or ABC in &CELL of %s (line %d)' % (label, sec.start + 1))
    return [[x * n for x in row] for row, n in zip(cell, multiple)]


def cell_from_input(path):
    lines = read_lines(path)
    root = parse(lines)
    secs = find_sections(root, 'SUBSYS/CELL') or find_sections(root, 'CELL')
    if not secs:
        raise InputError('no &CELL section in %s' % path)
    if len(secs) > 1:
        sys.stderr.write('Warning: %d &CELL sections in %s, using the one on line %d\n'
                         % (len(secs), path, secs[0].start + 1))
    return cell_from_section(lines, secs[0], path)


def is_cell_file(path):
    with open(path, 'r') as fh:
        first = fh.readline()
    return first.lstrip().startswith('#') and 'Ax' in first


def read_cell_file(path):
    """CP2K *-1.cell file -> list of (step, time_fs, 3x3 cell)."""
    frames = []
    with open(path, 'r') as fh:
        for n, raw in enumerate(fh, 1):
            words = raw.split()
            if not words or words[0].startswith('#'):
                continue
            if len(words) < 11:
                raise InputError('%s line %d: expected at least 11 columns' % (path, n))
            v = [float(x) for x in words[2:11]]
            frames.append((int(float(words[0])), float(words[1]), [v[0:3], v[3:6], v[6:9]]))
    if not frames:
        raise InputError('no cell data in %s' % path)
    return frames


def cell_from_cell_file(path, step=None):
    frames = read_cell_file(path)
    if step is None:
        return frames[-1][2]
    for s, _, cell in frames:
        if s == step:
            return cell
    raise InputError('step %d not found in %s (steps %d..%d)' % (step, path, frames[0][0], frames[-1][0]))


def cell_from_poscar(path):
    lines = read_lines(path)
    try:
        scale = float(lines[1].split()[0])
        cell = [[float(x) for x in lines[i].split()[:3]] for i in (2, 3, 4)]
    except (IndexError, ValueError):
        raise InputError('%s does not look like a POSCAR file' % path)
    if scale < 0:  # negative scale = target volume
        scale = (-scale / abs(det3(cell))) ** (1.0 / 3.0)
    return [[x * scale for x in row] for row in cell]


def is_poscar(path):
    base = os.path.basename(path).upper()
    return base.startswith('POSCAR') or base.startswith('CONTCAR') or base.endswith('.VASP')


def get_cell(path, step=None):
    """Cell of a CP2K input/restart, *.cell file (given or last step) or POSCAR -> 3x3 list (Angstrom)."""
    if not os.path.isfile(path):
        raise InputError('file not found: %s' % path)
    if path.endswith('.cell') or is_cell_file(path):
        return cell_from_cell_file(path, step)
    if is_poscar(path):
        return cell_from_poscar(path)
    try:
        return cell_from_input(path)
    except InputError:
        if looks_like_poscar(path):
            return cell_from_poscar(path)
        raise


def looks_like_poscar(path):
    """POSCAR layout: comment, one scale factor, three lines of three numbers."""
    try:
        with open(path, 'r') as fh:
            lines = [fh.readline() for _ in range(5)]
        float(lines[1].split()[0])
        return all(len([float(x) for x in lines[i].split()[:3]]) == 3 for i in (2, 3, 4))
    except (ValueError, IndexError):
        return False


def det3(m):
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def cell_lengths(cell):
    return [math.sqrt(sum(x * x for x in row)) for row in cell]


def cell_angles(cell):
    a, b, c = cell
    la, lb, lc = cell_lengths(cell)

    def ang(u, v, lu, lv):
        return math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(u, v)) / (lu * lv)))))
    return [ang(b, c, lb, lc), ang(a, c, la, lc), ang(a, b, la, lb)]


# ----------------------------------------------------------------------------- editing

def _newline(lines):
    return '\r\n' if lines and lines[0].endswith('\r\n') else '\n'


def keyword_line(indent, name, value, comment=''):
    comment = comment.strip()
    return '%s%s  %s%s' % (indent, name, value, ('  ' + comment) if comment else '')


def set_key(lines, pattern, key, value, label='file'):
    """Set KEY to VALUE in the (unique) section matching pattern. VALUE 'none' comments it out.
    Returns (new_lines, message)."""
    lines = list(lines)
    nl = _newline(lines)
    root = parse(lines)
    sec = find_one_section(root, pattern, label)
    active = sec.keyword(key)
    commented = sec.keyword(key, commented=True)
    where = '/'.join(sec.path)
    if value.lower() == 'none':
        if not active:
            return lines, 'no active %s in %s, nothing to comment out' % (key, where)
        for kw in active:
            raw = lines[kw.idx]
            indent = raw[:len(raw) - len(raw.lstrip())]
            lines[kw.idx] = indent + '# ' + raw.lstrip()
        return lines, 'commented out %s in %s' % (key, where)
    if active or commented:
        kw = (active or commented)[0]
        raw = lines[kw.idx].rstrip('\r\n')
        indent = raw[:len(raw) - len(raw.lstrip())]
        if kw.commented:
            body = raw.lstrip().lstrip('#!').lstrip()
            code, comment = split_comment(body)
        else:
            code, comment = split_comment(raw.lstrip())
        name = code.split()[0]
        lines[kw.idx] = keyword_line(indent, name, value, comment) + nl
        msg = '%s %s = %s in %s' % ('uncommented and set' if kw.commented else 'set', name, value, where)
        if len(active) > 1:
            msg += ' (warning: %d active %s lines, only the first was changed)' % (len(active), key)
        return lines, msg
    # insert before the section's &END, indented like the section's first line + 2
    start = lines[sec.start]
    indent = start[:len(start) - len(start.lstrip())] + '  '
    lines.insert(sec.end, keyword_line(indent, key.upper(), value) + nl)
    return lines, 'added %s %s to %s' % (key.upper(), value, where)


def count_key(lines, pattern, key, label='file'):
    sec = find_one_section(parse(lines), pattern, label)
    return len(sec.keyword(key)) + len(sec.keyword(key, commented=True))


def replace_section(src_lines, dst_lines, pattern, src_label='source', dst_label='target'):
    src = find_one_section(parse(src_lines), pattern, src_label)
    dst = find_one_section(parse(dst_lines), pattern, dst_label)
    block = src_lines[src.start:src.end + 1]
    if block and not block[-1].endswith('\n'):
        block[-1] += _newline(dst_lines)
    # re-indent the block like the section it replaces
    src_indent = block[0][:len(block[0]) - len(block[0].lstrip())]
    dst_indent = dst_lines[dst.start][:len(dst_lines[dst.start]) - len(dst_lines[dst.start].lstrip())]
    if src_indent != dst_indent:
        block = [dst_indent + l[len(src_indent):] if l.startswith(src_indent) and l.strip() else l for l in block]
    return dst_lines[:dst.start] + block + dst_lines[dst.end + 1:]


# ----------------------------------------------------------------------------- command line

def _write(lines, args, src_path):
    text = ''.join(lines)
    if getattr(args, 'in_place', False):
        out = src_path
    else:
        out = getattr(args, 'output', None)
    if out and out != '-':
        with open(out, 'w') as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)


def _format_cell(cell, fmt, spec):
    f = lambda x: format(x + 0.0 if abs(x) > 1e-14 else 0.0, spec)
    if fmt == 'vectors':
        return '\n'.join(' '.join(f(x) for x in row) for row in cell)
    if fmt == 'lengths':
        return ' '.join(f(x) for x in cell_lengths(cell))
    if fmt == 'cellpar':
        return ' '.join(f(x) for x in cell_lengths(cell) + cell_angles(cell))
    if fmt == 'lattice':
        return ' '.join(f(x) for row in cell for x in row)
    if fmt == 'cp2k':
        return '\n'.join(['&CELL'] + ['  %s %s' % (n, ' '.join(f(x) for x in row)) for n, row in zip('ABC', cell)]
                         + ['&END CELL'])
    raise InputError('unknown format %s' % fmt)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd')

    g = sub.add_parser('get-cell', help='print the cell of an input/restart, *.cell or POSCAR file')
    g.add_argument('file')
    g.add_argument('--step', type=int, default=None, help='step of a *.cell file (default: last)')
    g.add_argument('--format', default='vectors', choices=['vectors', 'lengths', 'cellpar', 'lattice', 'cp2k'])
    g.add_argument('--fmt', default='.10f', help='python format spec for numbers (default .10f)')

    h = sub.add_parser('has-section', help='count sections matching a path')
    h.add_argument('file')
    h.add_argument('path')

    s = sub.add_parser('set-key', help='set/comment/insert a keyword in one section')
    s.add_argument('file')
    s.add_argument('path')
    s.add_argument('key')
    s.add_argument('value')
    s.add_argument('-o', '--output')
    s.add_argument('-i', '--in-place', action='store_true')
    s.add_argument('--check', action='store_true', help='only print the number of KEY lines in the section')

    r = sub.add_parser('replace-section', help='replace a section of DST by the one of SRC')
    r.add_argument('src')
    r.add_argument('dst')
    r.add_argument('path')
    r.add_argument('-o', '--output')
    r.add_argument('-i', '--in-place', action='store_true')

    args = p.parse_args(argv)
    try:
        if args.cmd == 'get-cell':
            print(_format_cell(get_cell(args.file, args.step), args.format, args.fmt))
        elif args.cmd == 'has-section':
            n = len(find_sections(parse(read_lines(args.file)), args.path))
            print(n)
            return 0 if n else 1
        elif args.cmd == 'set-key':
            lines = read_lines(args.file)
            if args.check:
                print(count_key(lines, args.path, args.key, args.file))
                return 0
            new, msg = set_key(lines, args.path, args.key, args.value, args.file)
            _write(new, args, args.file)
            sys.stderr.write(msg + '\n')
        elif args.cmd == 'replace-section':
            new = replace_section(read_lines(args.src), read_lines(args.dst), args.path, args.src, args.dst)
            _write(new, args, args.dst)
        else:
            p.print_help()
            return 1
    except (InputError, OSError) as e:
        sys.stderr.write('cp2k_inp.py: error: %s\n' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
