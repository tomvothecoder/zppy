#!/bin/bash
{% include 'slurm_header.sh' %}
{{ environment_commands }}

# Turn on debug output if needed
debug={{ debug }}
if [[ "${debug,,}" == "true" ]]; then
  set -x
fi

# Script dir
cd {{ scriptDir }}

# Get jobid
id=${SLURM_JOBID}

# Update status file
STARTTIME=$(date +%s)
echo "RUNNING ${id}" > {{ prefix }}.status

# Create temporary workdir
workdir=`mktemp -d tmp.${id}.XXXX`
cd ${workdir}

{% if frequency == 'monthly' %}
# --- Monthly climatologies ---
ncclimo \
--case={{ case }} \
--jobs=${SLURM_NNODES} \
--mem_mb=0 \
--thr=1 \
{%- if exclude %}
-n '-x' \
{%- endif %}
{%- if vars != '' %}
--vars={{ vars }} \
{%- endif %}
--parallel=mpi \
--yr_srt={{ yr_start }} \
--yr_end={{ yr_end }} \
--input={{ input }}/{{ input_subdir }} \
{% if mapping_file == '' -%}
--output=output \
{%- else -%}
--map={{ mapping_file }} \
--output=trash \
--regrid=output \
{%- endif %}
--model={{ input_files.split(".")[0] }}

{% elif frequency.startswith('diurnal') %}

# --- Diurnal cycle climatologies ---

# Create symbolic links to input files
input={{ input }}/{{ input_subdir }}
for (( year={{ yr_start }}; year<={{ yr_end }}; year++ ))
do
  YYYY=`printf "%04d" ${year}`
  for file in ${input}/{{ case }}.{{ input_files }}.${YYYY}-*.nc
  do
    ln -s ${file} .
  done
done

# Add the last file of the previous year
year={{ yr_start - 1 }}
YYYY=`printf "%04d" ${year}`
mapfile -t files < <( ls ${input}/{{ case }}.{{ input_files }}.${YYYY}-*.nc 2> /dev/null )
{% raw -%}
if [ ${#files[@]} -ne 0 ]
then
  ln -s ${files[-1]} .
fi
{%- endraw %}
# as well as first file of next year to ensure that first and last years are complete
year={{ yr_end + 1 }}
YYYY=`printf "%04d" ${year}`
mapfile -t files < <( ls ${input}/{{ case }}.{{ input_files }}.${YYYY}-*.nc 2> /dev/null )
{% raw -%}
if [ ${#files[@]} -ne 0 ]
then
  ln -s ${files[0]} .
fi
{%- endraw %}

ls {{ case }}.{{ input_files }}.????-*.nc > input.txt
# Now, call ncclimo
cat input.txt | ncclimo \
--case={{ case }}.{{ input_files }} \
--jobs=${SLURM_NNODES} \
--mem_mb=0 \
--thr=1 \
{%- if exclude %}
-n '-x' \
{%- endif %}
{%- if vars != '' %}
--vars={{ vars }} \
{%- endif %}
--parallel=mpi \
--yr_srt={{ yr_start }} \
--yr_end={{ yr_end }} \
{% if mapping_file == '' -%}
--output=output \
{%- else -%}
--map={{ mapping_file }} \
--output=trash \
--regrid=output \
{%- endif %}
--climatology_mode=hfc

{% else %}
# --- Unsupported climatology mode ---
cd {{ scriptDir }}
echo 'Frequency '{{ frequency }}' is not a valid option'
echo 'ERROR (1)' > {{ prefix }}.status
exit 1

{%- endif %}

if [ $? != 0 ]; then
  cd {{ scriptDir }}
  echo 'ERROR (2)' > {{ prefix }}.status
  exit 2
fi

# Move regridded climo files to final destination
subdir=""
{% if frequency == 'monthly' %}
{
 subdir=clim
}
{% elif frequency.startswith('diurnal') %}
{
 subdir=clim_{{ frequency }}
}
{%- endif %}
dest={{ output }}/post/{{ component }}/{{ grid }}/${subdir}/{{ '%dyr' % (yr_end-yr_start+1) }}
mkdir -p ${dest}
mv output/*.nc ${dest}

if [ $? != 0 ]; then
  cd {{ scriptDir }}
  echo 'ERROR (3)' > {{ prefix }}.status
  exit 3
fi

# Delete temporary workdir
cd ..
if [[ "${debug,,}" != "true" ]]; then
  rm -rf ${workdir}
fi

# Update status file and exit
{% raw %}
ENDTIME=$(date +%s)
ELAPSEDTIME=$(($ENDTIME - $STARTTIME))
{% endraw %}
echo ==============================================
echo "Elapsed time: $ELAPSEDTIME seconds"
echo ==============================================
echo 'OK' > {{ prefix }}.status
exit 0
