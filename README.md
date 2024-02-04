# Home Media Server

## Requirements
1. Azure CLI
1. Terraform
1. Helm
1. WSL2
1. K3d

## Getting Started
1. Build the cluster image
    ```
    cd .k3d
    docker build --tag k3d-cuda:latest
    ```
1. Create the cluster
    ```
    k3d cluster create --config .k3d/config.yml
    ```
1. Populate the `infrastructure/variables.tfvars` with the variables for terraform 
1. Login with the Azure CLI
    ```
    az login
    ```
1. Set the Azure subscription into which you wish your infratsructure to be created
    ```
    az account set --subscription <subscription-id>
    ```
1. Deploy the infrastructure
    ```
    cd infrastructure
    terraform apply -var-file=variables.tfvars
    ```
1. Create a helm release
    ```
    cd helm
    helm upgrade --install home-media-server . --namespace home-media-server --values values.yaml --values infrastructure.values.yaml
    ```
