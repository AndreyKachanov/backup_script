Inotify-tools - осуществляет мониторинг изменении файловой системы в Linux. Это подсистема ядра Linux, которая отслеживает изменения файловой системы в Linux (открытие, чтение, создание, удаление, перемещение, изменение атрибутов и др.).

Установка на sles 11.4:
	sudo rpm -Uvh libinotifytools0-3.14-4.1.x86_64.rpm
	sudo rpm -Uvh inotify-tools-3.14-9.1.x86_64.rpm
Проверка:
	inotifywait --help	

Создадим скрипт, который прослушивает папку на добавление новых файлов:
	nano /oracle/script/watch_rsync.sh	

	Тело скрипта
	---------------------------
	#!/bin/bash
	source_dir=/oracle/backup/arch/
	destination_dir=/oracle/temp/watch_rsync
	log=/oracle/temp/watch_rsync/log.log

	inotifywait -m $source_dir -e close_write | # определяем, что в папку был добавлен новый файл, который был закрыт после записи в него данных
	    while read dir action file; do
	        echo "$(date +%d.%m.%Y\ %T). The file '$dir$file' appeared in via '$action'." >> $log
	        #sleep 20
	         rsync -z -c "$dir$file" $destination_dir # копирование с проверкой контрольных сумм для файлов
	         if [ "$?" -eq "0" ]
	             then
	               echo "DONE: $(date +%d.%m.%Y\ %T).Copied file $dir$file to $destination_dir." >> $log
	             else
	               echo "ERROR: $(date +%d.%m.%Y\ %T). Error while running rsync. File - '$dir$file'." >> $log
	         fi
	    done
	----------------------------

	chmod u+x /oracle/script/watch_rsync.sh

	После того, как в папку добавился новый файл (именно уже добавился, а не только начал добавляться), сработает скрипт,
	который командой rsync -c скопирует его в нужные папки. Флаг -с означает, что копирование происходит с проверкой контрольных сумм файлов.
	Если контрольная сумма не сойдётся - ошибка упадёт в лог файл. Так же в логе хранится информация когда файл был добавлен, когда был скопирован.

Запуск скрипта в фоновом режиме:
	nohup /oracle/script/watch_rsync.sh > /dev/null 2>&1 &

	nohup - позволяет запускать команды даже после выхода из системы.
	> /dev/null 2>&1 - означает перенаправление stdout на /dev/null и stderr на stdout, т.е. чтобы в терминал ничего не выводилось...
	& - символ амперсанда (&) в конце команды означает запустить команду в фоновом режиме.


Просмотр запущенного процесса:
	oracle@reyestr-backup:~> ps -ef | grep watch_rsync.sh

	oracle   31444 31001  0 20:13 pts/3    00:00:00 /bin/bash /oracle/script/watch_rsync.sh
	oracle   31446 31444  0 20:13 pts/3    00:00:00 /bin/bash /oracle/script/watch_rsync.sh
	oracle   31481 31001  0 20:13 pts/3    00:00:00 grep watch_rsync.sh

Завершение фонового процесса:
	kill -9 31444 && kill -9 31446
Не знаю почему, но создаётся 2 процесса. Убиваем 2 шт...