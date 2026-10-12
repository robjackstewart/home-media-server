#!/usr/bin/env bash
# Post-boot sanity check. Output goes to the journal: journalctl -u hms-healthcheck
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
rc=0

bad=$(kubectl get pods -n home-media-server --no-headers 2>/dev/null \
      | awk '$3!="Running" && $3!="Completed" {print "  "$1" "$3}')
if [ -n "$bad" ]; then echo "PODS NOT RUNNING:"; echo "$bad"; rc=1
else echo "pods: all running ($(kubectl get pods -n home-media-server --no-headers 2>/dev/null | wc -l))"; fi

# A failed GPU stack leaves every pod Running while transcoding silently drops to
# CPU, so pod status alone would never reveal it.
if nvidia-smi -L >/dev/null 2>&1; then echo "gpu: $(nvidia-smi -L | head -1)"
else echo "GPU: nvidia-smi FAILED - driver or kernel module problem"; rc=1; fi

gpu=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
if [ "$gpu" = "1" ]; then echo "gpu: schedulable (nvidia.com/gpu=1)"
else echo "GPU: node advertises nvidia.com/gpu='$gpu' - device plugin problem"; rc=1; fi

# /srv shares the root filesystem with the OS, so a full library wedges containerd.
use=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [ "$use" -ge 85 ]; then echo "DISK: / is ${use}% full"; rc=1; else echo "disk: / ${use}% used"; fi

[ $rc -eq 0 ] && echo "RESULT: healthy" || echo "RESULT: PROBLEMS FOUND"
exit $rc
