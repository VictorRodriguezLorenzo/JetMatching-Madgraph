#!/bin/bash

# Base directory
SCRIPT_DIR="/afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow"
BASE_DIR="$SCRIPT_DIR/genproductions/bin/MadGraph5_aMCatNLO/cards/production/13p6TeV/ttbarDM/ttbarDM_dilepton_pseudoscalar/templatecards"
GRIDPACK_DIR="$SCRIPT_DIR/gridpacks"

# Get inputs from the previous script
xqcut_val=$1      # First argument: xqcut value
mass_point_name=$2      # Second argument: name of the card

cd "$SCRIPT_DIR/genproductions/bin/MadGraph5_aMCatNLO"

# Make sure the gridpack exists, create it otherwise
mkdir -p $GRIDPACK_DIR
mkdir -p $GRIDPACK_DIR/$mass_point_name

if [[ -z "$xqcut_val" || -z "$mass_point_name" ]]; then
    echo "Error: xqcut and card name must be provided."
    exit 1
fi

# Replace '.' with '_' in xqcut_val for the file name
xqcut_val_sanitized=${xqcut_val//./_}

# Modify run_card.dat with the actual value for xqcut
sed -i "s/^.*= xqcut.*$/ ${xqcut_val} = xqcut/" "$BASE_DIR/"*"_run_card.dat"

# Generate gridpack
source /afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow/genproductions/bin/MadGraph5_aMCatNLO/submit_condor_gridpack_generation.sh "ttbarDM__$mass_point_name" "../../../mass_points/ttbarDM__$mass_point_name/" #"slc7_amd64_gcc10" "CMSSW_12_4_8"

# Use the sanitized xqcut value in the final file name
mv ttbarDM__"$mass_point_name"*.tar.xz "$GRIDPACK_DIR/${mass_point_name}/ttbarDM__${mass_point_name}_xqcut_${xqcut_val_sanitized}.tar.xz"

echo "Gridpack generation for xqcut=$xqcut_val and card=$mass_point_name completed!"

