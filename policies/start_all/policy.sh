source "functions.sh"

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
    create_job $i
done

for i in "${parsec[@]}"; do
    wait_for_job $i

    output "[status] $i completed"
done