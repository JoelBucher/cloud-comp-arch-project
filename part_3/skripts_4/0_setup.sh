
# Settings
user=bucherjo
create_cluster=true
install_mcperf=true
interactive_mode=true

# log_folder
logs_4="./logs_4"

# Files
memcache_server_log_4="memcache_server_4_1.log"
client_agent_log_4="client_agent_4_1.log"
client_measure_log_4="client_measure_4_1.log"

# Bash Scripts
SCRIPT_1="1_client_agent.sh"
SCRIPT_2="2_client_measure.sh"
SCRIPT_3="3_scheduler.sh"

output () {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo "${RED}$1${NC}"
}

interactive_mode(){
    echo "* -------------------------------------- *"
    echo "|            4.3 Setup Script            |"
    echo "* -------------------------------------- *"
    echo ""
    echo "user \t\t\t $user"
    echo "create cluster \t\t $( [ "$create_cluster" = "true" ] && echo "✅" || echo "❌" )"
    echo "install mcperf \t\t $( [ "$install_mcperf" = "true" ] && echo "✅" || echo "❌" )"
    echo ""
    echo ""
    echo "[Note]: Please make sure that you execute this command in your current active shell before you start the script"
    echo "gcloud auth login && gcloud auth application-default login"
    echo ""
    while true; do
        read -p "Do you want to proceed? (y/n) " yn
        case $yn in 
            [yY] ) echo "starting script...";
                break;;
            [nN] ) echo "exiting...";
                exit;;
            * ) echo invalid response;;
        esac
    done
}

compute_background_remote () {
    nohup gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2" >> $logs_4/$3 
}

compute_remote () {
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2"
}

create_environment () {
    output "[process] setting variables..."
    export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-$user/
    PROJECT='gcloud config get-value project'

    rm $logs_4/$memcache_server_log_4
    rm $logs_4/$client_agent_log_4
    rm $logs_4/$client_measure_log_4
}

create_cluster () {
    generated_yaml=./generated/part4.yaml

    output "[process] generating cluster files"
    sed "s/NETHZ/$user/g" part4.yaml > $generated_yaml

    output "[process] creating part4..."
    kops create -f $generated_yaml

    output "[process] updating cluster..."
    kops update cluster --name part4.k8s.local --yes --admin

    output "[process] validating cluster..."
    kops validate cluster --wait 10m

    kubectl get nodes -o wide
}

install_mcperf () {
    # install modified version of mcperf on client-agent-a and client-agent-b
    output "[process] install mcperf and running services..."

    for nodetype in "memcached" "client-agent" "client-measure"; do
        machine=$(kubectl get nodes -l cca-project-nodetype=$nodetype -o=jsonpath='{.items[*].metadata.name}')

        output "[process] install mcperf on $machine ..."

        if [[ $nodetype == "memcached" ]]; then
            memcache_server_ip=$(kubectl get nodes $machine -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

            compute_remote $machine "sudo apt update"
            compute_remote $machine "sudo apt install -y memcached libmemcached-tools"

            # change config
            compute_remote $machine "sudo sed -i '/^.*-m.*/c\-m 1024' /etc/memcached.conf"
            compute_remote $machine "sudo sed -i '/^.*-l.*/c\-l $memcache_server_ip' /etc/memcached.conf"
            compute_remote $machine "sudo sed -i '$ a\-t 2' /etc/memcached.conf" # maybe only needed for 4.1???

            compute_remote $machine "sudo systemctl restart memcached"
            compute_background_remote $machine "sudo systemctl status memcached" $memcache_server_log_4

            echo "gcloud compute scp ./skripts_4/preloader.py ubuntu@$machine:. --ssh-key-file ~/.ssh/cloud-computing --zone europe-west3-a" >> SCRIPT_3
        fi

        if [[ $nodetype == "client-agent" ]]; then
            client_agent_ip=$(kubectl get nodes $machine -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

            # part 3 installation
            compute_remote $machine "sudo sh -c 'echo deb-src http://europe-west3.gce.archive.ubuntu.com/ubuntu/ jammy main restricted >> /etc/apt/sources.list'"
            compute_remote $machine "sudo apt-get update"
            compute_remote $machine "sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes"
            compute_remote $machine "sudo apt-get build-dep memcached --yes"
            compute_remote $machine "git clone https://github.com/eth-easl/memcache-perf-dynamic.git"
            compute_remote $machine "cd memcache-perf-dynamic && make"

            # better start it manualy, as this part should run after some python scripts are done on the server
            echo 'echo "[process] starting client-agent..."' >> SCRIPT_2
            echo "gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$machine --zone europe-west3-a -- \"./mcperf -T 16 -A\"" >> SCRIPT_2
        fi

        if [[ $nodetype == "client-measure" ]]; then
            # part 3 installation
            compute_remote $machine "sudo sh -c 'echo deb-src http://europe-west3.gce.archive.ubuntu.com/ubuntu/ jammy main restricted >> /etc/apt/sources.list'"
            compute_remote $machine "sudo apt-get update"
            compute_remote $machine "sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes"
            compute_remote $machine "sudo apt-get build-dep memcached --yes"
            compute_remote $machine "git clone https://github.com/eth-easl/memcache-perf-dynamic.git"
            compute_remote $machine "cd memcache-perf-dynamic && make"

            echo "internal ip of memcache server is $memcache_server_ip"
            echo "internal ip of agent is $client_agent_ip"

            output "generating script 3"
            echo "echo \"[process] starting memcached measure...\"" >> SCRIPT_3
            echo "gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$machine --zone europe-west3-a -- \"./mcperf -s $memcache_server_ip --loadonly\"" >> SCRIPT_3
            echo "gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$machine --zone europe-west3-a -- \"./mcperf -s $memcache_server_ip -a $client_agent_ip --noload -T 16 -C 4 -D 4 -Q 1000 -c 4 -t 1800 --qps_interval 10 --qps_min 5000 --qps_max 100000\"" >> SCRIPT_3
        fi
    done
}

if "$interactive_mode"; then
    interactive_mode
fi


if "$create_cluster"; then
    create_environment
    create_cluster
fi

if "$install_mcperf"; then
    install_mcperf
fi

output "[success] all running"

# how to ssh: gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@<MACHINE_NAME> --zone europe-west3-a
# set number of cores the server is allowed to use for memcached with "sudo taskset -a -cp 0-2 <pid>"
# where pid is the id you get from the verification "sudo systemctl status memcached"
# note, pid changes everytime you restart the service "sudo systemctl restart memcached"
# you only need to reststart the service, when changing the confic file
# this can have ovewer side effects, such as the agent or the measure-agent to fail, maybe