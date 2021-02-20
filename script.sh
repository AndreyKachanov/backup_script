#!/bin/bash
source_dir=/oracle/backup/arch/
# source_dir=/oracle/temp/original/

#Array of destination folders
dest_folders=(
"/storeonce/reyestr/arch/"
"/backup/arch/"
"/nbackup/reyestr-backup/arch/"
)

log=/oracle/temp/rsync_watch.log

# Фунция проверяет, является ли "измененный" архивный журнал в папке source_dir самым последним в v$archived_log.
# Ищу добавленный файл в списке v$archived_log и проверяю его дату добавления (stamp), 
# чтобы эта дата была равной или была самой наибольшей из всех журналов в v$archived_log. 
# Проверку сделал после того, как в папку /backup/arch/ начали копироваться старые журналы, который оракл почему-то начал открывать и закрывать на запись. 
function checkArchiveLogFileInView {
result=$(sqlplus -s /nolog <<EOL
connect / as sysdba
set head off
set feedback off
set pagesize 2400
set linesize 2048
select count(*) from v\$archived_log where name like '%$1' and stamp >= (select max(stamp) from v\$archived_log);
exit;
EOL
)
echo $result;
}

function rsyncCopy {
    rsync -z -c "$1$2" $3 #копируем файл в эту папку
    if [ "$?" -eq "0" ]
        then
            echo "    DONE:$(date +%d.%m.%Y\ %T). Файл '$2' скопирован в папку'$3'." >> $log
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
        
        echo "$(date +%d.%m.%Y\ %T). Файл '$dir$file' появился с помощью действия '$action'. Размер - $fileSizeMb, $fileSizeBytes byte, Md5 checksum - $md5sumNewFile." >> $log

        courtRowsInView=$(checkArchiveLogFileInView $file)

        if [ "$courtRowsInView" -gt "0" ]  #if in system view v$archived_log have $file
            then
                echo "Проверка файла '$file' в v\$archived_log. Кол-во записей = $courtRowsInView. Начинаем копирование по папкам:" >> $log
                for dest in "${dest_folders[@]}"; do
                    if [ -d "$dest" ]; #check if destination directory exists 
                        then
                            if [ ! -f "$dest$file" ] #если в папке назначения нет этого файла/ 
                                then
                                    echo "В папке '$dest' файла '$file' нет. Начинаем копирование." >> $log
                                    rsyncCopy $dir $file $dest                                   
                                else #если в папке назначения файл уже есть
                                    echo "В папке '$dest' файл '$file' уже есть. Проверка Md5sum файлов:" >> $log
                                    md5sumOldFile=$(md5sum "$dest$file" | awk '{ print $1 }')
                                    if [ "$md5sumNewFile" != "$md5sumOldFile" ] #если md5 суммы разные - копируем файл в папку
                                        then
                                            echo "    Md5sum '$dir$file' - '$md5sumNewFile' != md5sum '$dest$file' - '$md5sumOldFile'. Файл копируем." >> $log
                                            rsyncCopy $dir $file $dest
                                        else
                                            echo "    Md5sum '$dir$file' - '$md5sumNewFile' == md5sum '$dest$file' - '$md5sumOldFile'. Файл не копируем." >> $log
                                    fi   
                            fi                                
                        else
                            echo "    ERROR: Папки '$dest' нет. Файл '$file' не скопирован." >> $log
                    fi
                done                                   
            else
                echo "Проверка файла '$file' в v\$archived_log. Кол-во записей = $courtRowsInView. Файл не копируем." >> $log 
        fi
        echo "------------------------------------------------------------------------------------------------------------------------" >> $log      
    done