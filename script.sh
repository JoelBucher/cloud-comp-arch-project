
# Settings
user=bucherjo
create_cluster=false
install_mcperf=true
run_memcached=true
interactive_mode=true

# Scheduling Policy
scheduling_policy="./policies/nodes"

# Files
client_a_log="client_a.log"
client_b_log="client_b.log"
client_measure_log="client_measure.log"
result_file="results.json"

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
    echo "scheduling policy \t $scheduling_policy"
    echo "create cluster \t\t $( [ "$create_cluster" = "true" ] && echo "✅" || echo "❌" )"
    echo "install mcperf \t\t $( [ "$install_mcperf" = "true" ] && echo "✅" || echo "❌" )"
    echo "run memcached \t\t $( [ "$run_memcached" = "true" ] && echo "✅" || echo "❌" )"
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
    nohup gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2" >> $scheduling_policy/$3 &
}

compute_remote () {
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2"
}

create_environment () {
    output "[process] setting variables..."
    export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-$user/
    PROJECT='gcloud config get-value project'

    rm $scheduling_policy/$client_a_log
    rm $scheduling_policy/$client_b_log
    rm $scheduling_policy/$client_measure_log
    rm $scheduling_policy/$result_file
}

create_cluster () {
    generated_yaml=./generated/part3.yaml

    output "[process] generating cluster files"
    sed "s/NETHZ/$user/g" part3.yaml > $generated_yaml

    output "[process] creating part3..."
    kops create -f $generated_yaml

    output "[process] updating cluster..."
    kops update cluster --name part3.k8s.local --yes --admin

    output "[process] validating cluster..."
    kops validate cluster --wait 10m

    kubectl get nodes -o wide
}

install_mcperf () {
    # install modified version of mcperf on client-agent-a and client-agent-b
    output "[process] install mcperf..."

    for nodetype in "client-agent-a" "client-agent-b" "client-measure"; do
        machine=$(kubectl get nodes -l cca-project-nodetype=$nodetype -o=jsonpath='{.items[*].metadata.name}')

        output "[process] install mcperf on $machine ..."

        compute_remote $machine "sudo sh -c 'echo deb-src http://europe-west3.gce.archive.ubuntu.com/ubuntu/ jammy main restricted >> /etc/apt/sources.list'"
        compute_remote $machine "sudo apt-get update"
        compute_remote $machine "sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes"
        compute_remote $machine "sudo apt-get build-dep memcached --yes"
        compute_remote $machine "git clone https://github.com/eth-easl/memcache-perf-dynamic.git"
        compute_remote $machine "cd memcache-perf-dynamic && make"

        if [[ $nodetype == "client-agent-a" ]]; then
            compute_background_remote $machine "cd memcache-perf-dynamic && ./mcperf -T 2 -A" $client_a_log
            a_ip=$(kubectl get nodes $machine -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        fi

        if [[ $nodetype == "client-agent-b" ]]; then
            compute_background_remote $machine "cd memcache-perf-dynamic && ./mcperf -T 4 -A" $client_b_log
            b_ip=$(kubectl get nodes $machine -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        fi
       
        if [[ $nodetype == "client-measure" ]]; then
            # we run memcache-server on node 3
            memcached_ip=$(kubectl get pods some-memcached -o=jsonpath='{.status.podIP}')

            echo "internal ip of memcache server is $memcached_ip"
            echo "internal ip of agent A is $a_ip"
            echo "internal ip of agent B is $b_ip"

            output "[process] loading memcached..."
            compute_remote $machine "cd memcache-perf-dynamic && ./mcperf -s $memcached_ip --loadonly"
            
            output "[process] starting memcached..."
            compute_background_remote $machine "cd memcache-perf-dynamic && ./mcperf -s $memcached_ip -a $a_ip -a $b_ip --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5" $client_measure_log
        fi
    done
}

# run PARSEC jobs from tasks 1 & 2
parsec_jobs () {
    output "[process] clean up jobs..."
    kubectl delete jobs --all

    output "[process] invoking parsec scheduling policy..."
    sh $scheduling_policy/policy.sh
}

run_memcached () {
    output "[process] creating memcached..."
    kubectl create -f memcache-t1-cpuset.yaml
    kubectl expose pod some-memcached --name some-memcached-11211  --type LoadBalancer --port 11211 --protocol TCP
    sleep 60
    kubectl get service some-memcached-11211
}

if "$interactive_mode"; then
    interactive_mode
fi

create_environment

if "$create_cluster"; then
    create_cluster
fi

if "$run_memcached"; then
    output "[process] clean up memcached..."
    kubectl delete service some-memcached-11211
    kubectl delete pod some-memcached
    run_memcached
fi 

if "$install_mcperf"; then
    install_mcperf
fi

parsec_jobs

output "[process] running tests..."
kubectl get pods -o json > $scheduling_policy/$result_file
python3 get_time.py $scheduling_policy/$result_file

output "[success] all running"