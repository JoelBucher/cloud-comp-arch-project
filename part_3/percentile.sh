
client_measure_name=$(kubectl get nodes -l cca-project-nodetype=client-measure -o=jsonpath='{.items[*].metadata.name}')
a_name=$(kubectl get nodes -l cca-project-nodetype=client-agent-a -o=jsonpath='{.items[*].metadata.name}')
b_name=$(kubectl get nodes -l cca-project-nodetype=client-agent-b -o=jsonpath='{.items[*].metadata.name}')


client_measure_ip=$(kubectl get nodes $client_measure_name -o=jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
memcached_ip= $(kubectl get pods some-memcached -o=jsonpath='{.status.podIP}')
a_ip=$(kubectl get nodes $a_name -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
b_ip=$(kubectl get nodes $b_name -o=jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo "client measure ip $client_measure_ip"
# echo "memcached ip $memcached_ip"
echo "Agent A ip $a_ip"
echo "Agent B ip $b_ip"

echo "cd memcache-perf-dynamic && ./mcperf -s $memcached_ip -a $a_ip -a $b_ip --noload -T 6 -C 4 -D 4 -Q 1000 -c 4 -t 10 --scan 30000:30500:5"


ssh -i ~/.ssh/cloud-computing ubuntu@$client_measure_ip

