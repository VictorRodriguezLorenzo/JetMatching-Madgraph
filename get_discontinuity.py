import ROOT
import sys

ROOT.gROOT.SetBatch(True)

# Function to calculate discontinuity with local smoothing
def discontinuity_metric(file_name, hist_name, kernel=None):
    """
    Calculates discontinuity using a weighted average of neighboring bins.
    """
    file = ROOT.TFile.Open(file_name)

    if not file or file.IsZombie():
        print(f"Error opening file {file_name}.")
        sys.exit(1)

    # Try to get the histogram
    print(f"Retrieving histogram: {hist_name}")  # Debugging
    hist = file.Get(hist_name)
    hist.Draw()

    if not hist:
        print(f"Histogram {hist_name} not found in {file_name}.")
        print("Available histograms and objects in the ROOT file:")

        for key in file.GetListOfKeys():
            print(f"  {key.GetName()}")

        sys.exit(1)

    if kernel is None:
    # Default kernel for weighted average with immediate neighbors
        kernel = [0.05, 0.10, 0.7, 0.10, 0.05]

    n_bins = hist.GetNbinsX()
    kernel_half_width = len(kernel) // 2
    grad_sum = 0.0

    # Loop over the histogram bins
    for i in range(1, n_bins + 1):
        # Compute the weighted average for the current bin
        weighted_value = 0.0
        normalization = 0.0

        for k, weight in enumerate(kernel):
            neighbor_index = i + k - kernel_half_width
            if 1 <= neighbor_index <= n_bins:
                weighted_value += weight * hist.GetBinContent(neighbor_index)
                normalization += weight

        if normalization > 0:
            weighted_value /= normalization

        # Compare with the next bin (same smoothing applied)
        if i < n_bins:
            weighted_next = 0.0
            normalization_next = 0.0

            for k, weight in enumerate(kernel):
                neighbor_index = i + 1 + k - kernel_half_width
                if 1 <= neighbor_index <= n_bins:
                    weighted_next += weight * hist.GetBinContent(neighbor_index)
                    normalization_next += weight

            if normalization_next > 0:
                weighted_next /= normalization_next

            # Add the absolute gradient between smoothed bins
            grad_sum += abs(weighted_next - weighted_value)
    print(grad_sum)
    file.Close()
    return grad_sum

# Main function to process the histogram and calculate discontinuity
def main():
    if len(sys.argv) != 6:
        print("Usage: python3 get_discontinuity.py <root_file> <histogram_name> <xqcut> <qcut> <output_metric_file>")
        sys.exit(1)
    print("Arguments received:", sys.argv)
    root_file = sys.argv[1]  # ROOT file path (e.g., $outroot)
    hist_name = sys.argv[2]  # Histogram name (e.g., djr1)
    xqcut = sys.argv[3]  # xqcut value
    qcut = sys.argv[4]  # qcut value
    output_metric_file = sys.argv[5]  # Path to the output metric.txt

    # Calculate the discontinuity for the histogram
    discont = discontinuity_metric(root_file, hist_name)

    # Output the discontinuity value
    print(f"Discontinuity for {hist_name} (xqcut={xqcut}, qcut={qcut}): {discont:.4f}")

    # Append the result to the specified output metric file
    with open(output_metric_file, "a") as f:
        f.write(f"{xqcut}, {qcut}, {discont:.4f}\n")

if __name__ == "__main__":
    main()

