echo "[process] setting variables..."
export KOPS_STATE_STORE=gs://cca-eth-2024-group-022-bucherjo/
PROJECT='gcloud config get-value project'


echo "[process] logging in user..."
gcloud auth application-default login

kops delete cluster --name part3.k8s.local --yes

