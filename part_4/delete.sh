echo "[process] setting variables..."
export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-bucherjo/
PROJECT='gcloud config get-value project'

kops delete cluster --name part4.k8s.local --yes

