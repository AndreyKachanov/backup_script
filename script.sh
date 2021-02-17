#!/bin/bash
source_dir=/oracle/temp/original/

#Array of destination folders
dest_folders=(
"/oracle/temp/destination1/"
"/oracle/temp/destination2/"
)

log=/oracle/temp/rsync_watch.log


function checkArchiveLogFile {
result=$(sqlplus -s /nolog <<EOL
connect / as sysdba
set head off
set feedback off
set pagesize 2400
set linesize 2048
select count(*) from v\$archived_log where name like '%$1';
exit;
EOL
)
echo $result;
}

inotifywait -m $source_dir -e close_write | # we define that a new file was added to the folder, which was closed after writing data
    while read dir action file; do
        echo "$(date +%d.%m.%Y\ %T). The file '$dir$file' appeared in via '$action'." >> $log
        # echo "file name =$file" >> $log
        for dest in "${dest_folders[@]}"; do
            if [ -d "$dest" ]; #check if destination directory exists 
                then

                    archiveExists=$(checkArchiveLogFile $file)
                    # echo $archiveExists >> $log
                    # if in system view v$archived_log have $file
                    if [ "$archiveExists" -gt "0" ]
                        then
                            echo "$(date +%d.%m.%Y\ %T). $file have $archiveExists rows in v\$archived_log view." >> $log
                            rsync -z -c "$dir$file" $dest #copy with checksum verification for files
                            if [ "$?" -eq "0" ]
                                then
                                    echo "DONE: $(date +%d.%m.%Y\ %T). Copied file $dir$file to $dest." >> $log
                                else
                                    echo "ERROR: $(date +%d.%m.%Y\ %T). Error while running rsync. File - '$dir$file'." >> $log
                            fi                                    
                        else
                            echo "!!! $(date +%d.%m.%Y\ %T). View v\$archived_log dont have '$file'." >> $log        
                    fi                         
                                 
                else
                    echo "ERROR: $(date +%d.%m.%Y\ %T). $dest not found. Can not continue." >> $log
            fi
        done       
    done