#!/bin/sh


# Controllers for the whole code
GENERATE_MASS_POINTS=true
GENERATE_GRIDPACKS=true
PERFORM_HADRONIZATION=false
STUDY_DJR_CONTINUITY=false
FIND_BEST_CONFIGURATION=false


# Define directories for the scripts and logs
SCRIPT_DIR="/afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow"
GRIDPACK_SCRIPT="${SCRIPT_DIR}/generate_gridpacks.sh" 
MASS_POINTS_DIR="$SCRIPT_DIR/mass_points"


# Check if the generate_gridpacks script exists
if [[ ! -f "$GRIDPACK_SCRIPT" ]]; then
    echo "Error: generate_gridpacks.sh not found!"
    exit 1
fi

if [[ "${GENERATE_MASS_POINTS}" = true ]]; then
    # Step 1: Generate cards for different mass points
    echo "Step 1: Generating cards for different mass points..."
    cd "$SCRIPT_DIR"
    ./writeallcards_ttbarDM_dilepton_pseudoscalar.sh

    if [[ $? -eq 0 ]]; then
        echo "Cards for different mass points generated successfully!"
    else
        echo "Error: Failed to generate cards!"
        exit 1
    fi
fi


if [[ "$GENERATE_GRIDPACKS" = true ]]; then
    # Step 2: Iterate over all mass points to generate gridpacks with different values of xqcut
    echo "Step 2: Generating gridpacks for different xqcut values..."

    # Assuming mass points directories are in the format ttbarDM_<mass_point_name>
    for mass_point in "$SCRIPT_DIR/mass_points/"*/; do  # Assuming the mass points are directories
        if [[ -d "$mass_point" ]]; then  # Make sure it's a directory
            # Extract mass point name from the directory name
            if [[ "$mass_point" =~ ttbarDM__([^/]+) ]]; then  # Match your directory naming convention
                mass_point_name=${BASH_REMATCH[1]}  # Capture the mass point name

                echo "Processing mass point: $mass_point_name"

                # Iterate over different xqcut values (for example, from 10 to 50 with step 10)
                for xqcut_val in $(seq 10.0 10.0 50.0); do
                    echo "Generating gridpack for xqcut=$xqcut_val and mass_point_name=$mass_point_name"

                    # Generate gridpack with the appropriate xqcut and mass_point_name values
                    cd "$SCRIPT_DIR"  # Ensure we are in the script directory for running the gridpack generation
                    bash "$GRIDPACK_SCRIPT" "$xqcut_val" "$mass_point_name"

                    if [[ $? -eq 0 ]]; then
                        echo -e "Gridpack generated for xqcut=$xqcut_val and mass_point_name=$mass_point_name \n\n"
                    else
                        echo "Error: Failed to generate gridpack for xqcut=$xqcut_val and mass_point_name=$mass_point_name"
                        exit 1
                    fi
                done
            else
                echo "Skipping invalid directory: $mass_point"
            fi
        fi
    done
fi



if [[ "$PERFORM_HADRONIZATION" = true ]]; then
    # Step 3: For each gridpack, perform hadronization with varying qcut values
    echo "Step 3: Hadronization and job submission..."

    CMSSW_DIR="/afs/cern.ch/user/v/victorr/private/CMSSW_12_4_16/src"
    CMSSW_EOS_DIR="/eos/user/v/victorr/CMSSW_12_4_16/src"
    CONDOR_SCRIPT="$CMSSW_DIR/runEventGeneration_to_eos.py"
    RESUBMIT_SCRIPT="${CMSSW_DIR}/resubmit_failed_jobs.sh"
    FRAGMENT_FILE="/eos/user/v/victorr/CMSSW_12_4_16/src/Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py"

    cd "$CMSSW_DIR"

    for gridpack in "$SCRIPT_DIR/gridpacks/"*/*.tar.xz; do
        if [[ -f "$gridpack" ]]; then
            base_name=$(basename "$gridpack" .tar.gz)
            xqcut=$(echo "$base_name" | grep -oP "xqcut_\d+" | grep -oP "\d+")

            # Update the gridpack path in the fragment
            sed -i "s|\"gridpack_path\": \".*\.tar\.xz\"|\"gridpack_path\": \"$gridpack\"|" "$FRAGMENT_FILE"

            mkdir -p "$CMSSW_EOS_DIR/Event_generation/$base_name"
            echo "Processing gridpack: $gridpack (xqcut=$xqcut)"

            # Iterate over qcut values (e.g., 30 to 60 with a step of 10)
            for qcut in $(seq "$xqcut" 10 $(("$xqcut" + 50))); do
                echo "Configuring hadronization for qcut=$qcut"

                # Update the fragment file with the new qcut value
                sed -i "s/^.*QCut = .*/    QCut = $qcut,/" "$FRAGMENT_FILE"

                # Rebuild CMSSW
                echo "Rebuilding CMSSW environment..."
                cd "$CMSSW_EOS_DIR"
                scram b

                mkdir -p "$CMSSW_EOS_DIR/Event_generation/$base_name/qcut_${qcut}"

                # Submit jobs to HTCondor
                echo "Submitting jobs to HTCondor..."
                cd "$CMSSW_DIR"
                python3 "$CONDOR_SCRIPT" -o "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}" # -n 10000 -e 50  # 10000 events, 200 jobs of 50

                # Monitor job progress
                echo "Monitoring jobs for $base_name with qcut=$qcut..."
                completed=false

                while [[ $completed == false ]]; do
                    sleep 300  # 5 minutes

                    # Run the resubmit script to check and resubmit failed jobs
                    echo "Running resubmit script..."
                    bash "$RESUBMIT_SCRIPT"

                    # Check the job status using condor_q
                    job_status=$(condor_q | grep "$USER" | awk '{print $6}' | sort | uniq -c)

                    echo "Job status summary for user $USER:"
                    echo "$job_status"

                    # Extract the count of running, idle, and held jobs
                    num_running=$(echo "$job_status" | grep -w R | awk '{print $1}')
                    num_idle=$(echo "$job_status" | grep -w I | awk '{print $1}')
                    num_held=$(echo "$job_status" | grep -w H | awk '{print $1}')

                    # Ensure variables are set to zero if not present in condor_q output
                    num_running=${num_running:-0}
                    num_idle=${num_idle:-0}
                    num_held=${num_held:-0}

                    echo "Running: $num_running, Idle: $num_idle, Held: $num_held"

                    # Check if all jobs are done (i.e., no running, idle, or held jobs)
                    if [[ $num_running -eq 0 && $num_idle -eq 0 && $num_held -eq 0 ]]; then
                        echo "All jobs for $base_name with qcut=$qcut are complete!"
                        completed=true
                    else
                        echo "Jobs still in progress. Retrying in 5 minutes..."
                    fi
                done

            done
        else
            echo "Skipping invalid gridpack: $gridpack"
        fi
    done

    echo "Step 3 complete!"
fi


if [[ "$STUDY_DJR_CONTINUITY" = true ]]; then

    HADRONIZATION_DIR="$CMSSW_EOS_DIR/Event_generation/"
    ROOT_FILES_DIR="$CMSSW_EOS_DIR/Histograms"
    PLOTDJR_SCRIPT="$SCRIPT_DIR/plotdjr.C"
    OPTIMIZE_SCRIPT="$SCRIPT_DIR/optimize_values.py"
    REMOVE_OTHERS=FALSE  # Set this to false to keep all configurations

    # Ensure output directories exist
    mkdir -p "$ROOT_FILES_DIR"

    # Step 4: Generate histograms and compute metrics
    echo "xqcut,qcut,discontinuity" > "$METRIC_RESULTS_FILE"

    # Iterate over all base_name directories (mass point + xqcut) in HADRONIZATION_DIR
    for base_dir in "$HADRONIZATION_DIR"/*/; do
        if [[ ! -d "$base_dir" ]]; then
            continue  # Skip if it's not a directory
        fi

        # Extract base name (e.g., mass point + xqcut) from the directory name
        base_name=$(basename "$base_dir")

        # Iterate over different qcut values inside each base_name directory
        for qcut_dir in "$base_dir"/*/; do
            if [[ ! -d "$qcut_dir" ]]; then
                continue  # Skip if it's not a directory
            fi

            # Extract qcut from the directory name (assuming qcut is part of the directory name)
            qcut=$(basename "$qcut_dir" | sed 's/^qcut_//')
            echo "Processing xqcut and qcut values: $base_name, $qcut"

            # Iterate over all ROOT files in the current qcut directory
            for root_file in "$qcut_dir"/*.root; do
                if [[ ! -f "$root_file" ]]; then
                    echo "No ROOT files found in $qcut_dir."
                    exit 1
                fi

                # Extract the base name from the ROOT file (e.g., mass point, xqcut, qcut)
                root_file_basename=$(basename "$root_file" .root)

                # Assuming the base_name format includes xqcut and qcut values, e.g., "ttbarDM__1000_xqcut_30"
                if [[ ! "$root_file_basename" =~ ttbarDM__([^_]+)_xqcut_([0-9]+)_qcut_([0-9]+) ]]; then
                    echo "Skipping unrecognized file: $root_file"
                    continue
                fi

                # Extract mass point, xqcut, and qcut from the filename
                mass_point="${BASH_REMATCH[1]}"
                xqcut="${BASH_REMATCH[2]}"
                qcut="${BASH_REMATCH[3]}"

                # Perform the required analysis on the ROOT file (e.g., plot, compute metric, etc.)
                echo "Processing ROOT file for mass_point: $mass_point, xqcut: $xqcut, qcut: $qcut"

                outfile="$ROOT_FILES_DIR/${base_name}_${qcut}_plots.pdf"
                outroot="$ROOT_FILES_DIR/${base_name}_${qcut}.root"

                # Generate DJR histograms
                echo "Generating histograms for xqcut=$xqcut, qcut=$qcut..."
                root -b -q "${PLOTDJR_SCRIPT}(\"$root_file\", \"$outfile\", \"$outroot\")"

                # Compute DJR1 discontinuity metric
                echo "Computing discontinuity for xqcut=$xqcut, qcut=$qcut..."
                python3 "$OPTIMIZE_SCRIPT" "$outroot" "djr1" >> "$METRIC_RESULTS_FILE" # STILL NEED TO IMPLEMENT THIS

                # Append the xqcut, qcut, and discontinuity values to the results file
                discontinuity="TODO"  # Replace this with the actual value from the script
                echo "$xqcut,$qcut,$discontinuity" >> "$METRIC_RESULTS_FILE"
            done
        done
    done

    echo "Step 4 complete!"
fi

if [[ "$FIND_BEST_CONFIGURATION" = true ]]; then
    # Step 5: Find best configuration and optionally remove others
    if [[ -f "$METRIC_RESULTS_FILE" ]]; then
        echo "Finding best configuration..."

        # Find the line with the best (minimum) discontinuity
        best_line=$(tail -n +2 "$METRIC_RESULTS_FILE" | sort -t, -k3,3n | head -n 1)
        IFS=',' read -r best_xqcut best_qcut best_metric <<< "$best_line"

        echo "Best Configuration: xqcut=$best_xqcut, qcut=$best_qcut, Discontinuity=$best_metric"

        if [[ "$REMOVE_OTHERS" == true ]]; then
            echo "Removing all non-optimal configurations..."
            for root_file in "$ROOT_FILES_DIR"/*.root; do
                base_name=$(basename "$root_file" .root)

                # Check if the current file matches the best configuration
                if [[ $base_name != *"xqcut_${best_xqcut}_qcut_${best_qcut}"* ]]; then
                    rm -f "$root_file" "${ROOT_FILES_DIR}/${base_name}_plots.pdf"
                    rm -f "${HADRONIZATION_DIR}/${base_name}.root"
                    echo "Removed: $base_name"
                fi
            done
        fi
    else
        echo "Metrics file not found. Check your input and scripts."
        exit 1
    fi

    echo "Step 5 complete!"
fi

echo "Process completed."

