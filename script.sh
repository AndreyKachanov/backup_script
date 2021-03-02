#!/bin/bash
source_dir=/oracle/backup/arch/
# source_dir=/oracle/temp/original/

#Array of destination folders
dest_folders=(
"/storeonce/reyestr/arch/"
"/backup/arch/"
"/nbackup/reyestr-backup/arch/"
)

# dest_folders=(
# "/oracle/temp/destination1/"
# "/oracle/temp/destination2/"
# )

# log=/oracle/temp/watch_rsync.log
# json_log=/oracle/temp/json_log.json

json_log=/oracle/script/json_log.json
json_log_tmp=/oracle/script/json_log.json.tmp

log=/oracle/script/watch_rsync.log

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
            echo ", \"$dest\": \"$(date +%d.%m.%Y\ %T)\""
        else
            echo "    ERROR:$(date +%d.%m.%Y\ %T). Error while running rsync. File - '$1$2', destination folder - '$3'." >> $log
            echo ", \"$dest\": \"rsync error"
    fi 
}

inotifywait -m $source_dir -e close_write | # we define that a new file was added to the folder, which was closed after writing data
    while read dir action file; do
        echo "$file" >> $log
        
        fileSizeMb=$(ls -l --block-size=MB "$dir$file" | awk '{print $5}')
        fileSizeBytes=$(ls -l "$dir$file" | awk '{print $5}')
        md5sumNewFile=$(md5sum "$dir$file" | awk '{ print $1 }')
        
        echo "$(date +%d.%m.%Y\ %T). Файл '$dir$file' появился с помощью действия '$action'. Размер - $fileSizeMb, $fileSizeBytes byte, Md5 checksum - $md5sumNewFile." >> $log

        courtRowsInView=$(checkArchiveLogFileInView $file)

        if [ "$courtRowsInView" -gt "0" ]  #if in system view v$archived_log have $file
            then
                echo "Проверка файла '$file' в v\$archived_log. Кол-во записей = $courtRowsInView. Stamp файла является наивысшим, т.е. журнал самый последний, свежий. Начинаем копирование по папкам:" >> $log
                
                # sequence="1"
                # json="\"sequence\": \"$sequence\", \"file\": \"$file\""
                json="\"file\": \"$file\""
                

                for dest in "${dest_folders[@]}"; do
                    if [ -d "$dest" ]; #check if destination directory exists 
                        then

                            if [ ! -f "$json_log" ] #если нет файла для лога json, создаем его
                                then echo "[]" > $json_log
                            fi 

                            if [ ! -f "$dest$file" ] #если в папке назначения нет этого файла
                                then
                                    echo "В папке '$dest' файла '$file' нет. Начинаем копирование." >> $log
                                    json+=$(rsyncCopy $dir $file $dest)
                                    # json+=", \"$dest\": \"$(date +%d.%m.%Y\ %T)\""                                   
                                else #если в папке назначения файл уже есть
                                    echo "В папке '$dest' файл '$file' уже есть. Проверка Md5sum файлов:" >> $log
                                    md5sumOldFile=$(md5sum "$dest$file" | awk '{ print $1 }')
                                    if [ "$md5sumNewFile" != "$md5sumOldFile" ] #если md5 суммы разные - копируем файл в папку
                                        then
                                            echo "    Md5sum '$dir$file' - '$md5sumNewFile' != md5sum '$dest$file' - '$md5sumOldFile'. Файл копируем." >> $log
                                            json+=$(rsyncCopy $dir $file $dest)
                                        else
                                            echo "    Md5sum '$dir$file' - '$md5sumNewFile' == md5sum '$dest$file' - '$md5sumOldFile'. Файл не копируем." >> $log
                                    fi   
                            fi                                
                                   

                        else
                            echo "    ERROR: Папки '$dest' нет. Файл '$file' не скопирован." >> $log
                            json+=", \"$dest\": \"папка отсутствует\""
                    fi
                done

                SUB1=${dest_folders[0]}
                SUB2=${dest_folders[1]}
                SUB3=${dest_folders[2]}

                if [[ "$json" == *"$SUB1"* ]] || [[ "$json" == *"$SUB2"* ]]  || [[ "$json" == *"$SUB3"* ]]   
                    then
                        cp $json_log $json_log_tmp && jq ".[.| length] |= . + {$json}" $json_log_tmp > $json_log && rm $json_log_tmp
                        rsync -c $json_log oracle@10.1.11.121:/home/oracle/site
                        if [ "$?" -eq "0" ]
                            then
                                echo "json отправлен" >> $log
                            else
                                echo "json не отправлен. rsync error" >> $log
                        fi
                    else
                        echo "В json файле нет нужных ключей, файл не отправлен." >> $log                
                fi                 
                # cp $json_log $json_log_tmp && jq ".[.| length] |= . + {$json}" $json_log_tmp > $json_log && rm $json_log_tmp
                # rsync -c $json_log oracle@10.1.11.121:/home/oracle/site                                   
            else
                echo "Проверка файла '$file' в v\$archived_log. Кол-во записей = $courtRowsInView. Журнал не свежий - файл не последний в списке. Не копируем." >> $log 
        fi
        echo "------------------------------------------------------------------------------------------------------------------------" >> $log      
    done