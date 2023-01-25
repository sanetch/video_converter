#!/bin/bash
######################################################
# Sanet video conv script
#
# created 16.11.2022 by Andrea Suira
#
# REQUIREMENTS ffmpeg
# Ex command: fmpeg -i input.avi -b 1000k -vcodec libx265 -crf 19 -filter:v fps=fps=24  output.mkv
######################################################
# Changelog:
# 17.11.2022 - Andrea Suira: Modified the logs output with Err level, fixed conversion command, added encoding check and file size check
# 18.11.2022 - Andrea Suira: Added total disk space usage report at the end of the script and fvl in extensions to convert
# 24.11.2022 - Andrea Suira: Added a blacklist after the check of converted bigger files to avoid re-convert on next run
# 25.01.2023 - Andrea Suira: Added files count in log file with percentage of work done/missing

# USER VARIABLES
# Base folder on local machine where the operations/data should be stored during the porcess
work_dir="/home/user/Desktop"
# Folder where the Files to convert are stored
video_dir="/home/user/mnt/Videostation/Movies"
# Output format for converted files
desired_ext=mkv
# Encoded wanted for the converted files, files that already have this encoding will be skipped
desired_enc=hevc #hevc=h265
# Should the converted file be saved despite it is bigger than the original one? yes/no
always_save_converted_file=no

# BASE VARIABLES, keep unchanged if possible
work_tmp_dir=$work_dir/tmp # Temp folder to store the converted video, before overwriting
log_dir=$work_dir/log # Logs folder
log_file=$log_dir/$(date '+%Y-%m-%d_%H%M').log # Log file name, based on date
log_date=$(date '+%Y-%m-%d %H:%M') # Date format to add in the log line
blacklist_file=$work_dir/blacklist.txt # In this file will be printed the names of file that will not be re-converted, as example if the converted file is bigger than the source file
converter_version=1 # The version of the converter, used to skip already converted files that doesn't meet the overwrite requirements, like size (smaller than converted) !!NOT IMPLEMENTED YET
converted_files=0
replaced_files=0
old_files_total_space=0
new_files_total_space=0
files_processed=0
spacing="----------------------------------------------------------------------------------------------" # Ascii separator between files operations

# SCRIPT VARIABLES, DON'T CHANGE
IFS=$'\n'       # make newlines the only separator
OK_STATE=0
OK_LOG="[INFO]"
WARNING_STATE=1
WAR_LOG="[WARNING]"
CRITICAL_STATE=2
CRI_LOG="[CRITICAL]"
UNKNOWN_STATE=8
UNK_LOG="[UNKNOWN]"

# Parameters section (if existing)
display_usage() {
echo -e "\e[32m--------------------------------------------------------------------------------"
echo " Sanet Videos converter script to save space on Movies an TV Series"
echo "  created 16.11.2022 by Andrea Suira"
echo " This script scans a defined folder, grabs the videos file that meet the extension check and doesn't have the requested encoding"
echo " then it copies one by one those file in another (usually local) folder before working on them."
echo " If the new converted file is smaller than the original, the original will be replaced"
echo " Usage:"
echo " $0 [ -param ] [ value ]"
echo " -d Runs the scripty in dry-mode, generating only the log file to check the variable and pre-flight checks of the script."
echo "   example: $0 -d"
echo " -h Launch this help message."
echo "   example: $0 -h"
echo " -w Specify the working folder (the user must have r/w permissions in this folder)."
echo " -v Specify the Videos folder, it could be a remote mounted location."
echo " -f Specify the desired file extension that ffmpeg should convert the files into."
echo " -e Specify the desired encoding type that ffmpeg should convert the files into."
echo -e "\e[37m "
}
while [ $# -gt 0 ]; do
	if [[ $1 == *"-h"* ]]; then
		display_usage
		exit $UNKNOWN_STATE
	fi
	if [[ $1 == *"-d"* ]]; then
		dry_run="yes"
	fi
	if [[ $1 == *"-"* ]]; then
		param="${1/-/}"
		declare $param="$2"
	fi
	shift
done

# Parameters set
if [[ "${w}" ]]; then
	work_dir="${w}"
fi
if [[ "${v}" ]]; then
	video_dir="${v}"
fi
if [[ "${f}" ]]; then
	desired_ext="${f}"
fi
if [[ "${e}" ]]; then
	desired_enc="${e}"
fi

# Save variables to log log_file if work dir exists
if [ ! -d $work_dir ] ; then
	echo "$(date '+%Y-%m-%d %H:%M') - $(tput setaf 1)$CRI_LOG: Work folder doesn't exists... Please check your configuration an re-start the script.'"
	exit 2
fi
# Create base folders
mkdir $work_tmp_dir
mkdir $log_dir
echo "$(date): Script started..." > $log_file
echo "EMTPY LINE TO FILL WILL % OF DONE JOB" >> $log_file
echo "         />_____________________________________________________" >> $log_file
echo "[########[]_______________________T_I_L_L____V_A_L_H_A_L________>" >> $log_file
echo "         \>" >> $log_file
echo -e "Work dir:                $work_dir" >> $log_file
echo -e "work_tmp_dir:            $work_tmp_dir" >> $log_file
echo -e "Desired output format:   $desired_ext" >> $log_file
echo -e "Desired output encoding: $desired_enc" >> $log_file
echo -e "log_file:                $log_file" >> $log_file
echo -e "video_dir:               $video_dir" >> $log_file
echo $spacing >> $log_file
# Pre-flight checks
echo "Pre-flight checks:" >> $log_file
# Work dir check
if touch $work_dir/test.txt ; then
	rm $work_dir/test.txt
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Work directory: OK" >> $log_file
else
	echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: The base Work Dir ($work_dir) did not exist or is not writable" >> $log_file
	echo $spacing >> $log_file
	exit 2
fi
# Videos dir check
if touch $video_dir/test.txt ; then
	rm $video_dir/test.txt
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Videos directory: OK" >> $log_file
else
	echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: The Videos Dir ($video_dir) did not exist or is not writable" >> $log_file
	echo $spacing >> $log_file
	exit 2
fi
# bc existence
if ! command -v bc &> /dev/null
then
	echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: bc command could not be found. Is bc installed? (sudo apt install bc)" >> $log_file
	echo $spacing >> $log_file
	exit 2
else
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: bc package: OK" >> $log_file
fi
# ffmpeg existence
if ! command -v ffmpeg &> /dev/null
then
	echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: ffmpeg command could not be found. Is ffmpeg installed? (sudo apt install ffmpeg)" >> $log_file
	echo $spacing >> $log_file
	exit 2
else
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: ffmpeg package: OK" >> $log_file
fi
# ffprobe existence
if ! command -v ffprobe &> /dev/null
then
	echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: ffprobe command could not be found. Is ffmpeg installed? (sudo apt install ffmpeg)" >> $log_file
	echo $spacing >> $log_file
	exit 2
else
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: ffprobe package: OK" >> $log_file
fi
files_count=$(find $video_dir \( -name "*.avi" -o -name "*.mkv" -o -name "*.mp4"  -o -name "*.flv" \) | wc -l)
echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Files to check: $files_count" >> $log_file
echo $spacing >> $log_file

# If the parameter d (dry-run) was set end here the script
if [ "$dry_run" == "yes" ] ; then
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: This was a dry run! No operation were done on the files..." >> $log_file
	exit 0
fi

# Get all videos
lines=$(find $video_dir \( -name "*.avi" -o -name "*.mkv" -o -name "*.mp4" -o -name "*.flv" \))
for line in $lines
#find $video_dir \( -name "*.avi" -o -name "*.mkv" -o -name "*.mp4" \) | while read line
do
	((files_processed=files_processed+1))
	work_percentage=$(echo "scale=2; 100 / $files_count * $files_processed" | bc)
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: $files_processed/$files_count [$work_percentage%]" >> $log_file
	job_status="Job status: $files_processed/$files_count [$work_percentage%]"
	sed -i "2s#.*#$job_status#" $log_file
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Working on file: $line" >> $log_file
	echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Saved space until now: $((($old_files_total_space-$new_files_total_space)/1024/1024/1024)) GB" >> $log_file
# Generate file variables
	file_size=$(wc -c <"$line")
	file_name_ext=$(basename "$line")
	dir_name=$(dirname "$line")
	file_name=$(basename "${line%.*}")
	file_encoding=$(/usr/bin/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 $line)
# Command 0: If the file is already in the desired encode or is in the blacklist, it will be skipped.
	if grep -Fxq "$line" "$blacklist_file" ; then
		blacklisted="yes"
	else
		blacklisted="no"
	fi
	if [ "$file_encoding" == "$desired_enc" ] || [ "$blacklisted" == "yes" ] ; then
		if [ "$blacklisted" == "yes" ]; then
			echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: File is blacklisted. Skip to next file." >> $log_file
		else
			echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: File encoding is $file_encoding, and match the desired: $desired_enc. Skip to next file." >> $log_file
		fi
	else
		echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Got original filename (with and without ext): $file_name_ext / $file_name" >> $log_file
		echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Got original folder: $dir_name" >> $log_file
		echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Got file encode: $file_encoding" >> $log_file
		echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Copy in work tmp folder started" >> $log_file
# Command 1: Copy original file to work on it in tmp folder
		if cp "$line" "$work_tmp_dir/" ; then
			echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Copy ended" >> $log_file
			echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Start ffmpeg conversion of $work_tmp_dir/$file_name_ext" >> $log_file
			ffmpeg_src="$work_tmp_dir/$file_name_ext"
			ffmpeg_dst="$work_tmp_dir/conv_$file_name.$desired_ext"
			ffmpeg_command="/usr/bin/ffmpeg -i $ffmpeg_src -b 1000k -vcodec libx265 -crf 19 -filter:v fps=fps=24 $ffmpeg_dst -y"
			echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Command: $ffmpeg_command" >> $log_file
# Command 2: Convert the copy file in tmp folder to con_FILENAME.EXTENSION version
			#if /usr/bin/ffmpeg -i $ffmpeg_src -c:v libx265 -vtag hvc1 -c:a copy $ffmpeg_dst -y ; then
			if /usr/bin/ffmpeg -i $ffmpeg_src -b 1000k -vcodec libx265 -crf 19 -filter:v fps=fps=24 $ffmpeg_dst -y ; then
				echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Ended ffmpeg conversion in $work_tmp_dir/conv_$file_name.$desired_ext" >> $log_file
				converted_files=$((converted_files + 1))
				new_file_size=$(wc -c <"$work_tmp_dir/conv_$file_name.$desired_ext")
				echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Original file size: $file_size bytes | New converted file size: $new_file_size bytes" >> $log_file
# Check if the new file is bigger than the original one, if it is, keep the old one and delete the new
				if [ $new_file_size -ge $file_size ] && [ "$always_save_converted_file" == "no" ]; then
					echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: The converted file is bigger than the original one. New file will be deleted, original untouched" >> $log_file
					echo $line >> $blacklist_file
					echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: File added to blacklist to prevent re-conversion next run" >> $log_file
					if rm "$work_tmp_dir/$file_name_ext" ; then
						echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: $work_tmp_dir/$file_name_ext deleted" >> $log_file
					else
						echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete tmp file..." >> $log_file
						break
					fi
					if rm "$work_tmp_dir/conv_$file_name.$desired_ext" ; then
						echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: $work_tmp_dir/conv_$file_name.$desired_ext deleted" >> $log_file
					else
						echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete tmp file..." >> $log_file
						break
					fi
				else
					echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Converted file is smaller. Deleting source files (Original and pre-converted copy):" >> $log_file
# Command 3: Delete the original file
					if rm "$line" ; then
						echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: $line deleted" >> $log_file
# Command 4: Delete the temporary copy file
						if rm "$work_tmp_dir/$file_name_ext" ; then
							echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: $work_tmp_dir/$file_name_ext deleted" >> $log_file
							echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Copying $work_tmp_dir/conv_$file_name.$desired_ext to $dir_name/$file_name.$desired_ext" >> $log_file
# Command 5: Copy the converted temporary file in the original source location, it is now the new original file
							if cp "$work_tmp_dir/conv_$file_name.$desired_ext" "$dir_name/$file_name.$desired_ext" ; then
								echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: File moved." >> $log_file
								replaced_files=$((replaced_files + 1))
								# Calulate old space and saved space
								old_files_total_space=$((old_files_total_space+file_size))
								new_files_total_space=$((new_files_total_space+new_file_size))
# Command 6: Delete the converted temporary file
								if rm "$work_tmp_dir/conv_$file_name.$desired_ext" ; then
									echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Converted tmp file deleted. Process complete, going to next file..." >> $log_file
								else
									echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete tmp file..." >> $log_file
									break
								fi
							else
								echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Copy converted file on original folder failed! Converted file saved in tmp folder" >> $log_file
								break
							fi
						else
							echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete tmp file" >> $log_file
							break
						fi
					else
						echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete original file" >> $log_file
						break
					fi
				fi
			else
				echo "$(date '+%Y-%m-%d %H:%M') - $WAR_LOG: Conversion failed. Ignoring file: $line" >> $log_file
				if rm "$work_tmp_dir/$file_name_ext" ; then
					echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Tmp file deleted." >> $log_file
				else
					echo "$(date '+%Y-%m-%d %H:%M') - $CRI_LOG: Unable to delete tmp file" >> $log_file
					break
				fi
			fi
		else
			echo "$(date '+%Y-%m-%d %H:%M') - $WAR_LOG: Copy failed. Ignoring file: $line" >> $log_file
		fi
	fi
	echo $spacing >> $log_file
done
echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Process completed. Checked $files_count, converted $converted_files, replaced $replaced_files..." >> $log_file
$saved_space
echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Disk space in bytes: Old files usage ($old_files_total_space bytes), new files usage ($new_files_total_space bytes)" >> $log_file
echo "$(date '+%Y-%m-%d %H:%M') - $OK_LOG: Total saved disk space: $((($old_files_total_space-$new_files_total_space)/1024/1024/1024)) GB" >> $log_file
echo $spacing >> $log_file
exit 0
