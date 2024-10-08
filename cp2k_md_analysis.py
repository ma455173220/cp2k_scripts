#!/apps/python3/3.10.0/bin/python3
import pandas as pd
import matplotlib.pyplot as plt

def plot_convergence(filepath):
    # Load the data file into a DataFrame
    try:
        data = pd.read_csv(filepath, sep='\s+', comment='#')
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
    
    # Get user selection
    try:
        selected_index = int(input("Select a column index to plot: "))
        if selected_index < 1 or selected_index > len(columns):
            print("Invalid selection.")
            return
    except ValueError:
        print("Invalid input. Please enter a number.")
        return

    selected_column = columns[selected_index - 1]

    # Plot the selected column against Time[fs]
    plt.plot(data['Time[fs]'], data[selected_column], label=selected_column)
    
    # Customize the plot
    plt.xlabel('Time [fs]')
    plt.ylabel(selected_column)
    plt.title('Convergence Analysis')
    plt.legend()
    plt.grid(True)
    plt.show()

if __name__ == "__main__":
    filepath = "./cp2k-1.ener"  # Update to the actual file path if needed
    plot_convergence(filepath)
