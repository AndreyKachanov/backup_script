#!/bin/bash
source_dir=/home/andrey/original/

#Array of destination folders
dest_folders=(
"/home/andrey/destination1/"
"/home/andrey/destination2/"
"/home/andrey/destination3/"
)

log=/home/andrey/rsync_watch.log

inotifywait -m $source_dir -e close_write | # определяем, что в папку был добавлен новый файл, который был закрыт после записи в него данных
    while read dir action file; do
        echo "$(date +%d.%m.%Y\ %T). The file '$dir$file' appeared in via '$action'." >> $log
        
        for dest in "${dest_folders[@]}"; do 
            echo $dest >> $log

            rsync -z -c "$dir$file" $dest # копирование с проверкой контрольных сумм для файлов
            if [ "$?" -eq "0" ]
                then
                  echo "DONE: $(date +%d.%m.%Y\ %T).Copied file $dir$file to $dest." >> $log
                else
                  echo "ERROR: $(date +%d.%m.%Y\ %T). Error while running rsync. File - '$dir$file'." >> $log
            fi

        done       
    done


