# DONT FORGET TO CHANGE YAML NETHZ USER
# Login user using 'gcloud auth application-default login'
create_cluster=false
install_mcperf=false
run_memcached=true
log="log.txt"

output () {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo "${RED}$1${NC}"
}

compute_remote () {
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2"
}

set_env_variables () {
    output "[process] setting variables..."
    export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-bucherjo/
    PROJECT='gcloud config get-value project'
}

create_cluster () {
    output "[process] creating part3..."
    kops create -f part3.yaml

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
            compute_remote $machine "nohup cd memcache-perf-dynamic && ./mcperf -T 2 -A &"
            a_ip=$(kubectl get nodes $machine -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        fi

        if [[ $nodetype == "client-agent-b" ]]; then
            compute_remote $machine "nohup cd memcache-perf-dynamic && ./mcperf -T 4 -A &"
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
        fi
    done
}

# run PARSEC jobs from tasks 1 & 2
parsec_jobs () {
    output "[process] starting parsec jobs..."
    parsec=(
        blackscholes
        canneal
        dedup
        ferret
        freqmine
        radix
        vips
    )

    for i in "${parsec[@]}"; do
        kubectl create -f parsec-benchmarks/part3/parsec-"$i".yaml
    done

    for i in "${parsec[@]}"; do
        kubectl wait --timeout=600s --for=condition=complete job/parsec-"$i" >> $log

        output "[status] $i completed"
    done
}

run_memcached () {
    output "[process] creating memcached..."
    kubectl create -f memcache-t1-cpuset.yaml
    kubectl expose pod some-memcached --name some-memcached-11211  --type LoadBalancer --port 11211 --protocol TCP
    sleep 60
    kubectl get service some-memcached-11211
}

set_env_variables

if "$create_cluster"; then
    create_cluster
fi

if "$run_memcached"; then
    run_memcached
fi 

if "$install_mcperf"; then
    install_mcperf
fi


parsec_jobs

output "[process] running tests..."
kubectl get pods -o json > results.json
python3 get_time.py results.json

output "[success] all running"