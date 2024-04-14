login=false
create_cluster=false
install_mcperf=false
log="log.txt"

output () {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo "${RED}$1${NC}"
}

compute_remote () {
    gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@$1 --zone europe-west3-a -- "$2" >> $log
}

set_env_variables () {
    output "[process] setting variables..."
    export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-bucherjo/
    PROJECT='gcloud config get-value project'
}

login_user () {
    output "[process] logging in user..."
    gcloud auth application-default login
}

create_cluster () {
    output "[process] creating part3..."
    kops create -f part3.yaml >> $log

    output "[process] updating cluster..."
    kops update cluster --name part3.k8s.local --yes --admin >> $log

    output "[process] validating cluster..."
    kops validate cluster --wait 10m >> $log

    kubectl get nodes -o wide
}

install_mcperf () {
    # install modified version of mcperf on client-agent-a and client-agent-b
    output "[process] install mcperf..."
    # for nodetype in "client-agent-a" "client-agent-b" "client-measure"; do
    for nodetype in "client-agent-a"; do

        machine=$(kubectl get nodes -l cca-project-nodetype=$nodetype -o=jsonpath='{.items[*].metadata.name}')

        output "[process] install mcperf on" $machine "..."

        compute_remote $machine "sudo sh -c 'echo deb-src http://europe-west3.gce.archive.ubuntu.com/ubuntu/ jammy main restricted >> /etc/apt/sources.list'"
        compute_remote $machine "sudo apt-get update"
        compute_remote $machine "sudo apt-get install libevent-dev libzmq3-dev git make g++ --yes"
        compute_remote $machine "sudo apt-get build-dep memcached --yes"
        compute_remote $machine "git clone https://github.com/eth-easl/memcache-perf-dynamic.git"
        compute_remote $machine "cd memcache-perf-dynamic"
        compute_remote $machine "make"

        if [[ $variable == "client-agent-a" ]]; then
            compute_remote $machine "./mcperf -T 2 -A"
        fi

        if [[ $variable == "client-agent-b" ]]; then
            compute_remote $machine "./mcperf -T 4 -A"
        fi

        if [[ $variable == "client-measure" ]]; then
            compute_remote $machine "./mcperf -s MEMCACHED_IP --loadonly"
            compute_remote $machine "./mcperf -s MEMCACHED_IP -a INTERNAL_AGENT_A_IP -a INTERNAL_AGENT_B_IP  --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5"
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
        kubectl create -f parsec-benchmarks/part2a/parsec-"$i".yaml
    done

    for i in "${parsec[@]}"; do
        kubectl wait --timeout=600s --for=condition=complete job/parsec-"$i" >> $log

        out=$(kubectl logs $(kubectl get pods --selector=job-name="$i" --output=jsonpath='{.items[*].metadata.name}'))
        
        echo "[$i, $inter]" >> "output.txt"
        echo $out >> "output.txt"
    done
}

set_env_variables

if "$login"; then
    login_user
fi

if "$create_cluster"; then
    create_cluster
fi

if "$install_mcperf"; then
    install_mcperf
fi


parsec_jobs

output "[process] running tests..."
kubectl get pods -o json > results.json
python3 get_time.py results.json

output "[success] all running"