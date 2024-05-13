source "./policies/functions.sh"

# Node a
# - canneal
# - vips

# Node b
# - blackscholes
# - dedup
# - ferret

# Node c
# - freqmine
# - radix

schedule_a () {
    create_and_wait "canneal"
    create_and_wait "vips"
}

schedule_b () {
    create_and_wait "blackscholes"
    create_and_wait "dedup"
    create_and_wait "ferret"
}

schedule_c () {
    create_and_wait "freqmine"
    create_and_wait "radix"
}

nohup schedule_a &
pid_a=$!

nohup schedule_b &
pid_b=$!

nohup schedule_c &
pid_c=$!

wait $pid_a
wait $pid_b
wait $pid_c
