
# Settings
user=johanst
create_cluster=false
install_mcperf=true
interactive_mode=true

# log_folder
4_1_logs="./4_1_logs"

# Files
memcache_server_log_4_1="memcache_server_4_1.log"
client_agent_log_4_1="client_agent_4_1.log"
client_measure_log_4_1="client_measure_4_1.log"
result_file_4_1="results_4_1.json"

output () {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo "${RED}$1${NC}"
}

interactive_mode(){
    echo "* -------------------------------------- *"
    echo "|           Awesome CCA Script           |"
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
    nohup gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2" >> $scheduling_policy/$3 
}

compute_remote () {
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2"
}

create_environment () {
    output "[process] setting variables..."
    export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-$user/
    PROJECT='gcloud config get-value project'

    rm $4_1_logs/$memcache_server_log_4_1
    rm $4_1_logs/$client_agent_log_4_1
    rm $4_1_logs/$client_measure_log_4_1
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
    output "[process] install mcperf..."

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
            compute_remote $machine "sudo sed -i '$ a\-t 2' /etc/memcached.conf"

            compute_remote $machine "sudo systemctl restart memcached"
            compute_background_remote $machine "sudo systemctl status memcached" $memcache_server_log_4_1
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
        fi

        if [[ $nodetype == "client-measure" ]]; then
            # part 3 installation
            compute_remote $machine "sudo sh -c 'echo deb-src http://europe-west3.gce.archive.ubuntu.com/ubuntu/ jammy main restricted >> /etc/apt/sources.list'"
            compute_remote $machine "sudo apt-get update"
            compute_remote $machine "sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes"
            compute_remote $machine "sudo apt-get build-dep memcached --yes"
            compute_remote $machine "git clone https://github.com/eth-easl/memcache-perf-dynamic.git"
            compute_remote $machine "cd memcache-perf-dynamic && make"
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

# things to do manually:
# ssh command: gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@<MACHINE_NAME> --zone europe-west3-a

# set number of cores the server is allowed to use for memcached with "sudo taskset -a -cp 0-2 <pid>"
# where pid is the id you get from the verification "sudo systemctl status memcached"
# note, pid changes everytime you restart the service "sudo systemctl restart memcached"

# running load on client agent
#  ./mcperf -T 16 -A

# starting measurment on client measure
# ./mcperf -s INTERNAL_MEMCACHED_IP --loadonly
# ./mcperf -s $memcache_server_ip -a $client_agent_ip  --noload -T 1 -C 1 -D 4 -Q 1000 -c 4 -t 5 --scan 5000:125000:5000