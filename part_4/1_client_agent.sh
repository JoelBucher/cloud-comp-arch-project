# This file is automatically generated
echo "[process] starting client-agent..."
gcloud compute ssh --ssh-key-file ~/.ssh/cloud-computing ubuntu@client-agent-9vfc --zone europe-west3-a -- "cd memcache-perf-dynamic && ./mcperf -T 16 -A"
