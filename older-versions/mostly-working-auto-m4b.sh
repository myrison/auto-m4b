#!/bin/bash

# Variables
inputfolder="${INPUT_FOLDER:-"/temp/merge/"}"
outputfolder="${OUTPUT_FOLDER:-"/temp/untagged/"}"
originalfolder="${ORIGINAL_FOLDER:-"/temp/recentlyadded/"}"
fixitfolder="${FIXIT_FOLDER:-"/temp/fix"}"
backupfolder="${BACKUP_FOLDER:-"/temp/backup/"}"
binfolder="${BIN_FOLDER:-"/temp/delete/"}"
m4bend=".m4b"
logend=".log"

# Ensure the expected folder structure
mkdir -p "$inputfolder"
mkdir -p "$outputfolder"
mkdir -p "$originalfolder"
mkdir -p "$fixitfolder"
mkdir -p "$backupfolder"
mkdir -p "$binfolder"

# Fix permissions for the new created folders
username="$(whoami)"
userid="$(id -u $username)"
groupid="$(id -g $username)"
chown -R $userid:$groupid /temp

# Adjust the number of cores depending on the ENV CPU_CORES
if [ -z "$CPU_CORES" ]; then
  echo "Using all CPU cores as none other defined."
  CPUcores=$(nproc --all)
else
  echo "Using $CPU_CORES CPU cores as defined."
  CPUcores="$CPU_CORES"
fi

# Adjust the interval of the runs depending on the ENV SLEEPTIME
if [ -z "$SLEEPTIME" ]; then
  echo "Using standard 1 min sleep time."
  sleeptime=1m
else
  echo "Using $SLEEPTIME min sleep time."
  sleeptime="$SLEEPTIME"
fi

# Function to move folders with multiple audio files and log the details
move_folders_with_multiple_files() {
  folders_moved=()
  echo "Searching for new audio files in $originalfolder"
  find "$originalfolder" -maxdepth 2 -mindepth 2 -type f \( -name '*.mp3' -o -name '*.m4b' -o -name '*.m4a' \) -print0 | xargs -0 -I {} dirname "{}" | sort | uniq -c | awk '$1 > 1 {print substr($0, index($0,$2))}' | while read -r dir; do
    dir=$(echo "$dir" | xargs)  # Trim leading/trailing whitespace
    echo "Attempting to move original directory named '$dir' to input folder named '$inputfolder' for processing"
    if [ -d "$dir" ]; then
      if mv "$dir" "$inputfolder"; then
        folders_moved+=("$dir")
        echo "Moved folder: '$dir' to '$inputfolder'"
      else
        echo "Failed to move '$dir' to '$inputfolder'"
      fi
    else
      echo "Directory '$dir' does not exist."
    fi
  done

  if [ ${#folders_moved[@]} -eq 0 ]; then
    echo "No new folders with multiple audio files found."
  else
    echo "Moving folders with 2 or more audio files to $inputfolder:"
    for folder in "${folders_moved[@]}"; do
      echo "Moved folder: '$folder'"
      find "$folder" -type f \( -name '*.mp3' -o -name '*.m4b' -o -name '*.m4a' \)
    done
  fi
}

echo "* * * * * * * * * * * * * * * * * * * * * *"
echo "Sleep time expired, checking for new files."

# Run indefinitely with sleep intervals
while true; do

  # Copy files to backup destination before any manipulation
  if [ "$(ls -A $originalfolder)" ]; then
    if [ "$MAKE_BACKUP" == "N" ]; then
      echo "Skipping making a backup"
    else
      echo "Making a backup of the whole $originalfolder"
      cp -Ru "$originalfolder"* $backupfolder
    fi
  else
    echo "No files to backup in $originalfolder, skipping backups."
  fi

  # Change to the original folder to correctly read from it
  cd "$originalfolder" || return

  # Make sure all single file mp3's & m4b's are in their own folder
  echo "Making sure all books in $originalfolder are in their own folders"
  for file in "$originalfolder"*.{m4b,mp3}; do
    if [[ -f "$file" ]]; then
      mkdir "${file%.*}"
      mv "$file" "${file%.*}"
    fi
  done

  # Move folders with multiple audio files to inputfolder
  move_folders_with_multiple_files

  # Move folders with nested subfolders to fixitfolder for manual fixing
  nested_folders=$(find "$originalfolder" -maxdepth 3 -mindepth 3 -type f \( -name '*.mp3' -o -name '*.m4b' -o -name '*.m4a' \) -exec sh -c '
    for f do
      gp="$(basename "$(dirname "$(dirname "$f")")")"
      printf "%s\n" "$gp"
    done
  ' sh-find {} + | sort | uniq -d)

  if [ -n "$nested_folders" ]; then
    echo "Nested subfolders cannot be auto-processed, moving to $fixitfolder to adjust manually."
    echo "$nested_folders" | while read j; do mv -v "$originalfolder$j" $fixitfolder; done
  else
    echo "No nested subfolders found."
  fi

  # Move single file mp3's to inputfolder
  single_mp3s=$(find "$originalfolder" -maxdepth 2 -type f \( -name '*.mp3' \) -printf "%h\0")
  if [ -n "$single_mp3s" ]; then
    echo "Finding single file mp3's in $originalfolder"
    echo "Single MP3 directories found:"
    echo "$single_mp3s" | xargs -0 -I {} echo "Checking directory: '{}'"
    echo "$single_mp3s" | xargs -0 -I {} mv "{}" "$inputfolder"
  else
    echo "No single file mp3 files found to move."
  fi

  # Moving the single m4b files to the untagged folder as no Merge needed
  single_m4b=$(find "$originalfolder" -maxdepth 2 -type f \( -iname \*.m4b -o -iname \*.mp4 -o -iname \*.m4a -o -iname \*.ogg \) -printf "%h\0")
  if [ -n "$single_m4b" ]; then
    echo "Finding single file m4b's in $originalfolder"
    echo "Single m4b directories found:"
    echo "$single_m4b" | xargs -0 -I {} echo "Checking directory: '{}'"
    echo "$single_m4b" | xargs -0 -I {} mv "{}" "$outputfolder"
  else
    echo "No single m4b files found to move."
  fi

  # Clear the folders
  rm -r "$binfolder"* 2>/dev/null

  # Doing all scanning for files to process from /merge folder
  cd "$inputfolder" || return
  echo "Scanning for folders ready for conversion."

  if ls -d */ 2>/dev/null; then
    echo "Preparing to convert the folder(s) identified above."
    for book in *; do
      if [ -d "$book" ]; then
        mpthree=$(find "$book" -maxdepth 2 -type f \( -name '*.mp3' -o -name '*.m4b' \) | head -n 1)
        m4bfile="$outputfolder$book/$book$m4bend"
        logfile="$outputfolder$book/$book$logend"
        chapters=$(ls "$inputfolder$book"/*chapters.txt 2> /dev/null | wc -l)
        if [ "$chapters" != "0" ]; then
          echo "Merging chapters file found in directory named "$book" into media file."
          echo "Running command: mp4chaps -i "$inputfolder$book"/*$m4bend"
          mp4chaps -i "$inputfolder$book"/*$m4bend
          mv "$inputfolder$book" "$outputfolder"
        else
          echo "Files found for processing, sampling $mpthree"
          bit=$(ffprobe -hide_banner -loglevel 0 -of flat -i "$mpthree" -select_streams a -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1)
          echo Bitrate = $bit
          echo The folder "$book" will be merged to "$m4bfile"
          echo Starting Conversion
          m4b-tool merge "$book" -n -q --audio-bitrate="$bit" --skip-cover --use-filenames-as-chapters --no-chapter-reindexing --audio-codec=libfdk_aac --jobs="$CPUcores" --output-file="$m4bfile" --logfile="$logfile"
          mv "$inputfolder$book" "$binfolder"
        fi
        echo "**** **** **** SUCCESS: Conversion Completed **** **** ****"
        # Make sure all single file m4b's are in their own folder
        echo Putting the m4b into a folder
        for file in $outputfolder*.m4b; do
          if [[ -f "$file" ]]; then
            mkdir "${file%.*}"
            mv "$file" "${file%.*}"
          fi
        done
      fi
    done
  else
    echo Script complete, next run in $sleeptime min...
    sleep $sleeptime
  fi
done

