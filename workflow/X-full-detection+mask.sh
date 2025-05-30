#!/bin/bash
#SBATCH --job-name=detection
#SBATCH --ntasks=14
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=64G
#SBATCH --time=24:00:00
#SBATCH --partition=base
#SBATCH --mail-user=lmock@geomar.de
#SBATCH --mail-type=ALL

# Activate Conda environment
export PATH=/gxfs_work/geomar/smomw523/miniconda3/bin:$PATH
source /gxfs_work/geomar/smomw523/miniconda3/etc/profile.d/conda.sh
conda activate py3-eddytools

# Change to working directory
cd /gxfs_work/geomar/smomw523/eddytools/

# Detection parameters
experiment_name='INALT60.L120-KRS0020' #'INALT20r.L120-KRS006'
data_resolution='1d'
OW_thr_factor=-0.3

if [[ "$experiment_name" == INALT60* ]]; then
    Npix_min=720 #= (sqrt(20)*6)**2 based on JKR with 1/10
    Npix_max=18000 #= (sqrt(500)*6)**2
    sigma=15 # --> 1/4
    wx=600 #100*6
    wy=600
    periods=(
    "2012-01-01 2012-01-25" "2012-01-26 2012-02-19" "2012-02-20 2012-03-15"
    "2012-03-16 2012-04-09" "2012-04-10 2012-05-04" "2012-05-05 2012-05-29"
    "2012-05-30 2012-06-28" "2012-06-29 2012-07-28" "2012-07-29 2012-08-27"
    "2012-08-28 2012-09-26" "2012-09-27 2012-10-26" "2012-10-27 2012-11-20"
    "2012-11-21 2012-12-15" "2012-12-16 2012-12-31"
    )
elif [[ "$experiment_name" == INALT20* ]]; then
    Npix_min=80 #= (sqrt(20)*2)**2
    Npix_max=2000 #= (sqrt(500)*2)**2
    sigma=5  # --> 1/4
    wx=200 #= 100*5
    wy=200
    periods=(
    "2012-01-01 2012-02-19" "2012-02-20 2012-04-04" "2012-04-05 2012-05-19"
    "2012-05-20 2012-07-03" "2012-07-04 2012-08-17" "2012-08-18 2012-10-01"
    "2012-10-02 2012-11-15" "2012-11-16 2012-12-31"
    )
fi

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

# List of notebooks to run
notebooks=(
    #"workflow/2a-smoothing.ipynb"
    #"workflow/4-OW.ipynb"
    #"workflow/5a-detection.ipynb"
    "workflow/5b-prepare-eddy-masks.ipynb"
    "workflow/5c-detection-visualisation.ipynb"
    "workflow/5d-depth-sections.ipynb"
)
tracking_notebooks=(
    "workflow/6a-tracking.ipynb"
    "workflow/6b-crossing_Good-Hope_section.ipynb"
)

# Iterate over notebooks and periods
declare -A pids
for i in "${!periods[@]}"; do
    period="${periods[$i]}"
    (
    datestart=$(echo $period | cut -d ' ' -f 1)
    dateend=$(echo $period | cut -d ' ' -f 2)
    datestart_nodash=$(echo $datestart | tr -d '-')
    dateend_nodash=$(echo $dateend | tr -d '-')
        for notebook in "${notebooks[@]}"; do
            output_name=$(basename "$notebook" .ipynb)
            notebook_folder="workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/$(echo $output_name | cut -d '-' -f 1)"
            mkdir -p "$notebook_folder"
            output_path="$notebook_folder/${output_name}_${datestart_nodash}-${dateend_nodash}.ipynb"
            srun --ntasks=1 --exclusive papermill "$notebook" "$output_path" \
                -p experiment_name $experiment_name -p data_resolution $data_resolution \
                -p datestart $datestart -p dateend $dateend \
                -p Npix_min $Npix_min -p Npix_max $Npix_max \
                -p OW_thr_factor $OW_thr_factor -p sigma $sigma -p wx $wx -p wy $wy \
                -k python
        done
    ) &
    pids[$i]=$!
done

# Wait for all periods to finish
for pid in "${pids[@]}"; do
    wait $pid
done

# Run tracking notebooks only once at the end
for notebook in "${tracking_notebooks[@]}"; do
    output_name=$(basename "$notebook" .ipynb)
    notebook_folder="workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/$(echo $output_name | cut -d '-' -f 1)"
    mkdir -p "$notebook_folder"
    output_path="$notebook_folder/${output_name}_${tracking_start_nodash}-${tracking_end_nodash}.ipynb"
    srun --ntasks=1 --exclusive papermill "$notebook" "$output_path" \
        -p experiment_name $experiment_name -p data_resolution $data_resolution \
        -p tracking_start $tracking_start -p tracking_end $tracking_end \
        -p Npix_min $Npix_min -p Npix_max $Npix_max \
        -p OW_thr_factor $OW_thr_factor -p sigma $sigma -p wx $wx -p wy $wy \
        -p minimum_duration $minimum_duration -p first_or_last_crossing $first_or_last_crossing \
        -k python
done

# Print resource infos
jobinfo