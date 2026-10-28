#!/usr/bin/env python3
"""
Plot one column of a CP2K MD energy file (.ener) against time.

Usage: cp2k_md_analysis.py [file.ener] [-c COLUMN] [-o plot.png]
  file.ener   default ./cp2k-1.ener
  -c COLUMN   number (1-4) or name (Kin, Temp, Pot, Cons) of the column; without -c a menu is shown
  -o FILE     save the plot to FILE (e.g. temp.png) instead of opening a window
"""
import sys
import argparse
import pandas as pd


def plot_convergence(filepath, column=None, output=None):
    # Load the data file into a DataFrame
    try:
        data = pd.read_csv(filepath, sep=r'\s+', comment='#', header=None)
    except Exception as e:
        print(f"Error reading the file: {e}")
        return
    
    # Rename columns based on the header information provided
    data.columns = [
        'Step Nr.', 'Time[fs]', 'Kin.[a.u.]', 'Temp[K]', 'Pot.[a.u.]', 'Cons Qty[a.u.]', 'UsedTime[s]'
    ]

    # Drop unnecessary columns
    data = data.drop(columns=['Step Nr.', 'UsedTime[s]'])

    # Display available columns for selection
    columns = [col for col in data.columns if col != 'Time[fs]']
    print("Available columns to plot:")
    for i, col in enumerate(columns, start=1):
        print(f"{i}: {col}")
    
    # Get user selection (-c: number or name of the column, otherwise ask)
    if column is not None:
        if column.isdigit():
            selected_index = int(column)
        else:
            matches = [i for i, col in enumerate(columns, start=1) if col.lower().startswith(column.lower())]
            if len(matches) != 1:
                print(f"Invalid column '{column}'.")
                return
            selected_index = matches[0]
        if selected_index < 1 or selected_index > len(columns):
            print("Invalid selection.")
            return
    else:
        try:
            selected_index = int(input("Select a column index to plot: "))
            if selected_index < 1 or selected_index > len(columns):
                print("Invalid selection.")
                return
        except ValueError:
            print("Invalid input. Please enter a number.")
            return

    selected_column = columns[selected_index - 1]

    if output:
        import matplotlib
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    # Plot the selected column against Time[fs]
    plt.plot(data['Time[fs]'], data[selected_column], label=selected_column)
    
    # Customize the plot
    plt.xlabel('Time [fs]')
    plt.ylabel(selected_column)
    plt.title('Convergence Analysis')
    plt.legend()
    plt.grid(True)
    if output:
        plt.savefig(output, dpi=200, bbox_inches="tight")
        print(f"Plot saved to {output}")
    else:
        plt.show()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", nargs="?", default="./cp2k-1.ener", help="CP2K .ener file (default ./cp2k-1.ener)")
    parser.add_argument("-c", "--column", default=None, help="column number (1-4) or name (Kin, Temp, Pot, Cons)")
    parser.add_argument("-o", "--output", default=None, help="save the plot to this file instead of showing it")
    args = parser.parse_args()
    plot_convergence(args.file, column=args.column, output=args.output)
