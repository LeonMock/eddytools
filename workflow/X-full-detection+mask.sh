#!/bin/bash
set -e
#SBATCH --job-name=detection
#SBATCH --ntasks=13
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=24G
#SBATCH --time=08:00:00
#SBATCH --partition=base
#SBATCH --mail-user=lmock@geomar.de
#SBATCH --mail-type=FAIL

# Load required modules
module load gcc12-env/12.3.0 
module load singularity/3.11.5

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
OW_thr_factor=-0.2
sigma=1
wx=1500 #100*15
wy=1500 #100*15

# Tracking parameters
tracking_start=$(echo ${periods[0]} | cut -d ' ' -f 1)
tracking_end=$(echo ${periods[-1]} | cut -d ' ' -f 2)
minimum_duration=5
first_or_last_crossing='first'

# Ensure output directory exists
mkdir -p workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/

# List of notebooks to run
notebooks=(
    "workflow/4-OW.ipynb"
    "workflow/5a-detection.ipynb"
    "workflow/5b-prepare-eddy-masks.ipynb"
    "workflow/5c-detection-visualisation.ipynb"
    "workflow/5d-depth-sections.ipynb"
)
tracking_notebooks=(
    "workflow/6a-tracking.ipynb"
    "workflow/6b-crossing_Good-Hope_section.ipynb"
)

# Iterate over notebooks and periods, running them sequentially
for notebook in "${notebooks[@]}"; do
    output_name=$(basename "$notebook" .ipynb)
    for period in "${periods[@]}"; do
        datestart=$(echo $period | cut -d ' ' -f 1)
        dateend=$(echo $period | cut -d ' ' -f 2)
        output_path="workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/${output_name}_${datestart}_${dateend}.ipynb"

         srun --ntasks=1 --exclusive singularity run -B /sfs -B /gxfs_work -B $PWD:/work --pwd /work parcels-container_2022.07.14-801fbe4.sif bash -c \
            ". /opt/conda/etc/profile.d/conda.sh && conda activate py3_eddytools && papermill --cwd notebooks \"$notebook\" \"$output_path\" -p datestart $datestart -p dateend $dateend -p Npix_min $Npix_min -p Npix_max $Npix_max -p OW_thr_factor $OW_thr_factor -p sigma $sigma -p wx $wx -p wy $wy -k python"
    done
done

# Run tracking notebooks only once at the end
for notebook in "${tracking_notebooks[@]}"; do
    output_name=$(basename "$notebook" .ipynb)
    output_path="workflow_executed/${experiment_name}/smoothed/${sigma}/${data_resolution}/${output_name}_${tracking_start}_${tracking_end}.ipynb"

     srun --ntasks=1 --exclusive singularity run -B /sfs -B /gxfs_work -B $PWD:/work --pwd /work parcels-container_2022.07.14-801fbe4.sif bash -c \
        ". /opt/conda/etc/profile.d/conda.sh && conda activate py3_eddytools && papermill --cwd notebooks \"$notebook\" \"$output_path\" -p tracking_start $tracking_start -p tracking_end $tracking_end -p Npix_min $Npix_min -p Npix_max $Npix_max -p OW_thr_factor $OW_thr_factor -p sigma $sigma -p wx $wx -p wy $wy -p minimum_duration $minimum_duration -p first_or_last_crossing $first_or_last_crossing -k python"
done

# Print resource infos
jobinfo