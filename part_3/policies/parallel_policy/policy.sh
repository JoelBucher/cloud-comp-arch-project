source "./policies/functions.sh"

jobs_a=(
    blackscholes
)

jobs_b=(
    vips
    dedup
    canneal
    radix
)

jobs_c=(
    ferret
    freqmine
)

node-a() {
   for i in "${jobs_a[@]}"; do
    create_job $i
    wait_for_job $i
    output "[status] $i completed"
    done
}

# Function to perform Task 2
node-b() {
    #create_job "radix"
    for i in "${jobs_b[@]}"; do
    create_job $i
    wait_for_job $i
    output "[status] $i completed"
    done
}

# Function to perform Task 3
node-c() {
    for i in "${jobs_c[@]}"; do
    create_job $i
    wait_for_job $i
    output "[status] $i completed"
    done
}

node-c & node-a & node-b 
