#!/usr/bin/env python3
"""
cp2k_conv_analyse.py -- generic analysis of a convergence test (one CP2K run per directory).

Test directories
  * default: every sub-directory with a generation_info.txt (written by cp2k_para_conv.sh);
    the parameter and value are read from it
  * -p PATTERN: directories matching a glob (cutoff_*Ry, U_*, rel_cutoff_*) or a prefix (kpoints_ -> kpoints_*);
    the value is taken from the directory name (prefix and a trailing "Ry" removed)
  Directories are sorted numerically by value ("MONKHORST-PACK 2 2 2" sorts as (2, 2, 2)).

Per directory (newest *.out, or -O NAME; Slurm logs slurm-*.out are ignored), one streaming pass:
  status         finished ("PROGRAM ENDED AT"), failed (CP2K "ABORT" message), running/incomplete
  SCF_NC         number of "SCF run NOT converged" messages
  E [Ha]         last "ENERGY| Total FORCE_EVAL ( QS ) energy"
  natoms         "- Atoms:" (first occurrence);  E/atom
  dE_prev, dE_ref  E/atom change vs the previous finished point and vs the reference point
                 (default: the last finished point, i.e. the most accurate one), in meV/atom
  SCF            steps of the last "SCF run converged in N steps"
  time [s]       wall time (last field of the " CP2K   1 ..." timing line)
  optional columns, shown when found in any output:
    P [bar]      "Internal pressure [bar]" (CELL_OPT) or STRESS| "1/3 Trace" [GPa] converted to bar
    gap [eV]     last "HOMO - LUMO gap" / "Band gap" line (value converted to eV if printed in a.u.)
    E_F [eV]     last "Fermi energy" line (value converted to eV if printed in a.u.)
    grids        "count for grid" of the first SCF (with --grids)
  NOTE: the pressure/gap/Fermi line formats differ between CP2K versions; check them on your outputs.

"converged at": the first value from which |dE_ref| stays below the threshold (-t, default 1 meV/atom)
for all later finished points.

Output: aligned table on stdout + TSV file (-o, default conv_analysis.tsv); --plot PNG plots dE_ref.

Usage:
  cp2k_conv_analyse.py                               # directories made by cp2k_para_conv.sh
  cp2k_conv_analyse.py -p 'cutoff_*Ry'               # cp2k_cutoff_conv.sh directories
  cp2k_conv_analyse.py -p kpoints_ -O Si_bulk.out    # kpoints_analyse.sh directories
  cp2k_conv_analyse.py -p U_ -t 0.5 --ref first --plot conv.png --grids
"""

import argparse
import glob
import math
import os
import re
import signal
import sys

HARTREE_TO_MEV = 27211.386245988
HARTREE_TO_EV = 27.211386245988

RE_ENERGY = re.compile(r'ENERGY\| Total FORCE_EVAL')
RE_ATOMS = re.compile(r'^\s*-\s*Atoms:\s*(\d+)')
RE_SCF_OK = re.compile(r'SCF run converged in\s+(\d+)\s+steps')
RE_TIMING = re.compile(r'^ CP2K\s+1\s')
RE_PRESSURE_BAR = re.compile(r'Internal pressure \[bar\]', re.IGNORECASE)
RE_STRESS_TRACE = re.compile(r'STRESS\|\s+1/3 Trace', re.IGNORECASE)
RE_GAP = re.compile(r'HOMO\s*-\s*LUMO gap|Band gap', re.IGNORECASE)
RE_FERMI = re.compile(r'Fermi energy', re.IGNORECASE)
RE_NGRIDS = re.compile(r'QS\| Number of grid levels:\s*(\d+)')
RE_GRID = re.compile(r'^\s*count for grid\s+\d+:\s+(\d+)')
RE_NUMBER = re.compile(r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?')


def last_number(line):
    nums = RE_NUMBER.findall(line)
    return float(nums[-1]) if nums else None


def to_ev(line, value):
    """Value of a gap/Fermi line in eV: lines that say [eV] are kept, otherwise Hartree (a.u.) is assumed."""
    if value is None:
        return None
    return value if 'ev' in line.lower() else value * HARTREE_TO_EV


def parse_output(path):
    """One streaming pass over a CP2K output file."""
    r = {'finished': False, 'failed': False, 'scf_nc': 0, 'energy': None, 'natoms': None, 'scf_steps': None,
         'walltime': None, 'pressure': None, 'gap': None, 'fermi': None, 'grids': []}
    ngrids = None
    with open(path, 'r', errors='replace') as fh:
        for line in fh:
            if 'PROGRAM ENDED AT' in line:
                r['finished'] = True
            elif 'ABORT' in line:
                r['failed'] = True
            elif 'SCF run NOT converged' in line:
                r['scf_nc'] += 1
            elif RE_ENERGY.search(line):
                r['energy'] = last_number(line)
            elif r['natoms'] is None and RE_ATOMS.match(line):
                r['natoms'] = int(RE_ATOMS.match(line).group(1))
            elif RE_SCF_OK.search(line):
                r['scf_steps'] = int(RE_SCF_OK.search(line).group(1))
            elif RE_TIMING.match(line):
                r['walltime'] = last_number(line)
            elif RE_PRESSURE_BAR.search(line):
                r['pressure'] = last_number(line)
            elif RE_STRESS_TRACE.search(line):
                v = last_number(line)
                r['pressure'] = v * 1.0e4 if v is not None else None   # GPa -> bar
            elif RE_GAP.search(line):
                r['gap'] = to_ev(line, last_number(line))
            elif RE_FERMI.search(line):
                r['fermi'] = to_ev(line, last_number(line))
            elif ngrids is None and RE_NGRIDS.search(line):
                ngrids = int(RE_NGRIDS.search(line).group(1))
            elif ngrids is not None and len(r['grids']) < ngrids and RE_GRID.match(line):
                r['grids'].append(int(RE_GRID.match(line).group(1)))
    return r


def newest_out(directory, name=None):
    if name:
        path = os.path.join(directory, name)
        return path if os.path.isfile(path) else None
    outs = [p for p in glob.glob(os.path.join(directory, '*.out'))
            if not os.path.basename(p).startswith('slurm-')]
    return max(outs, key=os.path.getmtime) if outs else None


def read_generation_info(directory):
    info = {}
    with open(os.path.join(directory, 'generation_info.txt')) as fh:
        for line in fh:
            if '=' in line:
                k, v = line.rstrip('\n').split('=', 1)
                info[k.strip()] = v.strip()
    return info


def value_key(value):
    """Numeric sort key of a value string: tuple of its numbers; 'none' first, non-numeric values last."""
    if value.lower() == 'none':
        return (0, ())
    nums = RE_NUMBER.findall(value.replace(':', ' ').replace('_', ' '))
    if nums:
        return (1, tuple(float(x) for x in nums))
    return (2, (value,))


def find_tests(pattern):
    """List of (value, directory, parameter) sorted by value."""
    tests = []
    if pattern is None:
        for info_file in sorted(glob.glob(os.path.join('*', 'generation_info.txt'))):
            d = os.path.dirname(info_file)
            info = read_generation_info(d)
            tests.append((info.get('modified_value', d), d, info.get('modified_param', '')))
    else:
        has_glob = any(c in pattern for c in '*?[')
        globpat = pattern if has_glob else pattern + '*'
        prefix = pattern.split('*')[0] if has_glob else pattern
        suffix = pattern.split('*')[-1] if has_glob and pattern.count('*') == 1 else ''
        for d in sorted(glob.glob(globpat)):
            if not os.path.isdir(d):
                continue
            value = d[len(prefix):] if d.startswith(prefix) else d
            if suffix and value.endswith(suffix):
                value = value[:-len(suffix)]
            if value.endswith('Ry'):
                value = value[:-2]
            tests.append((value, d, prefix.rstrip('_')))
    tests.sort(key=lambda t: value_key(t[0]))
    return tests


def fmt(v, spec, width):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return 'N/A'.rjust(width)
    return format(v, spec).rjust(width)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('-p', '--pattern', default=None,
                   help='directory glob or prefix (default: directories with generation_info.txt)')
    p.add_argument('-O', '--out-name', default=None, help='CP2K output file name in each directory (default: newest *.out)')
    p.add_argument('-t', '--threshold', type=float, default=1.0, help='convergence threshold in meV/atom (default 1)')
    p.add_argument('--ref', choices=['last', 'first'], default='last',
                   help='reference point for dE_ref: last (default, most accurate) or first finished point')
    p.add_argument('-o', '--output', default='conv_analysis.tsv', help='TSV output file (default conv_analysis.tsv)')
    p.add_argument('--grids', action='store_true', help='add the grid counts (count for grid N) columns')
    p.add_argument('--plot', metavar='PNG', default=None, help='plot |dE_ref| [meV/atom] vs value into this file')
    args = p.parse_args(argv)
    if hasattr(signal, 'SIGPIPE'):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # quiet when piped into head

    tests = find_tests(args.pattern)
    if not tests:
        where = ("matching '%s'" % args.pattern) if args.pattern else 'with generation_info.txt (use -p for other tests)'
        sys.exit('No test directories %s.' % where)

    rows = []
    for value, d, param in tests:
        out = newest_out(d, args.out_name)
        r = parse_output(out) if out else None
        row = {'value': value, 'dir': d, 'param': param, 'out': out, 'r': r}
        if r is None:
            row['status'] = 'no_output'
        elif r['finished']:
            row['status'] = 'finished'
        elif r['failed']:
            row['status'] = 'failed'
        else:
            row['status'] = 'running'
        e = r['energy'] if r else None
        n = r['natoms'] if r else None
        row['epa'] = e / n if (e is not None and n) else None
        rows.append(row)

    ok = [row for row in rows if row['status'] == 'finished' and row['epa'] is not None]
    ref = (ok[-1] if args.ref == 'last' else ok[0]) if ok else None
    ok_ids = set(id(row) for row in ok)
    prev = None
    for row in rows:
        row['de_prev'] = row['de_ref'] = None
        if id(row) in ok_ids:
            if prev is not None:
                row['de_prev'] = (row['epa'] - prev['epa']) * HARTREE_TO_MEV
            row['de_ref'] = (row['epa'] - ref['epa']) * HARTREE_TO_MEV
            prev = row

    # first value from which |dE_ref| < threshold for all later finished points
    converged_at = None
    for i, row in enumerate(ok):
        if all(abs(r2['de_ref']) < args.threshold for r2 in ok[i:]):
            converged_at = row
            break

    show = {k: any(row['r'] and row['r'][k] is not None for row in rows) for k in ('pressure', 'gap', 'fermi')}
    ngrid = max((len(row['r']['grids']) for row in rows if row['r']), default=0) if args.grids else 0

    params = sorted(set(row['param'] for row in rows if row['param']))
    columns = [('value', 'value', None, 0), ('status', 'status', None, 0), ('SCF_NC', 'scf_nc', 'd', 6),
               ('E [Ha]', 'energy', '.10f', 18), ('natoms', 'natoms', 'd', 6), ('E/atom [Ha]', 'epa', '.10f', 16),
               ('dE_prev [meV/at]', 'de_prev', '.4f', 16), ('dE_ref [meV/at]', 'de_ref', '.4f', 15),
               ('SCF', 'scf_steps', 'd', 5), ('time [s]', 'walltime', '.1f', 10)]
    if show['pressure']:
        columns.append(('P [bar]', 'pressure', '.2f', 11))
    if show['gap']:
        columns.append(('gap [eV]', 'gap', '.4f', 9))
    if show['fermi']:
        columns.append(('E_F [eV]', 'fermi', '.4f', 9))
    for g in range(ngrid):
        columns.append(('grid%d' % (g + 1), 'grid%d' % g, 'd', 9))

    def cell(row, key, spec, width):
        if key == 'value':
            return row['value']
        if key == 'status':
            return row['status']
        if key in ('epa', 'de_prev', 'de_ref'):
            return fmt(row[key], spec, width)
        r = row['r']
        if r is None:
            return fmt(None, spec, width)
        if key.startswith('grid'):
            g = int(key[4:])
            return fmt(r['grids'][g] if g < len(r['grids']) else None, spec, width)
        return fmt(r[key], spec, width)

    table = [[c[0] for c in columns]] + [[cell(row, c[1], c[2], c[3]).strip() for c in columns] for row in rows]
    widths = [max(len(t[i]) for t in table) for i in range(len(columns))]

    title = 'Convergence test' + (' of %s' % ', '.join(params) if params else '')
    print('# %s  (%d directories; reference: %s point%s)' % (
        title, len(rows), args.ref, (' = %s' % ref['value']) if ref else ' -- no finished run'))
    for i, line in enumerate(table):
        mark = ''
        if i > 0 and converged_at is not None and rows[i - 1] is converged_at:
            mark = '   <- converged (|dE_ref| < %g meV/atom from here on)' % args.threshold
        print('  '.join(v.rjust(w) if j > 1 else v.ljust(w) for j, (v, w) in enumerate(zip(line, widths))) + mark)
    if converged_at is not None:
        note = ''
        if converged_at is ref and len(ok) > 1:
            note = ' -- only the reference point itself: not converged within the tested range'
        print('# converged at: %s (threshold %g meV/atom)%s' % (converged_at['value'], args.threshold, note))
    else:
        print('# converged at: not reached (threshold %g meV/atom)' % args.threshold)
    for row in rows:
        if row['status'] != 'finished':
            print('# %s: %s (%s)' % (row['dir'], row['status'], row['out'] or 'no *.out file'))

    with open(args.output, 'w') as fh:
        fh.write('# %s; reference: %s; threshold %g meV/atom; converged at: %s\n' % (
            title, ref['value'] if ref else 'N/A', args.threshold,
            converged_at['value'] if converged_at else 'not reached'))
        fh.write('\t'.join(['dir'] + table[0]) + '\n')
        for row, line in zip(rows, table[1:]):
            fh.write('\t'.join([row['dir']] + line) + '\n')
    print('# table written to %s' % args.output)

    if args.plot:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        xs = list(range(len(ok)))
        ys = [max(abs(row['de_ref']), 1e-6) for row in ok]
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.semilogy(xs, ys, marker='o')
        ax.axhline(args.threshold, color='crimson', linestyle='--', label='%g meV/atom' % args.threshold)
        ax.set_xticks(xs)
        ax.set_xticklabels([row['value'] for row in ok], rotation=45, ha='right')
        ax.set_xlabel(', '.join(params) if params else 'value')
        ax.set_ylabel('|E/atom - E_ref/atom| [meV/atom]')
        ax.legend()
        fig.tight_layout()
        fig.savefig(args.plot, dpi=200)
        print('# plot written to %s' % args.plot)
    return 0


if __name__ == '__main__':
    sys.exit(main())
