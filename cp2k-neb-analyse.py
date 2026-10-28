#!/usr/bin/env python3

"""
This script analyzes a CP2K output file and extracts information about the
NEB information. Output: Step | Energy | RMS DISPLACEMENT | MAX DISPLACEMENT | RMS FORCE | MAX FORCE

In addition the energy profile along the band is extracted from the BAND information blocks that
CP2K prints at every band optimization step (written by motion/neb_io.F, dump_neb_info):

  BAND TYPE                     =                 CI-NEB
  STEP NUMBER                   =                      5
  NUMBER OF NEB REPLICA         =                      8
  DISTANCES REP =   0.537652   0.512345   0.498765   0.521234     <- N-1 distances, 4 per line,
                    0.534567   0.512000   0.540000                   continued on number-only lines
  ENERGIES [au] = -34.123456 -34.120000 -34.110000 -34.105000     <- N energies (Hartree), same layout
                  -34.115000 -34.122000 -34.123000 -34.124000
  BAND TOTAL ENERGY [au]        =           -272.9
Only the "STEP NUMBER", "NUMBER OF NEB REPLICA", "DISTANCES REP =" and "ENERGIES [au] =" lines (and their
number-only continuation lines) are read. NOTE: this layout follows the CP2K source; check it against a
real BAND output of your CP2K version before relying on it.

Output files (besides <out>__data.csv):
  <out>__band_energies.csv   step x replica energies relative to replica 1 [eV] (+ E of replica 1 [a.u.])
  <out>__profile.csv         last step: replica, path coordinate (cumulative distance, as printed), E, dE [eV]
  <out>__profile.png         energy profile of the last step (with --plot)
and the forward/reverse barrier and the highest image are printed.

Usage:
  cp2k-neb-analyse.py OUTPUT_FILE.out [--plot | --no-plot]
"""

import os
import sys


def print_usage():
    print("""
***************************************
*** The format of the script: ***
cp2k-neb-analyse.py OUTPUT_FILE.out [--plot | --no-plot]
(without --plot/--no-plot you are asked
 if the script runs in a terminal)
***************************************
    """)


def process_output_file(output_file):
    plot_file = output_file.split('.out')[0] + "__data.csv"
    starttime = ""
    CYCLE_NUMBER = 0
    line_minus = 3
    line_added = 3
    line_number = 0

    with open(output_file, 'r') as f, open(plot_file, 'w') as o:
        lines = f.readlines()
        for line in lines:
            line_number += 1
            if "PROGRAM STARTED AT" in line:
                starttime = line.split('AT')[-1].strip()
            elif "RMS DISPLACEMENT" in line:
                CYCLE_NUMBER += 1
                top_line_number = line_number - line_minus 
                bottom_line_number = line_number + line_added
                for contents in lines[top_line_number:bottom_line_number]:
                    if "ENERGY| Total FORCE_EVAL" in contents:
                        TOTAL_ENERGY = float(contents.split()[-1].strip())
                    elif "RMS DISPLACEMENT" in contents:
                        RMS_D = float(contents.split()[3].strip())
                    elif "MAX DISPLACEMENT" in contents:
                        MAX_D = float(contents.split()[3].strip())
                    elif "RMS FORCE" in contents:
                        RMS_F = float(contents.split()[3].strip())
                    elif "MAX FORCE " in contents:
                        MAX_F = float(contents.split()[3].strip())
                o.write("%5s  |%15.8f |%8.5f |%8.5f |%8.5f |%8.5f" % (CYCLE_NUMBER, TOTAL_ENERGY,
                                                                  RMS_D, MAX_D, RMS_F, MAX_F))
                o.write("\n")
        o.write("# Done!")

    with open(plot_file, 'r+') as f:
        contents = f.read()
        f.seek(0, 0)
        f.write("# Job Starting Date: " + starttime \
                + "\n# Directory: " + os.getcwd() \
                + "\n# STEP |    E [a.u.]    |  RMS_D  |  MAX_D  |  RMS_F  |  MAX_F " \
                + "\n" + contents)


HARTREE_TO_EV = 27.211386245988


def _numbers(text):
    """All tokens of text as floats, or None if any token is not a number."""
    try:
        return [float(x) for x in text.split()]
    except ValueError:
        return None


def parse_band_blocks(output_file):
    """Streaming parse of the BAND blocks -> list of dicts {step, distances, energies}."""
    blocks = []
    step = None
    nrep = None
    current = None
    collecting = None  # ('distances' | 'energies', expected count)
    with open(output_file, 'r') as f:
        for line in f:
            if collecting is not None:
                key, expected = collecting
                values = _numbers(line)
                if values and (expected is None or len(current[key]) < expected):
                    current[key].extend(values)
                    if expected is not None and len(current[key]) >= expected:
                        collecting = None
                    continue
                collecting = None
            if "STEP NUMBER" in line and "=" in line:
                try:
                    step = int(line.split("=")[-1].split()[0])
                except (ValueError, IndexError):
                    pass
            elif "NUMBER OF NEB REPLICA" in line and "=" in line:
                try:
                    nrep = int(line.split("=")[-1].split()[0])
                except (ValueError, IndexError):
                    pass
            elif "DISTANCES REP" in line and "=" in line:
                current = {'step': step if step is not None else len(blocks) + 1,
                           'nrep': nrep, 'distances': [], 'energies': []}
                current['distances'] = _numbers(line.split("=", 1)[1]) or []
                expected = nrep - 1 if nrep else None
                if expected is None or len(current['distances']) < expected:
                    collecting = ('distances', expected)
            elif "ENERGIES [au]" in line and "=" in line:
                if current is None or current['energies']:
                    current = {'step': step if step is not None else len(blocks) + 1,
                               'nrep': nrep, 'distances': [], 'energies': []}
                current['energies'] = _numbers(line.split("=", 1)[1]) or []
                blocks.append(current)
                expected = nrep if nrep else None
                if expected is None or len(current['energies']) < expected:
                    collecting = ('energies', expected)
    return [b for b in blocks if b['energies']]


def write_band_analysis(output_file, plot=False):
    """Band energies per step, final energy profile and barriers. Returns False if no BAND blocks were found."""
    blocks = parse_band_blocks(output_file)
    if not blocks:
        print("No BAND blocks (\"ENERGIES [au] =\") found: no energy profile written.")
        return False
    base = output_file.split('.out')[0]
    nmax = max(len(b['energies']) for b in blocks)

    with open(base + "__band_energies.csv", 'w') as o:
        o.write("# Energies of all replicas relative to replica 1 [eV], per band optimization step\n")
        o.write("# STEP |  E_REP1 [a.u.]  |" + "|".join(" %8s " % ("REP%d" % (i + 1)) for i in range(nmax)) + "\n")
        for b in blocks:
            e1 = b['energies'][0]
            rel = ["%10.4f" % ((e - e1) * HARTREE_TO_EV) for e in b['energies']]
            rel += ["%10s" % "N/A"] * (nmax - len(rel))
            o.write("%6s | %15.8f |%s\n" % (b['step'], e1, "|".join(rel)))

    last = blocks[-1]
    energies = last['energies']
    distances = last['distances']
    s_coord = [0.0]
    for d in distances[:len(energies) - 1]:
        s_coord.append(s_coord[-1] + d)
    s_coord += [float('nan')] * (len(energies) - len(s_coord))
    e1 = energies[0]
    rel = [(e - e1) * HARTREE_TO_EV for e in energies]
    with open(base + "__profile.csv", 'w') as o:
        o.write("# Energy profile of the last band step (step %s)\n" % last['step'])
        o.write("# REPLICA | PATH COORD (cumulative DISTANCES REP) |    E [a.u.]     |  dE [eV]\n")
        for i, (sc, e, de) in enumerate(zip(s_coord, energies, rel), 1):
            o.write("%9d | %37.6f | %15.8f | %9.4f\n" % (i, sc, e, de))

    imax = max(range(len(energies)), key=lambda i: energies[i])
    forward = (energies[imax] - energies[0]) * HARTREE_TO_EV
    reverse = (energies[imax] - energies[-1]) * HARTREE_TO_EV
    print("Band steps found          : %d (last step %s, %d replicas)" % (len(blocks), last['step'], len(energies)))
    print("Highest image             : replica %d" % (imax + 1))
    print("Forward barrier (max - 1) : %.4f eV" % forward)
    print("Reverse barrier (max - N) : %.4f eV" % reverse)
    print("Reaction energy (N - 1)   : %.4f eV" % ((energies[-1] - energies[0]) * HARTREE_TO_EV))
    print("Written: %s__band_energies.csv, %s__profile.csv" % (base, base))

    if plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        x = s_coord if all(v == v for v in s_coord) else list(range(1, len(energies) + 1))
        plt.figure()
        plt.plot(x, rel, marker='o')
        plt.xlabel("Path coordinate" if x is s_coord else "Replica")
        plt.ylabel("E - E(replica 1) [eV]")
        plt.title("NEB energy profile (step %s)" % last['step'])
        plt.savefig(base + "__profile.png", dpi=200, bbox_inches="tight")
        plt.close()
        print("Written: %s__profile.png" % base)
    return True


def plot_cycle_vs_par(plot_file):
    import math
    import re
    import matplotlib.pyplot as plt
    from matplotlib.pyplot import MultipleLocator
    
    # Read data from the file
    with open(plot_file, 'r') as f:
        data = [re.split(r'\s*\|\s*|\s+', line.strip()) for line in f if line.strip() and line.strip()[0].isdigit()]
    
    # Extract x and y values
    x = [int(row[0]) for row in data]
    y_values = [[float(val) for val in row[1:]] for row in data]
    
    # User selects the type of data to plot
    print("Select data to plot:")
    print("1. E")
    print("2. RMS_D")
    print("3. MAX_D")
    print("4. RMS_F")
    print("5. MAX_F")
    choice = int(input("Enter your choice (1-5): "))
    
    # Plot the selected data
    plt.figure()
    labels = ['E', 'RMS_D', 'MAX_D', 'RMS_F', 'MAX_F']
    selected_label = labels[choice - 1]
    y = []
    for content in y_values:
        y.append(float(content[choice - 1]))

    plt.scatter(x, y, label=selected_label, s=10)
    plt.plot(x, y)
    
    # Set labels and title
    plt.xlabel('Step')
    plt.ylabel('Value')
    plt.legend()
    
    # Set x-axis spacing
    x_spacing = 5 * math.ceil(len(x) / 50)  # Adjust 50 to change spacing criteria
    x_major_locator = MultipleLocator(x_spacing)
    ax = plt.gca()
    ax.xaxis.set_major_locator(x_major_locator)
    
    # Show the plot
    plt.show()

def main():
    plot = None
    if "--plot" in sys.argv[1:]:
        plot = True
    if "--no-plot" in sys.argv[1:]:
        plot = False
    files = [a for a in sys.argv[1:] if a not in ("--plot", "--no-plot")]
    if len(files) < 1:
        print("\033[31mERROR:\033[0m Missing file operand! Please identify the name of OUTPUT_FILE.out")
        print_usage()
        sys.exit(1)

    output_file = files[0]
    print("=======================================")
    print("In process...")
    print("...")

    try:
        process_output_file(output_file)
    except FileNotFoundError:
        print(f"Error: File '{output_file}' not found.")
        sys.exit(1)
    except (NameError, UnboundLocalError) as e:
        # an "RMS DISPLACEMENT" block without its energy line nearby: the convergence table is incomplete,
        # but the band energies below can still be extracted
        print(f"Warning: convergence table {output_file.split('.out')[0]}__data.csv is incomplete ({e})")

    print("=======================================")
    write_band_analysis(output_file, plot=bool(plot))

    print("=======================================")
    if plot is None:
        # no --plot/--no-plot: ask, but only when someone can answer (stdin is a terminal)
        if sys.stdin.isatty():
            print("Do you want to plot cycle vs. convergence parameters?\n(y/n)")
            plot = input().lower() == "y"
        else:
            plot = False
    if plot:
        plot_cycle_vs_par(output_file.split('.out')[0] + "__data.csv")

    print("Done!")
    print("=======================================")


if __name__ == "__main__":
    main()


