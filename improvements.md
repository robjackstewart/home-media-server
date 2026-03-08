# Home Media Server — Improvement Roadmap

## Current State Summary

A K3d-based home media server running on a single node with NVIDIA GPU. Services:
- **Media**: Jellyfin (GPU-accelerated), Sonarr, Radarr, Bazarr, Prowlarr, Transmission+Gluetun (Mullvad WireGuard VPN)
- **Automation**: Home Assistant
- **Dashboard**: Heimdall
- **Ingress**: Cloudflared → nginx-gateway-fabric (Gateway API)
- **Auth**: Cloudflare Zero Trust → Azure Entra ID OAuth
- **Secrets**: Azure Key Vault → Kubernetes Secrets (injected via Terraform)
- **Infra**: Terraform on Azure (Key Vault, Cloudflare resources, DNS)

---

## 🔴 HIGH PRIORITY — Security

### SEC-1: Add Resource Requests/Limits to All Pods
**Requirement:** Scheduler efficiency, OOM prevention
- **Current State:** Many containers have no resource requests or limits at all. Jellyfin, Transmission, Gluetun, Flaresolverr, and Cloudflared have neither. Sonarr, Radarr, Home Assistant have memory limits but no CPU limits or requests.
- **Improvement:** Add `resources.requests` and `resources.limits` for every container.
- **Note:** Should be done *after* OPS-5 (resource usage profiling) to avoid setting values that are too tight or too loose.

### SEC-2: Add Pod Security Contexts
**Requirement:** Least-privilege container execution
- **Current State:** No pod or container security contexts defined; all containers likely run as root.
- **Improvement:** Add `securityContext` to every container:
  - `runAsNonRoot: true` / `runAsUser: 1000` (linuxserver images honour PUID/PGID)
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true` where feasible
  - Drop `ALL` capabilities; re-add only what is needed (e.g. `NET_ADMIN` for Gluetun)

### SEC-3: Enable Azure Key Vault Purge Protection
**Requirement:** Secret durability
- **Current State:** `purge_protection_enabled = false`, `soft_delete_retention_days = 7`. Accidental deletion of the vault means permanent secret loss.
- **Improvement:** Set `purge_protection_enabled = true`; increase `soft_delete_retention_days` to 90.

### SEC-4: Add NetworkPolicies
**Requirement:** Network micro-segmentation
- **Current State:** All pods can communicate with all other pods in the namespace.
- **Improvement:** Add a default-deny `NetworkPolicy` for the namespace, then add explicit allow rules per service. Priority targets:
  - Isolate Transmission/Gluetun — only allow VPN egress and internal service communication
  - Restrict Prowlarr/Flaresolverr to relevant internal services only

### SEC-5: Pin All Image Tags to Specific Versions
**Requirement:** Reproducibility, supply-chain security
- **Current State:** Gluetun, Transmission, and Flaresolverr use `latest` — unpredictable upgrades, no auditability.
- **Improvement:** Pin all images to a specific semver tag or digest. Add these images to Renovate so updates arrive as PRs.

### SEC-6: Container Vulnerability Scanning
**Requirement:** Vulnerability management & compliance
- **Current State:** No security scanning in the pipeline.
- **Improvement:** Integrate Trivy into the CI pipeline to scan images on every PR. Optionally add Polaris for Kubernetes best-practices validation and Falco for runtime anomaly detection.

---

## 🟠 MEDIUM PRIORITY — Reliability

### REL-1: Add Missing Health Probes
**Requirement:** Kubernetes self-healing
- **Current State:** Incomplete probe coverage across the cluster:
  - **Home Assistant**: no liveness, readiness, or startup probes
  - **Gluetun**: no probes at all (critical — if the VPN dies, Transmission continues downloading unprotected)
  - **Flaresolverr**: no probes
  - **Bazarr**: startup probe only, no liveness or readiness
- **Improvement:** Add appropriate startup, liveness, and readiness probes for each. For Gluetun, promote the existing port-9999 health endpoint (already used by the transmission-monitor sidecar) to a formal `livenessProbe` and `readinessProbe`.

### REL-2: Consistent CPU Limits and Requests
**Requirement:** Resource fairness, OOM prevention
- **Current State:** Sonarr, Radarr, Home Assistant have memory limits but no CPU limits or requests. Jellyfin has no resource constraints aside from the GPU allocation.
- **Improvement:** Add CPU `requests` (required for scheduler) and `limits` (to prevent noisy-neighbour issues) to all services.
- **Note:** Depends on OPS-5 for informed values.

### REL-3: Velero Backup Strategy
**Requirement:** Data protection & disaster recovery
- **Current State:** No backup or restore strategy. All application state lives in host-path PVCs (5 Gi config, 500 Gi media).
- **Improvement:** Deploy Velero with an Azure Blob Storage backend. Schedule daily backups of config PVCs with 30-day retention. Document and test restore procedures.

### REL-4: Horizontal Pod Autoscaling (HPA)
**Requirement:** Automatic scaling under load
- **Current State:** All services run a single static replica.
- **Improvement:** Add HPA for services where scaling is meaningful — Prowlarr and Flaresolverr based on request rate, Jellyfin based on concurrent streams (custom metrics).

### REL-5: Multi-Node Cluster Support
**Requirement:** High availability, load distribution
- **Current State:** Single-node K3d cluster — any node maintenance takes everything down.
- **Improvement:** Expand to a multi-node K3d/K3s cluster. Add worker nodes, configure node selectors and GPU tolerations, add anti-affinity rules to spread critical services.

---

## 🟡 MEDIUM PRIORITY — Observability

### OBS-1: Prometheus + Grafana + AlertManager
**Requirement:** Metrics, dashboards, alerting
- **Current State:** No metrics collection, no dashboards, no alerting.
- **Improvement:** Deploy `kube-prometheus-stack` as an additional Helm release.
  - Scrape all pods via annotations, nginx-gateway-fabric, node-exporter, and cloudflared (port 2000 already exposes Prometheus metrics)
  - Pre-built community dashboards exist for Kubernetes, NGINX, and Jellyfin
  - Alerts: disk usage thresholds, pod crash loops, VPN health, GPU utilisation

### OBS-2: Loki + Promtail for Log Aggregation
**Requirement:** Centralised log retention and search
- **Current State:** Logs accessible only via `kubectl logs`; no historical retention.
- **Improvement:** Deploy Loki + Promtail (or Grafana Alloy). Surface logs in the same Grafana instance as OBS-1 with log-based alert rules.

### OBS-3: ServiceMonitor for Cloudflared
**Requirement:** Tunnel health visibility
- **Current State:** Cloudflared exposes Prometheus metrics on port 2000 but nothing scrapes them.
- **Improvement:** Add a `ServiceMonitor` CRD targeting the cloudflared service on port 2000. Low effort, high value.

### OBS-4: Application-Level Metrics (APM)
**Requirement:** Media-specific performance insights
- **Current State:** No application-level monitoring.
- **Improvement:** Add Prometheus exporters or enable built-in metric endpoints for Sonarr, Radarr, and Jellyfin. Track download rates, transcoding performance, library scan times, and active stream counts in Grafana.

### OBS-5: Distributed Tracing
**Requirement:** Request-flow debugging across services
- **Current State:** No tracing between services.
- **Improvement:** Deploy Jaeger or Tempo (Grafana stack) to trace request flows, identify latency hotspots, and debug inter-service issues.

---

## 🟡 MEDIUM PRIORITY — Operations

### OPS-1: GitOps with Flux CD
**Requirement:** Declarative deployment, drift detection, audit trail
- **Current State:** Deployments are manual (`task recreate`). No drift detection or audit trail.
- **Improvement:** Deploy Flux CD (lighter than ArgoCD for a single-node cluster) to reconcile the Helm release from Git. Gate changes via PRs; Flux automatically applies approved changes and raises alerts on drift.

### OPS-2: Azure Key Vault CSI Driver for Secret Rotation
**Requirement:** Zero-downtime secret rotation
- **Current State:** Secrets are injected at `terraform apply` time. Rotating a secret (e.g. VPN private key) requires a full apply and pod restart.
- **Improvement:** Install `secrets-store-csi-driver` + `azure-keyvault-provider`. Mount secrets directly from Key Vault at pod runtime, enabling automatic rotation without redeployment.

### OPS-3: Extend Renovate to Track All Image Tags
**Requirement:** Automated dependency updates
- **Current State:** Renovate tracks only Gateway API versions (`helm/Taskfile.yml`) and Helm chart dependencies (`Chart.yaml`). All application image tags in `helm/values.yaml` are untracked.
- **Improvement:** Add `docker` manager rules to `renovate.json` to track linuxserver, home-assistant, cloudflared, and other image versions in `helm/values.yaml`.

### OPS-4: Azure Resource Locks
**Requirement:** Accidental-deletion protection
- **Current State:** No resource locks on the Key Vault or Terraform state storage account.
- **Improvement:** Add `azurerm_management_lock` (CanNotDelete) in Terraform for the Key Vault and the `robstewarttfstate` storage account.

### OPS-5: Resource Usage Profiling (Prerequisite for SEC-1 / REL-2)
**Requirement:** Evidence-based resource constraints
- **Current State:** No metrics server; resource limits/requests cannot be set intelligently without usage data.
- **Improvement:** Deploy `metrics-server` and run `kubectl top pods -n home-media-server` over a representative period (covering a typical download + transcoding session). Deploy VPA in recommendation-only mode to surface suggested request/limit values per container before hardcoding them.

### OPS-6: Advanced CI/CD Pipeline
**Requirement:** Automated testing and security validation
- **Current State:** Basic lint/build tasks in Taskfile.
- **Improvement:** Add a GitHub Actions workflow with:
  - Helm chart linting and manifest validation (kubeval / `helm template | kubectl --dry-run`)
  - Trivy image scanning on PRs
  - Automated rollback on failed Helm upgrade

### OPS-7: Infrastructure as Code Enhancement
**Requirement:** Fully reproducible infrastructure
- **Current State:** Terraform manages cloud resources; K3d setup is semi-manual.
- **Improvement:** Automate K3d cluster provisioning via Terraform (or a dedicated script captured in the Taskfile). Extract reusable Terraform modules. Add remote state locking (already partially in place via Azure Storage).

---

## 💾 MEDIUM PRIORITY — Storage & Data

### STOR-1: Storage Class Tiering
**Requirement:** Performance-optimised storage
- **Current State:** Single `local-storage` host-path class for all volumes.
- **Improvement:** Create separate storage classes for SSD (config, databases) and HDD (bulk media). Add volume snapshot capability for point-in-time recovery.

### STOR-2: Database for Application Metadata
**Requirement:** Reliable, queryable metadata storage
- **Current State:** All *arr services store metadata in SQLite files on the config PVC.
- **Improvement:** Deploy a shared PostgreSQL instance and configure Sonarr, Radarr, Prowlarr, and Bazarr to use it. Add Redis for session caching. Improves performance and simplifies backup (database dump vs. full PVC snapshot).

---

## 🟢 LOW PRIORITY — New Features

### FEAT-1: Jellyseerr — Media Request Portal
**Requirement:** Self-service media requests without *arr admin access
- **Current State:** Users need direct access to Sonarr/Radarr admin UIs to request media.
- **Improvement:** Deploy Jellyseerr (Overseerr fork with Jellyfin integration) as a StatefulSet. Expose via Gateway route `/jellyseerr`.

### FEAT-2: Unpackerr — Automated Archive Extraction
**Requirement:** Automatic post-download extraction
- **Current State:** `.rar` archives downloaded by Transmission are not extracted, so Sonarr/Radarr cannot import them.
- **Improvement:** Deploy Unpackerr as a standalone Deployment watching the downloads directory. Configure it with Sonarr/Radarr API keys for post-extraction notifications.

### FEAT-3: Local DNS / Split-Horizon DNS
**Requirement:** Keep LAN traffic on the LAN
- **Current State:** `local.home-media-server.robjackstewart.com` resolves to 192.168.50.109 via an external DNS record; LAN traffic unnecessarily transits Cloudflare.
- **Improvement:** Deploy Pi-hole or configure CoreDNS with rewrite rules to resolve internal domains locally. This also blocks ads cluster-wide as a side effect.

### FEAT-4: Homepage Dashboard
**Requirement:** Live service stats on the landing page
- **Current State:** Heimdall serves as the dashboard but requires manual link configuration with no live service data.
- **Improvement:** Deploy Homepage (gethomepage.dev) alongside or as a replacement for Heimdall. It has native widget integrations for Sonarr, Radarr, Jellyfin, Home Assistant, Transmission, and Prowlarr — showing download queues, library counts, and now-playing info directly on the dashboard.

### FEAT-5: GPU Time-Slicing / NVIDIA GPU Operator
**Requirement:** Efficient GPU utilisation for multiple workloads
- **Current State:** Basic NVIDIA device plugin; GPU is exclusively allocated to Jellyfin.
- **Improvement:** Deploy the NVIDIA GPU Operator and configure GPU time-slicing so the GPU can be shared across pods when Jellyfin is idle. Add GPU utilisation metrics to Grafana (via DCGM exporter).

### FEAT-6: VPN Integration Enhancement
**Requirement:** Secure direct access from trusted devices
- **Current State:** External access is Cloudflare Tunnel only; no direct WireGuard access for trusted clients.
- **Improvement:** Deploy a WireGuard server in the cluster (e.g. wg-easy) and create a dedicated ingress route. Useful for low-latency access from known devices without traversing Cloudflare.

### FEAT-7: Service Mesh (Linkerd)
**Requirement:** Automatic mTLS, advanced traffic policies, built-in observability
- **Current State:** No service mesh; inter-pod traffic is unencrypted.
- **Improvement:** Deploy Linkerd (lighter than Istio) to add automatic mTLS between all services, golden-signal metrics per route, and circuit-breaker/retry policies.

---

## 🧪 LOW PRIORITY — Quality & Testing

### QA-1: Automated Testing for Helm Charts
**Requirement:** Regression prevention on chart changes
- **Current State:** No automated testing for Helm templates or configuration.
- **Improvement:** Add `helm unittest` for template unit tests. Add `chart-testing` (ct) in CI to lint and validate chart changes on every PR.

### QA-2: Chaos Engineering
**Requirement:** Resilience validation
- **Current State:** No resilience testing.
- **Improvement:** Deploy Litmus or Chaos Mesh to run scheduled pod-kill and network-partition experiments. Use results to drive improvements in health probes, restart policies, and backup procedures.

---

## 📋 Implementation Priority Order

| # | ID | Title | Category |
|---|-----|-------|----------|
| 1 | SEC-5 | Pin all image tags to specific versions | Security |
| 2 | OPS-5 | Profile resource usage (metrics-server + VPA recommend mode) | Operations |
| 3 | REL-1 | Add missing health probes (Gluetun, Home Assistant, Bazarr, Flaresolverr) | Reliability |
| 4 | OPS-3 | Extend Renovate to track all image tags | Operations |
| 5 | SEC-1 | Add resource requests/limits to all pods | Security |
| 6 | REL-2 | Add consistent CPU limits/requests | Reliability |
| 7 | SEC-2 | Add pod security contexts | Security |
| 8 | OBS-3 | Add ServiceMonitor for cloudflared metrics | Observability |
| 9 | OBS-1 | Deploy kube-prometheus-stack | Observability |
| 10 | OBS-2 | Deploy Loki + Promtail | Observability |
| 11 | SEC-3 | Enable Key Vault purge protection | Security |
| 12 | OPS-4 | Add Azure resource locks | Operations |
| 13 | SEC-4 | Add NetworkPolicies | Security |
| 14 | REL-3 | Deploy Velero backups | Reliability |
| 15 | OPS-2 | Azure Key Vault CSI driver | Operations |
| 16 | OPS-1 | GitOps with Flux CD | Operations |
| 17 | SEC-6 | Container vulnerability scanning (Trivy/Polaris) | Security |
| 18 | OPS-6 | Advanced CI/CD pipeline | Operations |
| 19 | OBS-4 | Application-level metrics (APM) | Observability |
| 20 | STOR-1 | Storage class tiering | Storage |
| 21 | STOR-2 | PostgreSQL for *arr metadata | Storage |
| 22 | FEAT-1 | Jellyseerr media request portal | Features |
| 23 | FEAT-2 | Unpackerr auto-extraction | Features |
| 24 | FEAT-3 | Local DNS / split-horizon DNS | Features |
| 25 | FEAT-4 | Homepage dashboard | Features |
| 26 | FEAT-5 | GPU time-slicing / NVIDIA GPU Operator | Features |
| 27 | OPS-7 | IaC enhancement (K3d + Terraform modules) | Operations |
| 28 | REL-4 | HPA for Prowlarr/Flaresolverr/Jellyfin | Reliability |
| 29 | FEAT-6 | WireGuard direct access | Features |
| 30 | REL-5 | Multi-node cluster support | Reliability |
| 31 | FEAT-7 | Service mesh (Linkerd) | Features |
| 32 | OBS-5 | Distributed tracing (Jaeger/Tempo) | Observability |
| 33 | QA-1 | Helm chart automated testing | Quality |
| 34 | QA-2 | Chaos engineering (Litmus) | Quality |

---

## 🎯 Success Metrics

### Security
- Zero critical vulnerabilities in container images
- 100% of inter-service traffic encrypted (mTLS via service mesh)
- Mean Time to Patch (MTTP) < 24 hours
- No containers running as root

### Reliability
- 99.9% uptime for core services (Jellyfin, Home Assistant)
- Mean Time to Recovery (MTTR) < 15 minutes
- Successful disaster recovery restore tested monthly

### Performance
- Media streaming startup time < 5 seconds
- Download completion rate > 95%
- GPU utilisation > 80% during peak transcoding

### Operations
- All image updates arrive as automated Renovate PRs
- Deployment time < 5 minutes end-to-end
- Zero-downtime Helm upgrades
- Full cluster state recoverable from Git + backup in < 30 minutes
