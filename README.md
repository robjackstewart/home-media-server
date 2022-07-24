
# Cluster

## Create
`k3d cluster create --config ./.infrastructure/local/k3d-cluster.yaml`

## Delete
`k3d cluster delete --config ./.infrastructure/local/k3d-cluster.yaml`

# Application

## Run
- `kubectl create namespace home-media-server --dry-run=client -o yaml | kubectl apply -f -`
- `helm install --values values.yaml home-media-server .`

## Teardown
- `helm delete home-media-server`
- `kubectl delete namespace home-media-server`