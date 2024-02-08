FROM ubuntu:22.04

RUN apt update --fix-missing \
    && apt upgrade -y

RUN apt install -y \
    curl \
    gnupg \
    software-properties-common \
    wget \
    apt-transport-https

# Azure CLI

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN az upgrade

# K3d

RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Terraform

RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

RUN gpg --no-default-keyring \
    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    --fingerprint

RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list

RUN apt update \
    && apt install -y terraform

# Helm

RUN curl https://baltocdn.com/helm/signing.asc | \
    gpg --dearmor | \
    tee /usr/share/keyrings/helm.gpg > /dev/null

RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | \
    tee /etc/apt/sources.list.d/helm-stable-debian.list

RUN apt update && \
    apt-get install -y helm
