# Home Media Server

## Requirements
1. Azure CLI
1. Terraform
1. Helm
1. Docker Desktop
1. WSL2

## Kubernetes GPU Support for Docker Desktop + WSL 2
1. Install `nvidia-container-toolkit` 
1. Add the following to your docker desktop config:
    ```
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
        "path": "/usr/bin/nvidia-container-runtime",
        "runtimeArgs": []
        }
    }
    ```
1. Reset your cluster
1. Label your node as follows:
    ``` shell
    kubectl label node docker-desktop nvidia.com/gpu.present=true
    ```
