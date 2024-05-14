pid=$(pgrep memcached)
sudo apt-get install python3-pip --yes
sudo pip3 install docker
sudo apt install docker.io
sudo usermod -aG docker ubuntu
newgrp docker

echo "memcached pid is: $pid"
sudo taskset -a -cp 0-2 $pid
python3 preloader.py
python3 scheduler.py
