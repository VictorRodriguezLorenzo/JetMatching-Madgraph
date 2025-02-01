#!/bin/sh

# Controllers for the whole code
GENERATE_MASS_POINTS=false
GENERATE_GRIDPACKS=false
PERFORM_HADRONIZATION=true
REMOVE_ROOT_FILES=true


# Define directories for the scripts and logs
SCRIPT_DIR="/afs/cern.ch/user/v/victorr/private/tt_DM/tt-DM-q_cut-xqcut-Madgraph"
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
CMSSW_EOS_DIR="/eos/user/v/victorr/ttDM/CMSSW_13_2_9/src"
CMSSW_DIR="$SCRIPT_DIR/CMSSW_13_2_9/src"
CONDOR_SCRIPT="$CMSSW_DIR/runEventGeneration_tmp_to_eos.py"
RESUBMIT_SCRIPT="${CMSSW_DIR}/resubmit_failed_jobs.sh"
FRAGMENT_FILE="/afs/cern.ch/user/v/victorr/private/tt_DM/tt-DM-q_cut-xqcut-Madgraph/CMSSW_13_2_9/src/Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py"
ROOT_FILES_DIR="$CMSSW_EOS_DIR/Event_generation"
HISTOGRAMS_FILES_DIR="$CMSSW_EOS_DIR/Histograms"
PLOTDJR_SCRIPT="$SCRIPT_DIR/plotdjr.C"

if [[ "$PERFORM_HADRONIZATION" = true ]]; then
    echo "Step 3 and 4: Hadronization, job submission, histograms, and metrics generation..."

    cd "$CMSSW_DIR"

    process_qcut() {
	    local gridpack=$1
	    local base_name=$(basename "$gridpack" .tar.xz)
	    local xqcut=$(echo "$base_name" | grep -oP "xqcut_\d+" | grep -oP "\d+")
	    local qcut=$2

	    echo "Processing gridpack: $gridpack (xqcut=$xqcut, qcut=$qcut)"

	    mkdir -p "$CMSSW_EOS_DIR/Event_generation/$base_name/qcut_${qcut}"

	# Submit jobs to HTCondor
	echo "Submitting jobs to HTCondor..."
	python3 "$CONDOR_SCRIPT" -g "$gridpack" -c "$qcut" -r "${base_name}_qcut_${qcut}" \
		-o "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}" \
		-a "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}" -n 20000 -e 1000

	# Monitor job progress
	completed=false

	while [[ $completed == false ]]; do
		sleep 60
		bash "$RESUBMIT_SCRIPT" "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}"

		job_summary=$(condor_q | grep "Total for $USER:")

		if [[ -n "$job_summary" ]]; then
			total_jobs=$(echo "$job_summary" | awk -F ';' '{print $1}' | awk '{print $4}')
			completed_jobs=$(echo "$job_summary" | awk -F ';' '{print $2}' | awk '{print $1}')
			idle_jobs=$(echo "$job_summary" | awk -F ',' '{print $3}' | awk '{print $1}')
			running_jobs=$(echo "$job_summary" | awk -F ',' '{print $4}' | awk '{print $1}')
			held_jobs=$(echo "$job_summary" | awk -F ',' '{print $5}' | awk '{print $1}')

			echo "Total: $total_jobs, Idle: $idle_jobs, Running: $running_jobs, Held: $held_jobs"

			if [[ "$completed_jobs" -eq "$total_jobs" && "$idle_jobs" -eq 0 && "$running_jobs" -eq 0 && "$held_jobs" -eq 0 ]]; then
				echo "All jobs for $base_name with qcut=$qcut are complete!"
				completed=true
			else
				echo "Jobs still in progress. Retrying in 1 minute..."
			fi
		else
			echo "Unable to retrieve job status. Retrying in 1 minute..."
		fi
	done

	# Combine ROOT files
	cd $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}
	cmsenv
	hadd -f -k "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root" \
		"$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}"/*/*.root
			rm -r $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/run_*

	# Generate histograms
	root_file="$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root"
	outfile="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}_plots.pdf"
	outroot="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}.root"

	mkdir -p "$CMSSW_EOS_DIR/Histograms"
	echo "Generating histograms for xqcut=$xqcut, qcut=$qcut..."
	root -l -b -q "${PLOTDJR_SCRIPT}(\"$root_file\", \"$outfile\", \"$outroot\")"
	if [[ "${REMOVE_ROOT_FILES}" = true ]]; then
		rm $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root
	fi
}
    export -f process_qcut
    export CMSSW_DIR CMSSW_EOS_DIR CONDOR_SCRIPT RESUBMIT_SCRIPT FRAGMENT_FILE ROOT_FILES_DIR HISTOGRAMS_FILES_DIR PLOTDJR_SCRIPT

    # Process all gridpacks and qcut values in parallel
    find "/eos/user/v/victorr/gridpacks_1/" -name "*.tar.xz" | parallel -j0 --link "base_name=\$(basename {} .tar.xz); xqcut=\$(echo \$base_name | grep -oP 'xqcut_\\d+' | grep -oP '\\d+'); seq \$xqcut 10 100 | parallel -j0 process_qcut {}"

    echo "Hadronization and histograms generation (steps 3 and 4) complete!"
fi

echo "Process completed."

