#!/bin/bash

# Check if the directory is provided as an argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <JOB_SCRIPT_DIR>"
    exit 1
fi

JOB_SCRIPT_DIR="$1"

# Check if the provided directory exists
if [ ! -d "$JOB_SCRIPT_DIR" ]; then
    echo "Error: Directory '$JOB_SCRIPT_DIR' does not exist."
    exit 1
fi

# Find logs with the keyword "End Fatal Exception" or missing "Event" and extract job identifiers
echo "Checking logs for errors in directory: $JOB_SCRIPT_DIR..."

FAILED_JOBS=()
while IFS= read -r line; do
    LOG_FILE=$(echo "$line" | cut -d':' -f1)      # Extract the log file name
    JOB_NAME=$(basename "$LOG_FILE" .err)         # Extract the job name from the log file
    FAILED_JOBS+=("$JOB_NAME")
done < <(grep -L "Begin processing the 100th record" "$JOB_SCRIPT_DIR"/*.err 2>/dev/null)

# Check if there are any failed jobs
if [ ${#FAILED_JOBS[@]} -eq 0 ]; then
    echo "No failed jobs detected. All clear!"
    exit 0
fi

echo "Detected failed jobs:"
for job in "${FAILED_JOBS[@]}"; do
    echo "  - $job"
done

# Resubmit the failed jobs
echo "Resubmitting failed jobs..."
for job in "${FAILED_JOBS[@]}"; do
    JOB_SCRIPT="$JOB_SCRIPT_DIR/$job.sub"  # Construct the path to the job submission script

    if [ -f "$JOB_SCRIPT" ]; then
        # Remove the .log, .out, and .err files before resubmitting
        echo "Removing old files for job: $job"
        rm -f "$JOB_SCRIPT_DIR/$job.log" "$JOB_SCRIPT_DIR/$job.out" "$JOB_SCRIPT_DIR/$job.err"

        # Resubmit the job
        echo "Resubmitting job: $job"
        condor_submit "$JOB_SCRIPT"
    else
        echo "Job script not found for: $job. Skipping..."
    fi
done

echo "Resubmission complete!"

