#!/usr/bin/env python3
"""
cp2k_xyz.py -- shared helpers for CP2K xyz trajectories (importable module).

  iter_xyz(path)            streaming frame iterator (constant memory, works on multi-GB trajectories)
  parse_cp2k_comment(text)  " i = 5, time = 2.5, E = -1.2"  ->  {'i': 5, 'time': 2.5, 'E': -1.2}
  bond_lengths(atoms, e1, e2, scale)        PBC bond lengths from natural cutoffs (vectorised, needs ASE)
  pair_distances_nopbc(atoms, e1, e2, rmax) plain (non-periodic) pair distances below rmax (numpy)

Run directly, it prints a one-line summary of an xyz file: cp2k_xyz.py traj.xyz
"""

import re
import sys

import numpy as np


class Frame(object):
    """One xyz frame. atom_lines keep the original text (with newlines) so frames can be copied verbatim."""
    __slots__ = ('index', 'natoms', 'header', 'comment', 'atom_lines')

    def __init__(self, index, natoms, header, comment, atom_lines):
        self.index = index
        self.natoms = natoms
        self.header = header          # the atom-count line as read
        self.comment = comment        # the comment line as read (with newline)
        self.atom_lines = atom_lines

    def info(self):
        return parse_cp2k_comment(self.comment)

    def symbols(self):
        return [line.split()[0] for line in self.atom_lines]

    def positions(self):
        return np.array([[float(x) for x in line.split()[1:4]] for line in self.atom_lines])

    def text(self):
        return self.header + self.comment + ''.join(self.atom_lines)


def iter_xyz(path, skip_blank=True):
    """Yield the frames of an xyz file one by one. Blank lines between frames are skipped.
    Raises ValueError on a malformed atom-count line or a truncated frame."""
    with open(path, 'r') as fh:
        index = 0
        while True:
            header = fh.readline()
            if not header:
                return
            if skip_blank and not header.strip():
                continue
            try:
                natoms = int(header.split()[0])
            except (ValueError, IndexError):
                raise ValueError('%s: expected an atom count, got %r' % (path, header.rstrip()))
            comment = fh.readline()
            atom_lines = [fh.readline() for _ in range(natoms)]
            if not comment or (natoms and not atom_lines[-1]):
                raise ValueError('%s: file truncated inside frame %d' % (path, index))
            yield Frame(index, natoms, header, comment, atom_lines)
            index += 1


_KV = re.compile(r'([A-Za-z_]\w*)\s*=\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)')


def parse_cp2k_comment(text):
    """Key = number pairs of a CP2K xyz comment line (i, time, E, ...)."""
    info = {}
    for key, val in _KV.findall(text):
        info[key] = int(val) if re.match(r'^[-+]?\d+$', val) else float(val)
    return info


def bond_lengths(atoms, elem1, elem2, scale=1.0):
    """All elem1-elem2 bonds (i, j, d) of an ASE Atoms object, each bond once, periodic images included.
    A bond is a pair closer than the sum of the ASE natural cutoffs (covalent radii) times scale."""
    from ase.neighborlist import natural_cutoffs, neighbor_list
    cutoffs = natural_cutoffs(atoms, mult=scale)
    i, j, d, S = neighbor_list('ijdS', atoms, cutoffs, self_interaction=False)
    symbols = np.array(atoms.get_chemical_symbols())
    si, sj = symbols[i], symbols[j]
    if elem1 == elem2:
        mask = (si == elem1) & (sj == elem1)
    else:
        mask = ((si == elem1) & (sj == elem2)) | ((si == elem2) & (sj == elem1))
    # neighbor_list lists every pair twice: (i, j, S) and (j, i, -S); keep one of them
    first_nonzero = np.where(S[:, 0] != 0, S[:, 0], np.where(S[:, 1] != 0, S[:, 1], S[:, 2]))
    keep = (i < j) | ((i == j) & (first_nonzero > 0))
    mask &= keep
    return list(zip(i[mask].tolist(), j[mask].tolist(), d[mask].tolist()))


def pair_distances_nopbc(atoms, elem1, elem2, rmax):
    """elem1-elem2 distances below rmax without periodic boundary conditions."""
    symbols = np.array(atoms.get_chemical_symbols())
    pos = atoms.positions
    a = pos[symbols == elem1]
    b = pos[symbols == elem2]
    d = np.linalg.norm(a[:, None, :] - b[None, :, :], axis=2)
    if elem1 == elem2:
        d = d[np.triu_indices(len(a), 1)]
    d = d.ravel()
    return d[d < rmax].tolist()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: cp2k_xyz.py traj.xyz   (prints the number of frames and atoms)')
    n, natoms = 0, None
    for frame in iter_xyz(sys.argv[1]):
        n += 1
        natoms = frame.natoms
    print('%d frames, %s atoms in the last frame' % (n, natoms))
