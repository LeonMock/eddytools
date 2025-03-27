#!/bin/bash
#SBATCH --job-name=tracking
#SBATCH --output=tracking_%j.out
#SBATCH --error=tracking_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=64G
#SBATCH --time=00:05:00
#SBATCH --partition=base
#SBATCH --mail-user=lmock@geomar.de
#SBATCH --mail-type=ALL

# Activate Conda environment
export PATH=/gxfs_work/geomar/smomw523/miniconda3/bin:$PATH
source /gxfs_work/geomar/smomw523/miniconda3/etc/profile.d/conda.sh
conda activate py3-eddytools

# Change to working directory
cd /gxfs_work/geomar/smomw523/eddytools/

# Define periods
periods=(
    "2012-01-01 2012-01-25" "2012-01-26 2012-02-19" "2012-02-20 2012-03-15"
    "2012-03-16 2012-04-09" "2012-04-10 2012-05-04" "2012-05-05 2012-05-29"
    "2012-05-30 2012-06-28" "2012-06-29 2012-07-28" "2012-07-29 2012-08-27"
    "2012-08-28 2012-09-26" "2012-09-27 2012-10-26" "2012-10-27 2012-11-20"
    "2012-11-21 2012-12-15" 
)

# Detection parameters
experiment_name='INALT60.L120-KRS0020'
data_resolution='1d'
Npix_min=2025 #45*45
Npix_max=15000 #500*6*5
OW_thr_factor=-0.3
sigma=9
wx=1500 #100*15
wy=1500 #100*15

set -e

# Tracking parameters
tracking_start=$(echo ${periods[0]} | cut -d ' ' -f 1)
tracking_end=$(echo ${periods[-1]} | cut -d ' ' -f 2)
tracking_start_nodash=$(echo $tracking_start | tr -d '-')
tracking_end_nodash=$(echo $tracking_end | tr -d '-')
minimum_duration=5
first_or_last_crossing='first'

# Ensure output directory exists
mkdir -p workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/

tracking_notebooks=(
    "workflow/6a-tracking.ipynb"
    "workflow/6b-crossing_Good-Hope_section.ipynb"
)

# Iterate over notebooks and periods
declare -A pids
for i in "${!periods[@]}"; do
period="${periods[$i]}"
    (
    tracking_start=$(echo $period | cut -d ' ' -f 1)
    tracking_end=$(echo $period | cut -d ' ' -f 2)
    tracking_start_nodash=$(echo $tracking_start | tr -d '-')
    tracking_end_nodash=$(echo $tracking_end | tr -d '-')
    for notebook in "${tracking_notebooks[@]}"; do
        output_name=$(basename "$notebook" .ipynb)
        notebook_folder="workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/$(echo $output_name | cut -d '-' -f 1)"
        mkdir -p "$notebook_folder"
        output_path="$notebook_folder/${output_name}_${tracking_start_nodash}-${tracking_end_nodash}.ipynb"
        srun --ntasks=1 --exclusive papermill "$notebook" "$output_path" \
            -p tracking_start $tracking_start -p tracking_end $tracking_end \
            -p Npix_min $Npix_min -p Npix_max $Npix_max \
            -p OW_thr_factor $OW_thr_factor -p sigma $sigma -p wx $wx -p wy $wy \
            -p minimum_duration $minimum_duration -p first_or_last_crossing $first_or_last_crossing \
            -k python
    done
    ) &
    pids[$i]=$!
done

# Wait for all periods to finish
for pid in "${pids[@]}"; do
    wait $pid
done

# Print resource infos
jobinfo