#!/usr/bin/env bash
# Checks that this host's NVIDIA kernel module is built for the kernel(s) it will actually run.
# Read-only: it inspects packages, module metadata and device nodes, and installs nothing.
#
# Why this exists: the host's HWE kernel and its NVIDIA driver are upgraded independently by
# unattended-upgrades, and a kernel can be installed (and, after the nightly reboot, booted) while
# the matching "restricted" modules package - linux-modules-nvidia-<major>-<kernel> - is not. The
# kernel then has no nvidia.ko to load, NVML reports "Driver Not Loaded",
# nvidia-container-toolkit fails to generate a CDI spec at container creation, the device plugin
# crash-loops with RunContainerError, the node advertises nvidia.com/gpu: 0, and Jellyfin sits
# Pending on "Insufficient nvidia.com/gpu". That is exactly the 7.0.0-34 kernel vs 7.0.0-31
# modules mismatch this script was written to catch before the reboot makes it live.
#
# Run on the host via `task k3s:gpu:compat:check`, or as part of `task k3s:environment:check`.
# Exits non-zero and names the package to install when something is incompatible.
set -euo pipefail

fail=0

for cmd in dpkg-query modinfo linux-version; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "nvidia-compat: FAIL - required command '$cmd' not found" >&2
    exit 1
  fi
done

# The installed metapackage (nvidia-driver-580, ...) is the source of truth for the driver major
# version, since every other userspace package is versioned off it. No match is non-zero from
# dpkg-query, hence the `|| true` on the whole pipeline.
driver_major=$(dpkg-query -W -f='${Package}\n' 'nvidia-driver-*' 2>/dev/null \
  | sed -n 's/^nvidia-driver-\([0-9][0-9]*\)$/\1/p' \
  | sort -n | tail -n1 || true)

if [ -z "$driver_major" ]; then
  echo "nvidia-compat: FAIL - no nvidia-driver-<major> metapackage is installed" >&2
  exit 1
fi

running_kernel=$(uname -r)
# GRUB_DEFAULT=0 boots the newest menu entry, and Ubuntu's grub generator orders entries
# newest-first - so the newest installed kernel is the one the next reboot will land on. That is
# the kernel that must have modules, not only the one currently running.
boot_kernel=$(linux-version list | linux-version sort | tail -n1)

check_kernel_has_module() {
  local kernel=$1 label=$2 pkg version
  pkg="linux-modules-nvidia-${driver_major}-${kernel}"

  # `modinfo -k <kernel>` reads /lib/modules/<kernel> directly; an assignment-in-if keeps a
  # non-zero exit from tripping `set -e` so the "missing" branch can report it instead.
  if version=$(modinfo -k "$kernel" -F version nvidia 2>/dev/null) && [ -n "$version" ]; then
    echo "nvidia-compat: OK - $label kernel $kernel has nvidia.ko (module version $version)"
    return 0
  fi

  echo "nvidia-compat: FAIL - $label kernel $kernel has no nvidia.ko; install '$pkg'" >&2
  return 1
}

check_kernel_has_module "$running_kernel" running || fail=1
if [ "$boot_kernel" != "$running_kernel" ]; then
  check_kernel_has_module "$boot_kernel" next-boot || fail=1
fi

# The module can be present on disk for the running kernel yet not actually loaded - the state
# this incident was found in. /sys/module/nvidia/version only exists once the module is live.
loaded_version=$(cat /sys/module/nvidia/version 2>/dev/null || true)

if [ -n "$loaded_version" ]; then
  echo "nvidia-compat: OK - nvidia module is loaded for running kernel $running_kernel (version $loaded_version)"

  disk_version=$(modinfo -k "$running_kernel" -F version nvidia 2>/dev/null || true)
  if [ -n "$disk_version" ] && [ "$disk_version" != "$loaded_version" ]; then
    echo "nvidia-compat: WARN - loaded module $loaded_version differs from on-disk $disk_version;" \
      "a reboot (or unload/reload) is needed to pick up the installed driver" >&2
  fi

  # Kernel module and userspace libraries are shipped as a matched pair within a driver major; a
  # minor mismatch means a partial driver upgrade landed and is worth surfacing before it bites.
  userspace_version=$(dpkg-query -W -f='${Version}' "libnvidia-compute-${driver_major}" 2>/dev/null || true)
  if [ -n "$userspace_version" ] && [ "${userspace_version%%-*}" != "$loaded_version" ]; then
    echo "nvidia-compat: WARN - module $loaded_version differs from libnvidia-compute-${driver_major}" \
      "${userspace_version}; driver upgrade may be half-applied" >&2
  fi
else
  echo "nvidia-compat: FAIL - nvidia module is not loaded for running kernel $running_kernel;" \
    "NVML reports 'Driver Not Loaded', so the device plugin cannot start" >&2
  fail=1
fi

# The device plugin and GPU workloads resolve these through NVML; a missing uvm in particular
# breaks CUDA/Jellyfin transcoding.
missing_nodes=0
for node in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-uvm; do
  if [ ! -e "$node" ]; then
    echo "nvidia-compat: FAIL - $node is missing" >&2
    missing_nodes=1
  fi
done
if [ "$missing_nodes" -eq 0 ]; then
  echo "nvidia-compat: OK - /dev/nvidiactl, /dev/nvidia0, /dev/nvidia-uvm present"
else
  fail=1
fi

exit "$fail"
