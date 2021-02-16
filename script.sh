#!/bin/bash
source_dir=/home/andrey/original/

#Array of destination folders
dest_folders=(
"/home/andrey/destination1/"
"/home/andrey/destination2/"
"/home/andrey/destination3/"
"/home/andrey/destination4/"
"/home/andrey/destination5/"
)

log=/home/andrey/rsync_watch.log

inotifywait -m $source_dir -e close_write | # we define that a new file was added to the folder, which was closed after writing data
    while read dir action file; do
        echo "$(date +%d.%m.%Y\ %T). The file '$dir$file' appeared in via '$action'." >> $log

        for dest in "${dest_folders[@]}"; do
            if [ -d "$dest" ]; #check if destination directory exists 
                then
                    rsync -z -c "$dir$file" $dest #copy with checksum verification for files
                    
                    if [ "$?" -eq "0" ]
                        then
                            echo "DONE: $(date +%d.%m.%Y\ %T). Copied file $dir$file to $dest." >> $log
                        else
                            echo "ERROR: $(date +%d.%m.%Y\ %T). Error while running rsync. File - '$dir$file'." >> $log
                    fi              
                else
                    echo "ERROR: $(date +%d.%m.%Y\ %T). $dest not found. Can not continue." >> $log
            fi
        done       
    done


