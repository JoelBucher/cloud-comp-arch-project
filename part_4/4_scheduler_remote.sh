# This file is automatically generated
pid=$(pgrep memcached)
echo "memcached pid is: $pid"
sudo taskset -a -cp 0-1 $pid
sudo apt-get install python3-pip --yes
sudo pip3 install docker
sudo pip3 install psutil
sudo apt install docker.io
newgrp docker
python3 preloader.py
python3 scheduler.py