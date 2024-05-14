#!/apps/python3/3.10.0/bin/python3

"""
This script analyzes a CP2K output file and extracts information about the
NEB information. Output: Step | Energy | RMS DISPLACEMENT | MAX DISPLACEMENT | RMS FORCE | MAX FORCE

Usage:
  cp2k-NEB-analyse.py OUTPUT_FILE.out
"""

import os
import sys
import datetime


def print_usage():
    print("""
***************************************
*** The format of the script: ***
cp2k-NEB-analyse.py OUTPUT_FILE.out
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
            if "RMS DISPLACEMENT" in line:
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
    if len(sys.argv) < 2:
        print("\033[31mERROR:\033[0m Missing file operand! Please identify the name of OUTPUT_FILE.out")
        print_usage()
        sys.exit(1)

    output_file = sys.argv[1]
    print("=======================================")
    print("In process...")
    print("...")

    try:
        process_output_file(output_file)
    except FileNotFoundError:
        print(f"Error: File '{output_file}' not found.")
        sys.exit(1)

    print("=======================================")
    print("Do you want to plot cycle vs. convergence parameters?\n(y/n)")
    plot_choice = input()
    if plot_choice.lower() == "y":
        plot_cycle_vs_par(output_file.split('.out')[0] + "__data.csv")

    print("Done!")
    print("=======================================")


if __name__ == "__main__":
    main()


