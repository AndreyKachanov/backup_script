#!/bin/bash
#source_dir=/oracle/backup/arch/
source_dir=/oracle/temp/original/

#Array of destination folders
dest_folders=(
"/oracle/temp/destination1/"
)

log=/oracle/temp/rsync_watch.log


function checkArchiveLogFileInView {
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

function rsyncCopy {
    rsync -z -c "$1$2" $3 #копируем файл в эту папку
    if [ "$?" -eq "0" ]
        then
            echo "    DONE:$(date +%d.%m.%Y\ %T). Copied file '$2' to '$3'." >> $log
        else
            echo "    ERROR:$(date +%d.%m.%Y\ %T). Error while running rsync. File - '$1$2', destination folder - '$3'." >> $log
    fi 
}

inotifywait -m $source_dir -e close_write | # we define that a new file was added to the folder, which was closed after writing data
    while read dir action file; do
        echo "$file" >> $log
        echo " " >> $log
        
        fileSizeMb=$(ls -l --block-size=MB "$dir$file" | awk '{print $5}')
        fileSizeBytes=$(ls -l "$dir$file" | awk '{print $5}')
        md5sumNewFile=$(md5sum "$dir$file" | awk '{ print $1 }')
        
        echo "$(date +%d.%m.%Y\ %T). The file '$dir$file' appeared in via '$action'. Size - $fileSizeMb, $fileSizeBytes byte, Md5 checksum - $md5sumNewFile." >> $log

        courtRowsInView=$(checkArchiveLogFileInView $file)

        if [ "$courtRowsInView" -gt "0" ]  #if in system view v$archived_log have $file
            then
                echo "System view v\$archived_log have $courtRowsInView rows with archived log file '$file'. Start copying to destination folders:" >> $log
                for dest in "${dest_folders[@]}"; do
                    if [ -d "$dest" ]; #check if destination directory exists 
                        then
                            if [ ! -f "$dest$file" ] #если в папке назначения нет этого файла
                                then
                                    rsyncCopy $dir $file $dest                                   
                                else #если в папке назначения файл уже есть
                                    md5sumOldFile=$(md5sum "$dest$file" | awk '{ print $1 }')
                                    if [ "$md5sumNewFile" -ne "md5sumOldFile" ] #если md5 суммы разные - копируем файл в папку
                                        then
                                            echo "$(date +%d.%m.%Y\ %T). Md5 summ new file '$dir$file' - '$md5sumNewFile' != md5 summ old file '$dest$file'- '$md5sumOldFile'. Copy file." >> $log
                                            rsyncCopy $dir $file $dest
                                        else
                                            echo "$(date +%d.%m.%Y\ %T). Md5 summ new file '$dir$file' - '$md5sumNewFile' == md5 summ old file '$dest$file'- '$md5sumOldFile'. Do not copy file." >> $log
                                    fi   
                            fi

                            # если в новой папке нет такого файла
                            #     then
                            #         копируем файл в папку
                            #     else
                            #         если md5 нового файла != md5 файла в папке
                            #             then
                            #                 копируем новый файл в папку.                       
                                         
                        else
                            echo "    ERROR:$(date +%d.%m.%Y\ %T). The folder '$dest' not found. Can not be copy file '$file'." >> $log
                    fi
                done                                   
            else
                echo "!!! $(date +%d.%m.%Y\ %T). System view v\$archived_log have $courtRowsInView rows with archived log file '$file'. Do not copy files." >> $log 
        fi
        echo "------------------------------------------------------------------------------------------------------------------------" >> $log      
    done