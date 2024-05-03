output () {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo "${RED}$1${NC}"
}

wait_for_job () {
    kubectl wait --timeout=600s --for=condition=complete job/parsec-"$1"
}

create_job () {
    kubectl create -f parsec-benchmarks/part3/parsec-"$1".yaml
}

create_and_wait () {
    output "[status] creating $1..."
    create_job $1
    wait_for_job $1
    output "[status] completed $1"
}