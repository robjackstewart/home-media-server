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

## WSL2
If you are running the K3d cluster and docker in WSL2, then you will need to forward the ports on your windows host into the WSL2 ports.

1. Give your WSL2 instance a static IP
    1. Get your WSL2 IP address `hostname -I` and take the first IP address if there are multiple. You can check its right by running `ip addr show eth0` and taking the `inet` value.
    1. Get your current gateway by running `ip route`. It follows `default via`.
    1. Edit the networm interfaces config: `sudo nano /etc/network/interfaces` adding the following content:
        ``` bash
        auto eth0
        iface eth0 inet static
            address <your-static-ip>
            netmask 255.255.255.0
            gateway <your-gateway-ip>
        ```
    1. On your windows host, run `wsl --shutdown`.
    1. Open a new WSL2 tab to restart WSL.
1. Forward ports on your windows host to your WSL2 instance but opening powershell on your windows host and running the following:
    ``` powershell

    $wslIP=$(wsl hostname -I).Split(' ')[0]

    netsh interface portproxy delete v4tov4 listenport=8096 
    netsh interface portproxy delete v4tov4 listenport=8920 
    netsh interface portproxy delete v4tov4 listenport=7359 
    netsh interface portproxy delete v4tov4 listenport=1900

    Remove-NetFirewallRule -DisplayName "Open Jellyfin Port *"

    netsh interface portproxy add v4tov4 listenport=8096 connectport=8096 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=8920 connectport=8920 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=7359 connectport=7359 connectaddress=$wslIP
    netsh interface portproxy add v4tov4 listenport=1900 connectport=1900 connectaddress=$wslIP

    netsh advfirewall firewall add rule name="Open Jellyfin Port 8096" dir=in action=allow protocol=TCP localport=8096
    netsh advfirewall firewall add rule name="Open Jellyfin Port 8920" dir=in action=allow protocol=TCP localport=8920
    netsh advfirewall firewall add rule name="Open Jellyfin Port 7359" dir=in action=allow protocol=UDP localport=7359
    netsh advfirewall firewall add rule name="Open Jellyfin Port 1900" dir=in action=allow protocol=UDP localport=1900
    ```
