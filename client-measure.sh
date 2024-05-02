
client_measure_name=$(kubectl get nodes -l cca-project-nodetype=client-measure -o=jsonpath='{.items[*].metadata.name}')

client_measure_ip=$(kubectl get nodes $client_measure_name -o=jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
echo "client measure ip $client_measure_ip"

ssh -i ~/.ssh/cloud-computing ubuntu@$client_measure_ip

