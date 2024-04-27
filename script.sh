# DONT FORGET TO CHANGE YAML NETHZ USER
# Login user using 'gcloud auth application-default login'
create_cluster=false
install_mcperf=true
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

        if [[ $variable == "client-agent-a" ]]; then
            compute_remote $machine "./mcperf -T 2 -A"
        fi

        if [[ $variable == "client-agent-b" ]]; then
            compute_remote $machine "./mcperf -T 4 -A"
        fi

        if [[ $variable == "client-measure" ]]; then
            # we run memcache-server on node 3
            memcached_ip=$(kubectl get nodes -l cca-project-nodetype=node-c-8core -o=jsonpath='{.items[*].metadata.internal-ip}')
            a_ip=$(kubectl get nodes -l cca-project-nodetype=node-a-2core -o=jsonpath='{.items[*].metadata.internal-ip}')
            b_ip=$(kubectl get nodes -l cca-project-nodetype=node-b-4core -o=jsonpath='{.items[*].metadata.internal-ip}')

            echo "internal ip of memcache server is $memcached_ip"
            echo "internal ip of memcache server is $a_ip"
            echo "internal ip of memcache server is $b_ip"

            compute_remote $machine "./mcperf -s $memcached_ip --loadonly"
            compute_remote $machine "./mcperf -s $memcached_ip -a $a_ip -a $b_ip  --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5"
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

set_env_variables

if "$create_cluster"; then
    create_cluster
fi

if "$install_mcperf"; then
    install_mcperf
fi
exit

parsec_jobs

output "[process] running tests..."
kubectl get pods -o json > results.json
python3 get_time.py results.json

output "[success] all running"