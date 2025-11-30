ARG K3S_TAG="v1.33.1-k3s1"
FROM rancher/k3s:$K3S_TAG AS k3s

FROM nvidia/cuda:13.0.1-base-ubuntu22.04

ARG NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"

RUN apt update && \
    apt upgrade -y && \
    apt -y install gnupg2 curl libnvidia-container-tools=$NVIDIA_CONTAINER_TOOLKIT_VERSION libnvidia-container1=$NVIDIA_CONTAINER_TOOLKIT_VERSION nvidia-container-toolkit=$NVIDIA_CONTAINER_TOOLKIT_VERSION nvidia-container-toolkit-base=$NVIDIA_CONTAINER_TOOLKIT_VERSION && \
    chmod 1777 /tmp && \
    mkdir -p /var/lib/rancher/k3s/agent/etc/containerd && \
    mkdir -p /var/lib/rancher/k3s/server/manifests

COPY --from=k3s /bin /bin
COPY --from=k3s /etc /etc

# Provide custom containerd configuration to configure the nvidia-container-runtime
COPY config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl

VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log

ENV PATH="$PATH:/bin/aux"
ENV CRI_CONFIG_FILE=/var/lib/rancher/k3s/agent/etc/crictl.yaml

ENTRYPOINT ["/bin/k3s"]
CMD ["agent"]