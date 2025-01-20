import os
import re
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np

# Define the path to the "logs" folder
logs_folder = "logs/ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_49_mphi_100_gSM_1_gDM_1_6800GeV"

# Regular expression to match the cross section line
cross_section_pattern = re.compile(
    r"Before Filter: total cross section = ([\d\.eE\+\-]+) \+\- ([\d\.eE\+\-]+) pb"
)

# Dictionary to hold cross-section and error data grouped by (xqcut, qcut)
data_dict = {}

def extract_cross_section(file_path):
    """
    Extracts the cross section and its error from a log file.
    """
    with open(file_path, 'r') as file:
        for line in file:
            match = cross_section_pattern.search(line)
            if match:
                cross_section = float(match.group(1))
                error = float(match.group(2))
                return cross_section, error
    return None, None

# Walk through all directories and subdirectories
for root, dirs, files in os.walk(logs_folder):
    if "qcut_" in root:  # Check if we are inside a qcut_X folder
        # Extract xqcut and qcut values from the folder path
        parts = root.split("/")
        xqcut = None
        qcut = None
        for part in parts:
            if "xqcut" in part:
                xqcut = int(part.split("_")[-1])
            if "qcut" in part:
                qcut = int(part.split("_")[-1])
        
        # Key for grouping data
        key = (xqcut, qcut)
        
        # Process log files in the current folder
        for file_name in files:
            if file_name.endswith(".err"):  # Assuming log files have '.err' extension
                file_path = os.path.join(root, file_name)
                cross_section, error = extract_cross_section(file_path)
                if cross_section is not None:
                    # Initialize the data structure if not already present
                    if key not in data_dict:
                        data_dict[key] = {"cross_sections": [], "errors": []}
                    
                    # Append values to the list
                    data_dict[key]["cross_sections"].append(cross_section)
                    data_dict[key]["errors"].append(error)

# Aggregate data: Compute averages for each (xqcut, qcut) pair
data = []
for (xqcut, qcut), values in data_dict.items():
    avg_cross_section = np.mean(values["cross_sections"])
    avg_error = np.mean(values["errors"])
    data.append({
        "xqcut": xqcut,
        "qcut": qcut,
        "avg_cross_section_pb": avg_cross_section,
        "avg_error_pb": avg_error
    })

# Create a DataFrame for the aggregated data
df = pd.DataFrame(data)

# Save the aggregated data to a CSV file
output_file = "averaged_cross_sections.csv"
df.to_csv(output_file, index=False)

# Display the aggregated data
print(df)
print(f"\nAveraged cross sections saved to '{output_file}'")

# Pivot data to create a grid for heatmap/contour plot
pivot_table = df.pivot_table(
    index="xqcut", columns="qcut", values="avg_cross_section_pb", aggfunc=np.mean
)

# Heatmap of cross sections
plt.figure(figsize=(10, 8))
sns.heatmap(pivot_table, annot=True, fmt=".2e", cmap="viridis", cbar_kws={'label': 'Average Cross Section (pb)'})
plt.title("Cross Section Heatmap")
plt.xlabel("qcut")
plt.ylabel("xqcut")
plt.tight_layout()
plt.savefig("heatmap_cross_sections.png")
plt.show()


# Import necessary modules
import matplotlib.pyplot as plt
import numpy as np

# Prepare data for the contour plot
plt.figure(figsize=(10, 8))  # Larger figure for better readability
plt.gca().set_facecolor('k')
X, Y = np.meshgrid(pivot_table.columns, pivot_table.index)

Z = np.nan_to_num(pivot_table.values)

lowest_nonzero = np.min(Z[Z > 0])
levels = np.linspace(lowest_nonzero, np.max(Z), 10)


# Create a filled contour plot
contourf = plt.contourf(X, Y, Z, levels=levels, cmap="viridis")
contour = plt.contour(X, Y, Z, levels=levels, colors="black", linewidths=0.5)

# Add labels to contours
plt.clabel(contour, inline=True, fontsize=8)

# Add a color bar with a descriptive label
cbar = plt.colorbar(contourf)
cbar.set_label("Cross Section (pb)", fontsize=10)

# Customize plot labels and title
plt.title("Cross Section Contour Plot", fontsize=14, weight='bold')
plt.xlabel("qcut", fontsize=12)
plt.ylabel("xqcut", fontsize=12)

# Optimize layout for better appearance
plt.tight_layout()

# Save the plot with a descriptive file name
output_file = "cross_section_contour_plot.png"
plt.savefig(output_file, dpi=300)  # Save with higher DPI for better quality

# Optionally display the plot
plt.show()

