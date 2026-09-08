# Home Media Server — Improvement Roadmap

## Current State Summary

A K3d-based home media server running on a single node with NVIDIA GPU. Services:
- **Media**: Jellyfin (GPU-accelerated), Sonarr, Radarr, Bazarr, Prowlarr, Transmission+Gluetun (Mullvad WireGuard VPN), Seerr (media request portal)
- **Automation**: Home Assistant
- **Household**: BabyBuddy (childcare tracking), Gramps Web (genealogy, with a Celery worker + Valkey broker)
- **Dashboard**: Heimdall
- **Ingress**: Tailscale Kubernetes operator, each app its own `Ingress` behind a shared `ProxyGroup`, reachable only over the tailnet at `https://<subdomain>.<tailnet>.ts.net`
- **Auth**: tailnet membership (`tailscale_acl`) - no separate auth layer; nothing is publicly reachable
- **Secrets**: Azure Key Vault → Kubernetes Secrets (injected via Terraform)
- **Infra**: Terraform on Azure (Key Vault) and Tailscale (ACL policy, OAuth-driven operator)

---

## 🔴 HIGH PRIORITY — Security

### SEC-1: Add Resource Requests/Limits to All Pods
**Requirement:** Scheduler efficiency, OOM prevention
- **Current State:** Many containers have no resource requests or limits at all. Jellyfin, Transmission, Gluetun, and Flaresolverr have neither. Sonarr, Radarr, Home Assistant have memory limits but no CPU limits or requests. `metrics-server` is already installed and `kubectl top pods` is live — a spot check showed `radarr-0` and `sonarr-0` both over 700m CPU with no limit set, so this is a present risk, not just theoretical.
- **Improvement:** Add `resources.requests` and `resources.limits` for every container.
- **Note:** OPS-5's prerequisite (metrics-server) is already satisfied, so this no longer needs to wait — just needs a representative observation window before picking numbers.

### SEC-2: Add Pod Security Contexts
**Requirement:** Least-privilege container execution
- **Current State:** No pod or container security contexts defined; all containers likely run as root.
- **Improvement:** Add `securityContext` to every container:
  - `runAsNonRoot: true` / `runAsUser: 1000` (linuxserver images honour PUID/PGID)
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true` where feasible
  - Drop `ALL` capabilities; re-add only what is needed (e.g. `NET_ADMIN` for Gluetun)
- **Caveat:** Most linuxserver images need to start as root so their s6-overlay init can `chown` the config volume before dropping to the `abc` user internally. Setting `runAsNonRoot: true` on the standard tags will likely prevent them from starting at all — needs per-image testing, not a blanket rollout, unless switching to their dedicated rootless variants where available.

### SEC-3: Enable Azure Key Vault Purge Protection
**Requirement:** Secret durability
- **Current State:** `purge_protection_enabled = false`, `soft_delete_retention_days = 7`. Accidental deletion of the vault means permanent secret loss.
- **Improvement:** Set `purge_protection_enabled = true`; increase `soft_delete_retention_days` to 90.
- **Caveat:** `purge_protection_enabled` is one-way on Azure — it cannot be turned back off once set on a vault.

### SEC-7: Cloudflare Access Break-Glass Plan ✅ OBSOLETED
**Requirement:** Recovery path if the auth layer itself misconfigures
- **Previous State:** A single wildcard `cloudflare_zero_trust_access_application` (`*.robjackstewart.com`) gated every app except Home Assistant's explicit bypass, with no documented recovery path if that policy, the Entra group, or the IdP config broke and locked everyone out.
- **Resolution:** The whole Cloudflare Access/Entra ID layer was removed in favour of Tailscale (see the "Ingress"/"Auth" lines above). The equivalent break-glass concern now is the tailnet ACL (`tailscale_acl` in `infrastructure/main.tf`) - it's managed by Terraform from a file in this repo, editable and re-appliable independently of the cluster, and the Tailscale admin console remains reachable to fix it directly if a bad ACL ever locks out a device.

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
- **Caveat:** Falco's eBPF/kernel-module runtime detection frequently has trouble in nested virtualization — exactly this setup (WSL2 → Docker → K3d). Worth a spike before committing to it specifically; Trivy and Polaris don't have this problem.

---

## 🟠 MEDIUM PRIORITY — Reliability

### REL-1: Add Missing Health Probes
**Requirement:** Kubernetes self-healing
- **Current State:** Incomplete probe coverage across the cluster:
  - **Home Assistant**: no liveness, readiness, or startup probes
  - **Gluetun**: no probes at all
  - **Flaresolverr**: no probes
  - **Bazarr**: startup probe only, no liveness or readiness
- **Improvement:** Add appropriate startup, liveness, and readiness probes for each, using the existing port-9999 Gluetun health endpoint for its `livenessProbe`/`readinessProbe`.
- **Note:** The `transmission-monitor` sidecar this item used to reference was removed in `e2f8f40` ("remove transmission monitor") — it actively polled that same health endpoint and called `transmission-remote --torrent all --stop` when the VPN went down, which no longer happens. The only remaining protection against a torrent leaking outside the tunnel is Gluetun's own iptables kill-switch (`FIREWALL=on` by default, not overridden in `values.yaml`), which blocks the traffic at the network layer but won't stop Transmission from queuing/retrying against a dead tunnel. Worth deciding deliberately whether the kill-switch alone is sufficient or whether the monitor's stop-on-unhealthy behavior should be recreated as part of this item.

### REL-2: Consistent CPU Limits and Requests
**Requirement:** Resource fairness, OOM prevention
- **Current State:** Sonarr, Radarr, Home Assistant have memory limits but no CPU limits or requests. Jellyfin has no resource constraints aside from the GPU allocation.
- **Improvement:** Add CPU `requests` (required for scheduler) and `limits` (to prevent noisy-neighbour issues) to all services.
- **Note:** Depends on OPS-5 for informed values.

### REL-3: Velero Backup Strategy
**Requirement:** Data protection & disaster recovery
- **Current State:** No backup or restore strategy. All application state lives in host-path PVCs (5 Gi config, 500 Gi media).
- **Improvement:** Deploy Velero with an Azure Blob Storage backend. Schedule daily backups of config PVCs with 30-day retention. Document and test restore procedures.
- **Caveat:** This carries an ongoing Azure Blob Storage cost (storage + egress for restores), not just engineering effort — size the expected config-volume backup footprint before committing to a retention window.

### REL-4: Horizontal Pod Autoscaling (HPA)
**Requirement:** Automatic scaling under load
- **Current State:** All services run a single static replica.
- **Improvement:** Add HPA for services where scaling is meaningful — Prowlarr and Flaresolverr based on request rate, Jellyfin based on concurrent streams (custom metrics).

### REL-5: Multi-Node Cluster Support
**Requirement:** High availability, load distribution
- **Current State:** Single-node K3d cluster — any node maintenance takes everything down.
- **Improvement:** Expand to a multi-node K3d/K3s cluster. Add worker nodes, configure node selectors and GPU tolerations, add anti-affinity rules to spread critical services.
- **Caveat:** This isn't a config-only change — there's one physical host with the GPU today. Multi-node requires provisioning additional physical or virtual hosts first.

---

## 🟡 MEDIUM PRIORITY — Observability

### OBS-1: Prometheus + Grafana + AlertManager
**Requirement:** Metrics, dashboards, alerting
- **Current State:** No metrics collection, no dashboards, no alerting.
- **Improvement:** Deploy `kube-prometheus-stack` as an additional Helm release.
  - Scrape all pods via annotations and node-exporter
  - Pre-built community dashboards exist for Kubernetes and Jellyfin
  - Alerts: disk usage thresholds, pod crash loops, VPN health, GPU utilisation
- **Caveat:** Real memory overhead (likely 500Mi–1Gi+ for Prometheus+Grafana+AlertManager+node-exporter combined) on the same single node that's also doing GPU transcoding. Worth sizing/testing before committing, not assumed free.

### OBS-2: Loki + Promtail for Log Aggregation
**Requirement:** Centralised log retention and search
- **Current State:** Logs accessible only via `kubectl logs`; no historical retention.
- **Improvement:** Deploy Loki + Promtail (or Grafana Alloy). Surface logs in the same Grafana instance as OBS-1 with log-based alert rules.
- **Caveat:** Same resource-overhead consideration as OBS-1 — this is additive on top of it, not free.

### OBS-3: ServiceMonitor for Cloudflared ✅ OBSOLETED
**Requirement:** Tunnel health visibility
- **Previous State:** Cloudflared exposed Prometheus metrics on port 2000 but nothing scraped them.
- **Resolution:** Cloudflared is gone; there's no tunnel left to monitor. The tailscale-operator and its proxy pods expose their own metrics if this is revisited - see the operator's `--metrics-address` flag - but nothing scrapes those either today, so a fresh version of this item could be opened once OBS-1 lands.

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
- **Current State:** Renovate's built-in `helm-values` manager already tracks the `registry`/`repository`/`tag` triple in `helm/values.yaml` for anything on a real semver tag — confirmed by merged PRs bumping radarr, sonarr, and prowlarr. It cannot track the five images still pinned to `latest` (`gluetun`, `transmission`, `flaresolverr`, `payment-manager`, plus the dead `calibre` block), since there's no version to diff a floating tag against. `renovate.json` has no custom managers left since the `GATEWAY_API_VERSION` one it used to carry was removed along with Gateway API/nginx-gateway-fabric.
- **Improvement:** This is really a side effect of **SEC-5** — once those five images are pinned to real tags, Renovate picks them up automatically. No new regex/custom manager is needed.

### OPS-4: Azure Resource Locks
**Requirement:** Accidental-deletion protection
- **Current State:** No resource locks on the Key Vault or Terraform state storage account.
- **Improvement:** Add `azurerm_management_lock` (CanNotDelete) in Terraform for the Key Vault and the `robstewarttfstate` storage account.

### OPS-5: Resource Usage Profiling (Prerequisite for SEC-1 / REL-2)
**Requirement:** Evidence-based resource constraints
- **Current State:** `metrics-server` is already deployed and functional — `kubectl top pods -n home-media-server` works today. This item is no longer blocking SEC-1/REL-2; what's left is just observing over a representative period.
- **Improvement:** Run `kubectl top pods -n home-media-server` over a representative period (covering a typical download + transcoding session). Deploy VPA in recommendation-only mode to surface suggested request/limit values per container before hardcoding them.

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

### OPS-8: Validate the Helm Chart in CI
**Requirement:** Catch broken templates before they reach the cluster
- **Current State:** `ci.yml` builds the K3d image and checks Renovate/nginx-gateway-fabric compatibility, but never renders or lints the chart. A syntax error or bad value reference in `helm/templates/` merges silently and only surfaces when `task recreate` runs for real on the self-hosted runner. Confirmed today — every chart change in this session had to be validated manually with `helm template`/`helm lint` since CI wouldn't have caught it.
- **Improvement:** Add a CI step running `helm template . --values values.yaml --values sample.infrastructure.values.yaml` (or a fixture values file) and `helm lint`, failing the build on error. This is a ~10-line addition, not a new dependency — a much smaller and higher-value step than the full `chart-testing`/`helm unittest` scope in QA-1, and should land well before it.

### OPS-9: Detect App-Level Config Drift After Infra Changes
**Requirement:** Catch breakage that lives outside Helm/Terraform entirely
- **Current State:** No item in this roadmap covers it, and none of the proposed CI/GitOps items (OPS-1, OPS-8, QA-1) would catch it, because the drift lives in each app's own persisted state on the config PVC, not in the chart. Confirmed twice in this session after the subdomain migration: Bazarr kept stale `/radarr` and `/sonarr` URLs in its own Radarr/Sonarr integration settings after those apps' `UrlBase` was cleared, and Heimdall's dashboard kept duplicate tile rows pointing at the old path-prefix URLs in its SQLite database — both required a manual `kubectl exec` to find and fix.
- **Improvement:** At minimum, add a checklist step to the "how to change a hostname/route" process reminding to check dependent apps' own settings (Bazarr's Radarr/Sonarr URLs, Heimdall's tiles, Jellyfin's base URL, any `*arr` app that talks to another). A stretch goal would be a small script that greps each app's persisted config for the old hostname/prefix after a routing change and flags matches.

### OPS-10: Track the GPU/CUDA Base Image in Renovate
**Requirement:** Keep the K3d node image's GPU stack current
- **Current State:** `.k3d/Dockerfile` pins `rancher/k3s`, `nvidia/cuda`, and `nvidia-container-toolkit` versions, none of which Renovate tracks — only `helm/values.yaml` images and the Gateway API version are covered.
- **Improvement:** Add these to Renovate the same way SEC-5/OPS-3 cover application images, so GPU driver/toolkit updates arrive as PRs instead of silently going stale.

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

## ⚡ MEDIUM PRIORITY — Performance Management

### PERF-1: Scale-to-Zero for Idle Apps
**Requirement:** Don't run rarely-used apps 24/7 on a single-node box
**Current State:** All services run a static 1 replica permanently, regardless of actual usage. State lives on the shared `config`/`media` PVCs rather than per-pod storage, so scaling a StatefulSet to 0 and back is safe here in a way it wouldn't be with per-pod PVs.
- **Improvement:** Deploy KEDA. Two tiers of ambition:
  - **Near-term, low effort:** cron-based scaling (KEDA's cron scaler, or even a plain `CronJob` running `kubectl scale`) for genuinely low-traffic apps like Bazarr/Prowlarr overnight.
  - **Stretch goal:** true on-demand scaling via `keda-http-add-on`, which wakes a pod on the next incoming request. This needs real re-plumbing of the routing layer — requests would go through KEDA's proxy instead of directly to each app's Service, which today is a plain Gateway API `HTTPRoute` per app (see `helm/templates/*.yaml`).

### PERF-2: Prioritize Jellyfin Under Resource Contention
**Requirement:** Protect the app people are actively watching when the node is under load
- **Current State:** No `PriorityClass` on any pod; no container has `requests == limits` (guaranteed QoS). Under contention, the scheduler/kernel has no signal that Jellyfin matters more than a background Sonarr scan.
- **Improvement:** Give Jellyfin a higher `PriorityClass` and guaranteed QoS (requests == limits) so the scheduler preempts/evicts lower-priority pods before touching it under pressure. This folds directly into SEC-1/REL-2 — set Jellyfin's numbers as part of that same resource-limits pass rather than as a separate effort.
- **Note:** This only reacts once the node is already under real resource pressure — it doesn't know whether anyone is actually watching something right now. See PERF-3 for that.

### PERF-3: Usage-Aware Dynamic Throttling (stretch)
**Requirement:** Actively deprioritize background work while Jellyfin has an active stream, not just react to contention after the fact
- **Current State:** Nothing reacts to "someone hit play" — Sonarr/Radarr/Prowlarr scans and Transmission transfers run at full tilt regardless of concurrent playback.
- **Improvement:** This isn't a stock Kubernetes primitive — it needs a small custom controller/script polling Jellyfin's `/Sessions` API for active playback, and reacting by patching other Deployments' resource limits, pausing Transmission (which already has scheduler/bandwidth-limit support), or similar. Treat as a real build, not a config change — scope it separately once PERF-1/PERF-2 are in place.

---

## 🟢 LOW PRIORITY — New Features

### FEAT-1: Seerr — Media Request Portal ✅ DONE
**Requirement:** Self-service media requests without *arr admin access
- **Previous State:** Users needed direct access to Sonarr/Radarr admin UIs to request media.
- **Improvement:** Deployed [Seerr](https://docs.seerr.dev/) — the merged successor to Jellyseerr/Overseerr — as a StatefulSet, exposed at its own subdomain (`seerr.<zone>`) via `helm/templates/seerr.yaml`, consistent with every other app's per-app-subdomain routing.

### FEAT-2: Unpackerr — Automated Archive Extraction
**Requirement:** Automatic post-download extraction
- **Current State:** `.rar` archives downloaded by Transmission are not extracted, so Sonarr/Radarr cannot import them.
- **Improvement:** Deploy Unpackerr as a standalone Deployment watching the downloads directory. Configure it with Sonarr/Radarr API keys for post-extraction notifications.

### FEAT-3: Local DNS / Split-Horizon DNS ✅ OBSOLETED
**Requirement:** Keep LAN traffic on the LAN
- **Previous State:** `local.home-media-server.robjackstewart.com` resolved to 192.168.50.109 via an external DNS record; LAN traffic unnecessarily transited Cloudflare.
- **Resolution:** Remote access moved to Tailscale, which is peer-to-peer by construction - traffic between two devices on the same LAN stays on the LAN without ever reaching a relay, let alone a third-party proxy. There's no longer an equivalent "everything goes through an external service" record to work around. A Pi-hole/CoreDNS setup for ad-blocking DNS is still a separate, independently worthwhile idea, just no longer tied to this problem.

### FEAT-4: Homepage Dashboard
**Requirement:** Live service stats on the landing page
- **Current State:** Heimdall serves as the dashboard but requires manual link configuration with no live service data.
- **Improvement:** Deploy Homepage (gethomepage.dev) alongside or as a replacement for Heimdall. It has native widget integrations for Sonarr, Radarr, Jellyfin, Home Assistant, Transmission, and Prowlarr — showing download queues, library counts, and now-playing info directly on the dashboard.

### FEAT-5: GPU Time-Slicing / NVIDIA GPU Operator
**Requirement:** Efficient GPU utilisation for multiple workloads
- **Current State:** Basic NVIDIA device plugin; GPU is exclusively allocated to Jellyfin.
- **Improvement:** Deploy the NVIDIA GPU Operator and configure GPU time-slicing so the GPU can be shared across pods when Jellyfin is idle. Add GPU utilisation metrics to Grafana (via DCGM exporter).

### FEAT-6: VPN Integration Enhancement ✅ DONE
**Requirement:** Secure direct access from trusted devices
- **Previous State:** External access was Cloudflare Tunnel only; no direct WireGuard access for trusted clients.
- **Improvement:** Replaced Cloudflare Tunnel with Tailscale (a WireGuard mesh) via the Tailscale Kubernetes operator - see the "Ingress"/"Auth" lines above and the README's "Remote access" section. Every app is reachable directly, peer-to-peer where NAT traversal allows, from any device signed into the tailnet.

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
| 1 | OPS-8 | Validate the Helm chart in CI (`helm template`/`helm lint`) | Operations |
| 2 | SEC-5 | Pin all image tags to specific versions | Security |
| 3 | OPS-3 | Extend Renovate to track all image tags (unlocked by #2) | Operations |
| 4 | REL-1 | Add missing health probes (Gluetun, Home Assistant, Bazarr, Flaresolverr) | Reliability |
| 5 | SEC-1 | Add resource requests/limits to all pods (metrics-server already live) | Security |
| 6 | OPS-5 | Profile resource usage over a representative period (VPA recommend mode) | Operations |
| 7 | REL-2 | Add consistent CPU limits/requests | Reliability |
| 8 | PERF-2 | Prioritize Jellyfin under contention (PriorityClass + guaranteed QoS) | Performance |
| 9 | OPS-9 | Detect app-level config drift after infra changes | Operations |
| 10 | SEC-2 | Add pod security contexts (test per-image first — see caveat) | Security |
| 11 | SEC-3 | Enable Key Vault purge protection (irreversible — see caveat) | Security |
| 12 | OPS-4 | Add Azure resource locks | Operations |
| 13 | SEC-4 | Add NetworkPolicies | Security |
| 14 | PERF-1 | Scale-to-zero for idle apps (KEDA, cron tier first) | Performance |
| 15 | OBS-1 | Deploy kube-prometheus-stack | Observability |
| 16 | OBS-2 | Deploy Loki + Promtail | Observability |
| 17 | REL-3 | Deploy Velero backups (ongoing Azure Blob cost — see caveat) | Reliability |
| 18 | OPS-2 | Azure Key Vault CSI driver | Operations |
| 19 | OPS-1 | GitOps with Flux CD | Operations |
| 20 | SEC-6 | Container vulnerability scanning (Trivy/Polaris; Falco needs a spike) | Security |
| 21 | OPS-6 | Advanced CI/CD pipeline | Operations |
| 22 | OPS-10 | Track GPU/CUDA base image in Renovate | Operations |
| 23 | OBS-4 | Application-level metrics (APM) | Observability |
| 24 | STOR-1 | Storage class tiering | Storage |
| 25 | STOR-2 | PostgreSQL for *arr metadata | Storage |
| 26 | FEAT-2 | Unpackerr auto-extraction | Features |
| 27 | FEAT-4 | Homepage dashboard | Features |
| 28 | FEAT-5 | GPU time-slicing / NVIDIA GPU Operator | Features |
| 29 | OPS-7 | IaC enhancement (K3d + Terraform modules) | Operations |
| 30 | REL-4 | HPA for Prowlarr/Flaresolverr/Jellyfin | Reliability |
| 31 | REL-5 | Multi-node cluster support (needs new hardware — see caveat) | Reliability |
| 32 | FEAT-7 | Service mesh (Linkerd) | Features |
| 33 | OBS-5 | Distributed tracing (Jaeger/Tempo) | Observability |
| 34 | QA-1 | Helm chart automated testing (broader than OPS-8) | Quality |
| 35 | PERF-3 | Usage-aware dynamic throttling (custom build — see note) | Performance |
| 36 | QA-2 | Chaos engineering (Litmus) | Quality |

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
