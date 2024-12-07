#!/bin/sh


# Controllers for the whole code
GENERATE_MASS_POINTS=true
GENERATE_GRIDPACKS=true
PERFORM_HADRONIZATION=true
STUDY_DJR_CONTINUITY=true
FIND_BEST_CONFIGURATION=true


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
                for xqcut_val in $(seq 10 10 50); do
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


CMSSW_DIR="/afs/cern.ch/user/v/victorr/private/CMSSW_13_2_9/src"
CMSSW_EOS_DIR="/eos/user/v/victorr/CMSSW_13_2_9/src"
CONDOR_SCRIPT="$CMSSW_DIR/runEventGeneration_to_eos.py"
RESUBMIT_SCRIPT="${CMSSW_DIR}/resubmit_failed_jobs.sh"
FRAGMENT_FILE="/eos/user/v/victorr/CMSSW_13_2_9/src/Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py"

if [[ "$PERFORM_HADRONIZATION" = true ]]; then
    # Step 3: For each gridpack, perform hadronization with varying qcut values
    echo "Step 3: Hadronization and job submission..."

    cd "$CMSSW_DIR"

    for gridpack in "$SCRIPT_DIR/gridpacks/"*/*.tar.xz; do
        if [[ -f "$gridpack" ]]; then
            base_name=$(basename "$gridpack" .tar.xz)
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
		cmsenv
                scram b

                mkdir -p "$CMSSW_EOS_DIR/Event_generation/$base_name/qcut_${qcut}"

                # Submit jobs to HTCondor
                echo "Submitting jobs to HTCondor..."
                cd "$CMSSW_DIR"
                python3 "$CONDOR_SCRIPT" -r "${base_name}_qcut_${qcut}" -o "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}" -a "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}" # -n 10000 -e 50  # 10000 events, 200 jobs of 50

                # Monitor job progress
                echo "Monitoring jobs for $base_name with qcut=$qcut..."
                completed=false

                while [[ $completed == false ]]; do
                    sleep 60  # 1 minute

                    # Run the resubmit script to check and resubmit failed jobs
                    echo "Running resubmit script..."
                    bash "$RESUBMIT_SCRIPT" "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}"

                    # Get the job summary line from condor_q
                    job_summary=$(condor_q | grep "Total for $USER:")

                    if [[ -n "$job_summary" ]]; then
                        # Extract values from the job summary
                        total_jobs=$(echo "$job_summary" | awk -F ';' '{print $1}' | awk '{print $4}')
                        completed_jobs=$(echo "$job_summary" | awk -F ';' '{print $2}' | awk '{print $1}')
                        idle_jobs=$(echo "$job_summary" | awk -F ',' '{print $3}' | awk '{print $1}')
                        running_jobs=$(echo "$job_summary" | awk -F ',' '{print $4}' | awk '{print $1}')
                        held_jobs=$(echo "$job_summary" | awk -F ',' '{print $5}' | awk '{print $1}')

                        echo "Total: $total_jobs, Idle: $idle_jobs, Running: $running_jobs, Held: $held_jobs"

                        # Check if all jobs are done
                        if [[ "$completed_jobs" -eq "$total_jobs" && "$idle_jobs" -eq 0 && "$running_jobs" -eq 0 && "$held_jobs" -eq 0 ]]; then
                            echo "All jobs for $base_name with qcut=$qcut are complete!"
                            completed=true
                        else
                            echo -e "Jobs still in progress. Retrying in 1 minute... \n"
                        fi
                    else
                        echo "Unable to retrieve job status. Retrying in 1 minute..."
                    fi
                done
                cd "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}"
		hadd -f -k "${base_name}_qcut_${qcut}_combined.root" */*.root
            done
        else
            echo "Skipping invalid gridpack: $gridpack"
        fi
    done

    echo "Step 3 complete!"
fi


ROOT_FILES_DIR="$CMSSW_EOS_DIR/Event_generation"
HISTOGRAMS_FILES_DIR="$CMSSW_EOS_DIR/Histograms"
PLOTDJR_SCRIPT="$SCRIPT_DIR/plotdjr.C"
DISCONTINUITY_SCRIPT="$SCRIPT_DIR/get_discontinuity.py"
METRICS_DIR="$CMSSW_EOS_DIR/Metrics"


if [[ "$STUDY_DJR_CONTINUITY" = true ]]; then
    # Ensure output directories exist
    mkdir -p "$HISTOGRAMS_FILES_DIR"
    
    cd $CMSSW_DIR
    cmsenv

    # Iterate over all base_name directories (mass point + xqcut) in HADRONIZATION_DIR
    for base_dir in "$ROOT_FILES_DIR"/*; do
        if [[ ! -d "$base_dir" ]]; then
            continue  # Skip if it's not a directory
        fi

        # Extract base name (e.g., mass point + xqcut) from the directory name
        base_name=$(basename "$base_dir")

        # Iterate over different qcut values inside each base_name directory
        for qcut_dir in "$base_dir"/*; do
            if [[ ! -d "$qcut_dir" ]]; then
                continue  # Skip if it's not a directory
            fi

            # Extract qcut from the directory name (assuming qcut is part of the directory name)
            qcut=$(basename "$qcut_dir" | sed 's/^qcut_//')

            # Iterate over all ROOT files in the current qcut directory
            for root_file in "$qcut_dir"/*.root; do
                if [[ ! -f "$root_file" ]]; then
                    echo "No ROOT files found in $qcut_dir."
                    exit 1
                fi

                # Extract the base name from the ROOT file (e.g., mass point, xqcut, qcut)
		root_file_basename=$(basename "$root_file" .root | sed 's/^_combined//')

                echo $root_file_basename
                # Assuming the base_name format includes xqcut and qcut values, e.g., "ttbarDM__1000_xqcut_30"
		if [[ ! "$root_file_basename" =~ ttbarDM__(.*)_xqcut_([0-9]+)_qcut_([0-9]+) ]]; then
			echo "Skipping unrecognized file: $root_file"
			continue
		fi

                # Extract mass point, xqcut, and qcut from the filename
                mass_point="${BASH_REMATCH[1]}"
                xqcut="${BASH_REMATCH[2]}"
                qcut="${BASH_REMATCH[3]}"
                
                mkdir -p $METRICS_DIR/$mass_point

		cd $METRICS_DIR/$mass_point

                # Perform the required analysis on the ROOT file (e.g., plot, compute metric, etc.)
                echo "Processing ROOT file for mass_point: $mass_point, xqcut: $xqcut, qcut: $qcut"

                outfile="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}_plots.pdf"
                outroot="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}.root"

                # Generate DJR histograms
                echo "Generating histograms for xqcut=$xqcut, qcut=$qcut..."
                root -b -q "${PLOTDJR_SCRIPT}(\"$root_file\", \"$outfile\", \"$outroot\")"

                # Compute DJR1 discontinuity metric
                echo "Computing discontinuity for xqcut=$xqcut, qcut=$qcut..."
                
		if [[ ! -f metric.txt ]]; then
			echo "xqcut, qcut, discontinuity" > metric.txt
		else
			python3 "$SCRIPT_DIR/get_discontinuity.py" "$outroot" "hall_djr0" "$xqcut" "$qcut" "$METRICS_DIR/$mass_point/metric.txt"
		fi
            done
        done
    done

    echo "Step 4 complete!"
fi

METRIC_BEST_RESUTS_FILE="$SCRIPT_DIR/results_metric.txt"

if [[ "$FIND_BEST_CONFIGURATION" = true ]]; then
# Step 5: Find best configuration and optionally remove others

# After the processing loop that generates the metric.txt files

# Create or clear the best_configuration.txt file
best_config_file="$SCRIPT_DIR/best_configuration.txt"
echo "mass_point, xqcut, qcut, discontinuity" > "$best_config_file"

# Iterate over all mass point directories inside METRICS_DIR
for mass_point_dir in "$METRICS_DIR"/*; do
    if [[ ! -d "$mass_point_dir" ]]; then
        continue  # Skip if it's not a directory
    fi

    mass_point=$(basename "$mass_point_dir")
    metric_file="$mass_point_dir/metric.txt"

    if [[ ! -f "$metric_file" ]]; then
        echo "No metric.txt found for mass point: $mass_point"
        continue  # Skip if no metric.txt file is found
    fi

    # Find the best configuration by sorting metric.txt based on discontinuity value
    # (Assuming that the discontinuity value is the last column in the metric.txt file)
    best_config=$(sort -t, -k4 -n "$metric_file" | head -n 1)

    # Extract mass_point, xqcut, qcut, discontinuity from the best configuration line
    mass_point_best=$(echo "$best_config" | cut -d, -f1)
    xqcut_best=$(echo "$best_config" | cut -d, -f2)
    qcut_best=$(echo "$best_config" | cut -d, -f3)
    discontinuity_best=$(echo "$best_config" | cut -d, -f4)

    # Append the best configuration to the best_configuration.txt file
    echo "$mass_point_best, $xqcut_best, $qcut_best, $discontinuity_best" >> "$best_config_file"

done

echo "Best configurations have been saved to $best_config_file."
    echo "Step 5 complete!"
fi

echo "Process completed."

