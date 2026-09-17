# Home Media Server — Improvement Roadmap

## Current State Summary

A native k3s single-node cluster (installed as a systemd service, configured declaratively from
`k3s/config.yaml` — see `k3s/Taskfile.yml`) on a host with an NVIDIA GPU. Services:
- **Media**: Jellyfin (GPU-accelerated), Sonarr, Radarr, Bazarr, Prowlarr, Transmission+Gluetun (Mullvad WireGuard VPN), Seerr (media request portal)
- **Books & comics**: Bookshelf (ebook downloader, a maintained Readarr fork, backed by a self-hosted rreading-glasses + Postgres metadata service for its own Hardcover API quota), Mylar3 (comic downloader), Kavita (reader + Send-to-Kindle, the only reader in this stack) - all synced to Prowlarr/Transmission the same way as Sonarr/Radarr
- **Automation**: Home Assistant
- **Household**: BabyBuddy (childcare tracking), Gramps Web (genealogy, with a Celery worker + Valkey broker)
- **Dashboard**: Heimdall
- **Ingress**: Tailscale Kubernetes operator, each app its own `Ingress` behind a shared `ProxyGroup`, reachable only over the tailnet at `https://<subdomain>.<tailnet>.ts.net`
- **Auth**: tailnet membership (`tailscale_acl`) - no separate auth layer; nothing is publicly reachable
- **Secrets**: Azure Key Vault → Kubernetes Secrets (injected via Terraform)
- **Infra**: Terraform on Azure (Key Vault) and Tailscale (ACL policy, OAuth-driven operator)
- **Deployment**: GitOps via Flux (running as the Azure Arc `microsoft.flux` extension), reconciling from a commit Terraform pins on every push to `main` via a GitHub-hosted Actions runner authenticated over OIDC - no self-hosted runner, no stored Azure credential in GitHub, no Kubernetes access from CI at all (see **SEC-8**, **OPS-1** - merged but not yet verified live)

---

## 🔴 HIGH PRIORITY — Security

### SEC-8: Self-Hosted Runner Is Reachable From Any Approved Contributor 🚧 IN PROGRESS
**Requirement:** Stop a public repo's CI from being a path to cluster-admin on the home host
- **Current State:** ⚠️ **Revised** — `deploy.yml` (`.github/workflows/deploy.yml`) no longer references `runs-on: self-hosted` at all: it runs on `ubuntu-24.04` and authenticates to Azure directly via GitHub OIDC (`infrastructure/ci.tf`'s federated identity), with no stored Azure credential in GitHub and no Kubernetes access of any kind (Flux, not this workflow, deploys the chart - see **OPS-1**). The repo's fork-PR approval setting is still only `first_time_contributors`, and no `permissions:`/SHA-pinning audit has happened yet on `ci.yml`, so those two remain open. The runner registered on the home host is now unused by any workflow but has **not yet been unregistered** - do that once the new pipeline is confirmed working (`gh api repos/{owner}/{repo}/actions/runners` should return empty after), then remove its systemd service from the host.
- **Improvement:** Tighten fork-PR approval to require review for all outside collaborators, not just first-timers. Add `permissions: contents: read` to `ci.yml` (`deploy.yml` already has it). Pin third-party Actions to commit SHAs rather than floating tags, across both workflows. Unregister the now-unused self-hosted runner.
- **Caveat:** The remaining fork-PR-approval and SHA-pinning gaps are lower severity now that no workflow can reach the host at all - the worst a malicious PR can do today is waste GitHub-hosted runner minutes or attempt a `terraform plan` (read-only; `apply` only runs on `push` to `main`, which forks can't trigger).

### SEC-1: Add Resource Requests/Limits to All Pods
**Requirement:** Scheduler efficiency, OOM prevention, and noisy-neighbour protection
- **Current State:** Many containers have no resource requests or limits at all — Jellyfin, Transmission and Gluetun have neither. Others (Sonarr, Radarr, Home Assistant) have a memory `limit` but no CPU `limit` or any `requests` at all, which matters for two reasons: `requests` are what the scheduler uses to place pods, and without `limits` on every container a single misbehaving process can starve its neighbours on this single-node box. `metrics-server` is deployed and `kubectl top pods` is live, so this can be sized with real data rather than guesswork.
- **Improvement:** Add both `resources.requests` and `resources.limits` for every container, sized from an observation window (see **OPS-5**).
- **Note:** Supersedes the old REL-2 item, which duplicated this one (CPU-only). OPS-5's prerequisite (metrics-server) is already satisfied.

### SEC-2: Add Pod Security Contexts
**Requirement:** Least-privilege container execution
- **Current State:** No pod or container security contexts defined; all containers likely run as root.
- **Improvement:** Add `securityContext` to every container:
  - `runAsNonRoot: true` / `runAsUser: 1000` (linuxserver images honour PUID/PGID)
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true` where feasible
  - Drop `ALL` capabilities; re-add only what is needed (e.g. `NET_ADMIN` for Gluetun)
- **Caveat:** Most linuxserver images need to start as root so their s6-overlay init can `chown` the config volume before dropping to the `abc` user internally. Setting `runAsNonRoot: true` on the standard tags will likely prevent them from starting at all — needs per-image testing, not a blanket rollout, unless switching to their dedicated rootless variants where available.

### SEC-9: Tailnet ACL Grants Every Member Full Admin on Every App
**Requirement:** Least-privilege authorization, not just authentication, over the tailnet
- **Current State:** `tailscale_acl` in `infrastructure/main.tf` grants `autogroup:member` unrestricted `ip: ["*"]` access to every device tagged `tag:k8s` — i.e. every app. Combined with the `arrExternalAuthInitContainer` helper, which forces Sonarr/Radarr/Prowlarr/etc.'s own `AuthenticationMethod` to `External` (because tailnet membership was assumed to *be* the authorization boundary), any tailnet member — including a shared or guest device — has full admin on every *arr app, Transmission (which has no RPC auth of its own either) and Home Assistant, not just consumer apps like Jellyfin/Seerr/Kavita.
- **Improvement:** Split the ACL `grants` into a consumer tier (Jellyfin, Seerr, Kavita, Heimdall) open to `autogroup:member`, and an admin tier (Sonarr, Radarr, Prowlarr, Transmission, Bazarr, Mylar3, Bookshelf, Home Assistant, BabyBuddy, Gramps) restricted to a new `group:admins`. Add the ACL policy's `tests` block so a bad grant fails `terraform apply` instead of silently widening access.
- **Caveat:** Needs tagging each app's Service/Ingress by tier, and deciding who belongs in `group:admins` in the Tailscale admin console first.

### SEC-3: Enable Key Vault Purge Protection — on the Project Vault
**Requirement:** Secret durability
- **Current State:** ⚠️ **Revised** — the previous version of this item (and **MAINT-3**, below) described `home-media-server-kv` as a dead pass-through nobody read from. That's no longer true as of the Flux/Azure-Arc GitOps work (**OPS-1**): this vault is now the sync source External Secrets Operator reads from, via Workload Identity Federation (`infrastructure/arc.tf`) — every Secret the chart needs, and the merged `infrastructure-values` blob, live here and are pulled into the cluster from here on an hourly refresh. `purge_protection_enabled = false` and `soft_delete_retention_days = 7` (`infrastructure/main.tf`) genuinely matter now: losing this vault means every app loses its credentials and the chart's own values, not just a stale copy.
- **Improvement:** Set `purge_protection_enabled = true`; increase `soft_delete_retention_days` to 90.
- **Caveat:** `purge_protection_enabled` is one-way on Azure — it cannot be turned back off once set on a vault.

### SEC-11: Harden the Terraform State Storage Account
**Requirement:** Protect the one artifact that holds every secret this stack depends on
**Current State:** `providers.tf`'s `backend "azurerm"` points at `robstewarttfstate`/`tfstate`. Terraform state holds every secret value this repo manages in plaintext (WireGuard private key, Tailscale OAuth client secret, generated Postgres password, API tokens) — it's a bigger single point of compromise than any individual Key Vault secret.
- **Improvement:** On that storage account: disable public blob access, enable blob versioning and soft delete (which also gives a recovery path if state itself gets corrupted, not just deleted), and scope RBAC on the container to only the identities that need it (today: whoever runs `terraform apply` by hand; after **OPS-1**, the CI identity too).
- **Caveat:** Pairs with **OPS-4** (resource locks) — together they cover both accidental deletion and accidental exposure.

### SEC-10: Pod Security Admission in Warn/Audit Mode
**Requirement:** Surface **SEC-2** violations without a hard blocker
- **Current State:** Nothing checks container security posture, even passively.
- **Improvement:** Label the `home-media-server` namespace with Pod Security Admission's `warn` and `audit` levels (e.g. `baseline`). This surfaces every container running as root, with excess capabilities, etc. in `kubectl` warnings and audit logs without breaking anything.
- **Caveat:** Must stay `warn`/`audit`, not `enforce` — Gluetun genuinely needs `NET_ADMIN`, which `restricted` (and parts of `baseline`) would block outright.

### SEC-4: Add NetworkPolicies
**Requirement:** Network micro-segmentation
- **Current State:** All pods can communicate with all other pods in the namespace.
- **Improvement:** Add a default-deny `NetworkPolicy` for the namespace, then add explicit allow rules per service. Priority targets:
  - Isolate Transmission/Gluetun — only allow VPN egress and internal service communication
  - Restrict Prowlarr/Flaresolverr to relevant internal services only

### SEC-5: Pin All Images to a Real Tag or Digest
**Requirement:** Reproducibility, supply-chain security, and (as a side effect) automated updates
- **Current State:** Gluetun (both instances), Transmission, and the dead `calibre` block use `latest`. `rreading-glasses` (`hardcover`), `postgres` (`'18'`) and `valkey` (`'9-alpine'`) are pinned to a real but non-semver or partial tag with no fixed patch version, so a restart can pull a materially different image under the same tag.
- **Improvement:** Pin every image to either a specific semver tag (where the upstream publishes one) or a content digest (`image@sha256:...`) where it doesn't. Renovate's digest-pinning support (`pinDigests`, or `image@sha256:...` with a floating tag comment) tracks floating tags like `hardcover`/`latest` just as well as it tracks semver — it raises a PR whenever the digest moves, there's no fundamental gap here, just images that were never pinned in the first place.
- **Note:** Supersedes the old OPS-3 item, which incorrectly claimed Renovate "cannot track" floating-tag images — it can, via digest pinning, once they're pinned at all.

### SEC-6: Container Vulnerability Scanning
**Requirement:** Vulnerability management & compliance
- **Current State:** No security scanning in the pipeline.
- **Improvement:** Integrate Trivy into the CI pipeline to scan images on every PR. Optionally add Polaris for Kubernetes best-practices validation and Falco for runtime anomaly detection.
- **Caveat:** Falco's eBPF/kernel-module runtime detection has historically had trouble in nested virtualization; that concern doesn't apply now that the cluster runs natively on k3s rather than inside Docker/K3d, so it's viable here without a preliminary spike — but it's still lower priority than the scanning tools above.

---

## 🟠 MEDIUM PRIORITY — Reliability

### REL-3: Back Up Config Data
**Requirement:** Data protection & disaster recovery — some of this data is irreplaceable
- **Current State:** No backup or restore strategy at all. All application state lives in host-path PVCs: 5 Gi config, 600 Gi media. Gramps (genealogy) and BabyBuddy (childcare tracking) hold data that cannot be re-downloaded or regenerated if the config volume is lost, unlike media libraries or *arr app state.
- **Improvement:** A CronJob (declared in this chart, not configured by hand on the host) running restic or kopia against `/srv/home-media-server/config` only — not the 600 Gi media volume — to Azure Blob Storage. Lean on the *arr apps' own scheduled backup/export features (Sonarr/Radarr's built-in zip backups, a Gramps export) to get consistent snapshots of SQLite-backed state rather than risking a live copy of an open database file. Document and actually test a restore.
- **Note:** Raised in priority relative to the old Velero-based version of this item: Velero doesn't suit `local` PersistentVolumes well (no CSI snapshotter here, so it would need node-agent file-level backup) for comparatively little gain over a much simpler in-repo CronJob, and the irreplaceable-data risk (Gramps/BabyBuddy) makes this more urgent than "medium reliability" implies.
- **Caveat:** Carries an ongoing Azure Blob Storage cost (storage + egress for restores). The config-only footprint (a few GB) keeps this small; size it before picking a retention window.

### REL-1: Add Missing Health Probes
**Requirement:** Kubernetes self-healing
- **Current State:** Incomplete probe coverage across the cluster:
  - **Home Assistant**: no liveness, readiness, or startup probes
  - **Gluetun**: no probes at all (both the Transmission sidecar and the standalone `indexer-proxy` instance)
  - **Bazarr**: startup probe only, no liveness or readiness
- **Improvement:** Add appropriate startup, liveness, and readiness probes for each, using the existing port-9999 Gluetun health endpoint for its `livenessProbe`/`readinessProbe`.
- **Note:** The only protection today against a torrent leaking outside the tunnel if Gluetun's connection drops is its own iptables kill-switch (`FIREWALL=on` by default), which blocks the traffic at the network layer but won't stop Transmission from queuing/retrying against a dead tunnel. Worth deciding deliberately whether the kill-switch alone is sufficient or whether a monitor that stops Transmission on Gluetun-unhealthy should be added as part of this item.

### REL-6: Stop Using `pullPolicy: Always` on Pinned Images
**Requirement:** Reliability and reproducibility of restarts, once **SEC-5** lands
- **Current State:** Most images in `helm/values.yaml` set `pullPolicy: Always`, including ones already pinned to a specific semver tag (only `postgres` and the bootstrap `busybox` use `IfNotPresent`). This means every pod restart — even one unrelated to a deploy, like a node reboot or an OOM kill — depends on the registry being reachable, and is subject to registry rate limits (Docker Hub in particular). For a genuinely floating tag this is what keeps it current, but for a pinned tag it buys nothing and only adds a failure mode.
- **Improvement:** Once **SEC-5** pins an image to a real tag or digest, switch its `pullPolicy` to `IfNotPresent`. Leave `Always` only on images that remain intentionally floating.

### REL-4: Horizontal Pod Autoscaling (HPA) ❌ WON'T DO
**Requirement:** Automatic scaling under load
- **Reason:** This is a single-node cluster, so an HPA can't add capacity, only add replicas on the same node — and most of these apps (the *arr suite in particular) keep their state in SQLite on a shared PVC, where a second replica would corrupt data rather than share load. Not worth pursuing here.

### REL-5: Multi-Node Cluster Support
**Requirement:** High availability, load distribution
- **Current State:** Single-node k3s cluster — any node maintenance takes everything down.
- **Improvement:** Expand to a multi-node k3s cluster. Add worker nodes, configure node selectors and GPU tolerations, add anti-affinity rules to spread critical services.
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

### OBS-4: Application-Level Metrics (APM)
**Requirement:** Media-specific performance insights
- **Current State:** No application-level monitoring.
- **Improvement:** Add Prometheus exporters or enable built-in metric endpoints for Sonarr, Radarr, and Jellyfin. Track download rates, transcoding performance, library scan times, and active stream counts in Grafana.

### OBS-5: Distributed Tracing ❌ WON'T DO
**Requirement:** Request-flow debugging across services
- **Reason:** None of the apps in this stack emit traces, and there's no polyglot request-fan-out pattern here that tracing is meant to untangle. The observability gap this stack actually has is metrics and logs (OBS-1/OBS-2), not trace correlation.

---

## 🟡 MEDIUM PRIORITY — Operations

### OPS-1: GitOps with Flux, via Azure Arc 🚧 IN PROGRESS
**Requirement:** Declarative deployment, drift detection, audit trail, and — critically — a path off the self-hosted runner (**SEC-8**)
- **Current State:** Deployments are GitOps-based: Flux, running in-cluster as the Azure Arc-managed `microsoft.flux` extension, reconciles the chart from a specific commit that Terraform pins as the final step of each `apply` (`infrastructure/arc.tf`) — so infrastructure (the Secrets and merged values External Secrets Operator syncs from Key Vault, see **OPS-2**) always lands before the chart that depends on it. `.github/workflows/deploy.yml` runs that Terraform apply on every push to `main`, on a GitHub-hosted runner authenticated to Azure via OIDC (`infrastructure/ci.tf`) — no stored Azure credential in GitHub, and no Kubernetes access of any kind, since Terraform never touches the Kubernetes API at all (the `kubernetes` provider is gone entirely). This closes **SEC-8**'s core risk directly: nothing CI runs can reach the cluster.
- **Note:** The code is merged but **not yet applied/verified against the live cluster** — see `infrastructure/arc.tf`'s and `.github/workflows/deploy.yml`'s own comments for the bootstrap sequence (a human runs `task recreate` locally once to create the Arc connection and the CI identity itself, sets three GitHub repository variables from `terraform output`, then pushes are what deploy from then on). Once confirmed working: unregister the self-hosted runner (**SEC-8**) → split the tailscale-operator/nvidia-device-plugin subcharts into their own HelmReleases, which also removes the last locally-run step (`task helm:crds:apply`, still needed as a manual local task until then - see that task's own comment).
- **Caveat:** The Arc GitOps (Flux) extension is billed per vCPU beyond a small free allowance — expect roughly $10–15/month on this host's core count. Confirm current pricing before merging. A cheaper fallback for remote `kubectl` alone, without Arc/Flux, is the Tailscale operator's own API-server proxy over the existing tailnet.

### OPS-2: External Secrets Operator for Secret Rotation 🚧 IN PROGRESS
**Requirement:** Zero-downtime secret rotation
- **Current State:** ⚠️ **Revised** — folded into the **OPS-1** work rather than left as a follow-up: External Secrets Operator is now declared (`clusters/home/external-secrets.yaml`, `secret-store.yaml`, `external-secret.yaml`), installed in-cluster by Flux, and reads this project's Key Vault via Workload Identity Federation (`infrastructure/arc.tf`) — no stored credential anywhere. Terraform's `kubernetes` provider is gone entirely; every Secret the chart needs, and the merged `infrastructure-values` blob, are written to Key Vault instead and synced in on a 1-hour `refreshInterval`. Not yet verified against the live cluster — see **OPS-1**'s own note.
- **Improvement:** Mark this ✅ DONE once the live cutover (see **OPS-1**) is confirmed working end-to-end.

### OPS-3: Extend Renovate to Track All Image Tags ✅ FOLDED INTO SEC-5
**Previous State:** Believed Renovate couldn't track floating-tag images (`gluetun`, `transmission`, `rreading-glasses`, etc.) at all.
- **Resolution:** That premise was wrong — Renovate's digest pinning tracks floating tags too, raising a PR whenever the digest moves. The actual work item is just pinning every image per **SEC-5**; there's no separate Renovate configuration task once that's done.

### OPS-4: Azure Resource Locks
**Requirement:** Accidental-deletion protection
- **Current State:** No resource locks on the Key Vault or Terraform state storage account.
- **Improvement:** Add `azurerm_management_lock` (CanNotDelete) in Terraform for the Key Vault and the `robstewarttfstate` storage account.

### OPS-5: Resource Usage Profiling (Prerequisite for SEC-1)
**Requirement:** Evidence-based resource constraints
- **Current State:** `metrics-server` is already deployed and functional — `kubectl top pods -n home-media-server` works today.
- **Improvement:** Run `kubectl top pods -n home-media-server` over a representative period (covering a typical download + transcoding session). Deploy VPA in recommendation-only mode to surface suggested request/limit values per container before hardcoding them into **SEC-1**.

### OPS-6: Automated Rollback on Failed Deploy
**Requirement:** Fail safe, not loud, on a broken chart change
- **Current State:** `helm upgrade --install` in `helm/Taskfile.yml` has no `--atomic`/rollback flag, so a failed upgrade can leave the release in a half-applied state until someone notices and rolls back by hand.
- **Improvement:** Once **OPS-1** moves deploys to Flux's `HelmRelease`, this is close to free — Flux's `upgrade.remediation`/`install.remediation` retry-and-rollback settings cover it directly. Everything else this item used to cover (chart linting, image scanning) is already tracked separately under **OPS-8** and **SEC-6**.

### OPS-7: Infrastructure as Code Enhancement
**Requirement:** Fully reproducible infrastructure
- **Current State:** Terraform manages cloud resources; the k3s cluster setup itself (`k3s/Taskfile.yml`, `k3s/config.yaml`) is already declarative and scripted, but not yet provisioned by Terraform.
- **Improvement:** Automate k3s cluster provisioning via Terraform (or keep it in the Taskfile but extract reusable Terraform modules for the Azure/Tailscale side). Add remote state locking (already partially in place via Azure Storage).

### OPS-8: Validate the Helm Chart in CI
**Requirement:** Catch broken templates before they reach the cluster
- **Current State:** `ci.yml` builds/checks the devcontainer environment but never renders or lints the Helm chart. A syntax error or bad value reference in `helm/templates/` can merge silently and only surface when a real deploy runs.
- **Improvement:** Add a CI step running `helm template . --values values.yaml --values sample.infrastructure.values.yaml` (a fixture values file) and `helm lint`, failing the build on error. A ~10-line addition, not a new dependency — smaller and higher-value than the full `chart-testing`/`helm unittest` scope in **QA-1**, and should land well before it. Once **OPS-1**'s `clusters/home/` directory exists, extend this to `kubectl kustomize clusters/home | kubeconform`.

### OPS-9: Detect App-Level Config Drift After Infra Changes
**Requirement:** Catch breakage that lives outside Helm/Terraform entirely
- **Current State:** No item in this roadmap covers it, and none of the proposed CI/GitOps items (**OPS-1**, **OPS-8**, **QA-1**) would catch it, because the drift lives in each app's own persisted state on the config PVC, not in the chart. Confirmed twice already after a past subdomain migration: Bazarr kept stale `/radarr` and `/sonarr` URLs in its own Radarr/Sonarr integration settings, and Heimdall's dashboard kept duplicate tile rows pointing at old path-prefix URLs in its SQLite database — both required a manual `kubectl exec` to find and fix.
- **Improvement:** At minimum, add a checklist step to the "how to change a hostname/route" process reminding to check dependent apps' own settings (Bazarr's Radarr/Sonarr URLs, Heimdall's tiles, Jellyfin's base URL, any `*arr` app that talks to another). A stretch goal would be a small script that greps each app's persisted config for the old hostname/prefix after a routing change and flags matches. See also **FEAT-4** — replacing Heimdall with a YAML-configured dashboard removes one of the two confirmed sources of this drift outright.

### OPS-10: Pin the k3s Version
**Requirement:** Reproducible cluster installs
- **Current State:** `k3s:cluster:install` in `k3s/Taskfile.yml` pipes the latest `get.k3s.io` installer straight into `sh`, so a cluster rebuild today can land on a different k3s version than the one currently running, with no record of which version is live.
- **Improvement:** Pin an explicit `INSTALL_K3S_VERSION` (the installer script's own supported pinning mechanism) in the Taskfile, and track it with a Renovate regex/custom manager the same way other unmanaged version strings in this repo are tracked.
- **Note:** The host's NVIDIA driver and container toolkit remain outside this repo's version tracking — k3s auto-detects them but doesn't manage their versions, and there's no in-repo equivalent of the old CUDA node image to pin them from anymore.

---

## 💾 MEDIUM PRIORITY — Storage & Data

### STOR-1: Storage Class Tiering
**Requirement:** Performance-optimised storage
- **Current State:** Single `local-storage` host-path class for all volumes.
- **Improvement:** Create separate storage classes for SSD (config, databases) and HDD (bulk media). Add volume snapshot capability for point-in-time recovery.

### STOR-2: Database for Application Metadata
**Requirement:** Reliable, queryable metadata storage
- **Current State:** All *arr services store metadata in SQLite files on the config PVC.
- **Improvement:** Deploy a shared PostgreSQL instance and configure Sonarr, Radarr, Prowlarr, and Bazarr to use it — all four natively support Postgres as an alternative to SQLite. Improves performance and simplifies backup (database dump vs. full PVC snapshot).
- **Note:** The previous version of this item also proposed "Redis for session caching" — dropped, since none of these apps have a supported Redis-backed session/caching mode to configure.

---

## ⚡ MEDIUM PRIORITY — Performance Management

### PERF-1: Scale-to-Zero for Idle Apps
**Requirement:** Don't run rarely-used apps 24/7 on a single-node box
**Current State:** All services run a static 1 replica permanently, regardless of actual usage. State lives on the shared `config`/`media` PVCs rather than per-pod storage, so scaling a StatefulSet to 0 and back is safe here in a way it wouldn't be with per-pod PVs.
- **Improvement:** Deploy KEDA. Two tiers of ambition:
  - **Near-term, low effort:** cron-based scaling (KEDA's cron scaler, or even a plain `CronJob` running `kubectl scale`) for genuinely low-traffic apps like Bazarr/Prowlarr overnight.
  - **Stretch goal:** true on-demand scaling via `keda-http-add-on`, which wakes a pod on the next incoming request. This needs real re-plumbing of the routing layer — requests would go through KEDA's proxy instead of directly to each app's Service, which today is a Tailscale `Ingress` per app (see the `tailscaleIngress` helper in `helm/templates/functions.tpl`).

### PERF-2: Prioritize Jellyfin Under Resource Contention
**Requirement:** Protect the app people are actively watching when the node is under load
- **Current State:** No `PriorityClass` on any pod; no container has `requests == limits` (guaranteed QoS). Under contention, the scheduler/kernel has no signal that Jellyfin matters more than a background Sonarr scan.
- **Improvement:** Give Jellyfin a higher `PriorityClass` and guaranteed QoS (requests == limits) so the scheduler preempts/evicts lower-priority pods before touching it under pressure. This folds directly into **SEC-1** — set Jellyfin's numbers as part of that same resource-limits pass rather than as a separate effort.
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
- **Current State:** Heimdall serves as the dashboard but requires manual link configuration with no live service data, and its config lives in a SQLite database on the config PVC — one of the two confirmed sources of the app-level config drift described in **OPS-9**.
- **Improvement:** Deploy Homepage (gethomepage.dev) alongside or as a replacement for Heimdall. It has native widget integrations for Sonarr, Radarr, Jellyfin, Home Assistant, Transmission, and Prowlarr — showing download queues, library counts, and now-playing info directly on the dashboard.
- **Note:** Raised in priority relative to the old ordering — unlike Heimdall, Homepage is configured entirely from YAML, so it can be declared as a ConfigMap in this chart rather than drifting from hand-configured host state, directly addressing one of **OPS-9**'s two confirmed incidents.

### FEAT-5: GPU Time-Slicing / NVIDIA GPU Operator
**Requirement:** Efficient GPU utilisation for multiple workloads
- **Current State:** Basic NVIDIA device plugin; GPU is exclusively allocated to Jellyfin.
- **Improvement:** Deploy the NVIDIA GPU Operator and configure GPU time-slicing so the GPU can be shared across pods when Jellyfin is idle. Add GPU utilisation metrics to Grafana (via DCGM exporter).

### FEAT-6: VPN Integration Enhancement ✅ DONE
**Requirement:** Secure direct access from trusted devices
- **Previous State:** External access was Cloudflare Tunnel only; no direct WireGuard access for trusted clients.
- **Improvement:** Replaced Cloudflare Tunnel with Tailscale (a WireGuard mesh) via the Tailscale Kubernetes operator - see the "Ingress"/"Auth" lines above and the README's "Remote access" section. Every app is reachable directly, peer-to-peer where NAT traversal allows, from any device signed into the tailnet.

### FEAT-7: Service Mesh (Linkerd) ❌ WON'T DO
**Requirement:** Automatic mTLS, advanced traffic policies, built-in observability
- **Reason:** All inter-pod traffic already stays inside a single-node cluster reachable only over the tailnet (**FEAT-6**) — there's no untrusted network hop between pods for mTLS to protect against, and the operational cost of running a mesh on a resource-constrained single node outweighs the benefit here.

---

## 🧪 LOW PRIORITY — Quality & Testing

### QA-1: Automated Testing for Helm Charts
**Requirement:** Regression prevention on chart changes
- **Current State:** No automated testing for Helm templates or configuration.
- **Improvement:** Add `helm unittest` for template unit tests. Add `chart-testing` (ct) in CI to lint and validate chart changes on every PR.

### QA-2: Chaos Engineering ❌ WON'T DO
**Requirement:** Resilience validation
- **Reason:** On a single-node cluster there's exactly one failure domain, and it's already well understood (the node goes down, everything goes down) — scheduled pod-kill/network-partition experiments have little left to teach here that a tested backup/restore (**REL-3**) doesn't already cover more directly.

---

## 🧹 LOW PRIORITY — Maintainability

### MAINT-2: Remove Dead Values
**Requirement:** Keep `helm/values.yaml` accurate to what's actually deployed
- **Current State:** The `calibre` block in `helm/values.yaml` has no corresponding template — Calibre-Web was superseded by Bookshelf/Kavita and never cleaned up. Every app's `clusterIP` is also hardcoded to a specific address, which no template actually references by that literal value (they're all read back out of `.Values.<app>.clusterIP` and only used to pin the Service's own IP) and which risks an "field is immutable" apply failure or an address collision if the cluster's Service CIDR ever changes.
- **Improvement:** Remove the `calibre` block entirely. For the `clusterIP` pins, first confirm (by checking each app's own persisted config, not just the chart) that nothing depends on a specific IP rather than the `*-service` DNS name, then either remove the pins or replace them with a documented reason where one is genuinely needed.

### MAINT-3: Remove the Pass-Through Key Vault ✅ SUPERSEDED
**Previous State:** Believed `home-media-server-kv` was a dead pass-through nobody read from, copying secrets from the common vault for no reason.
- **Resolution:** Superseded by the Flux/Azure-Arc GitOps work (**OPS-1**) — that premise is no longer true. The project vault is now External Secrets Operator's real sync source (see **SEC-3**'s revised entry), holding every Secret the chart needs plus the merged `infrastructure-values` blob. Removing it would break every app's config, not clean up dead weight.

### MAINT-4: DRY the Helm Templates
**Requirement:** Reduce copy-paste drift across near-identical apps
- **Current State:** The chart's ~22 templates (roughly 1,900 lines) repeat the same shape for every linuxserver-style app: a Service, a single-replica StatefulSet, the `media`/`config` volumes, the `TZ`/`PUID`/`PGID` env block, and startup/liveness/readiness HTTP probes — with only the app name, image, port and mount paths actually varying.
- **Improvement:** Extend `helm/templates/functions.tpl` (which already has a `tailscaleIngress` and `arrExternalAuthInitContainer` helper following this pattern) with a few more named templates — e.g. `linuxserverEnv` for the TZ/PUID/PGID block, `httpProbes` for the standard probe shape — and migrate the simpler apps over one at a time.
- **Caveat:** Not every app fits the pattern (Transmission's Gluetun sidecar, Gramps' Celery worker) — this is about the ~15 apps that do, not a wholesale rewrite. Migrating to a full third-party library chart (e.g. bjw-s `app-template`) isn't worth it for this scale; a few more in-repo helpers is enough.

### MAINT-5: Pin the Dev Toolchain
**Requirement:** Reproducible tooling, not just reproducible cluster/app state
- **Current State:** `.devcontainer/Dockerfile` installs Helm from the `main` branch of its install script, and the latest release of kubectl and yq, with no version pinned. It also still installs k3d, which nothing in this repo uses anymore. `infrastructure/providers.tf` has no `required_version` constraint on Terraform itself. `renovate.json` extends the deprecated `config:base` preset rather than its replacement.
- **Improvement:** Pin Helm/kubectl/yq to specific versions in the devcontainer and track them with Renovate the same way application images are tracked. Remove the k3d install step. Add a `required_version` constraint to the Terraform config. Switch `renovate.json` from `config:base` to `config:recommended`.

---

## 📋 Implementation Priority Order

| # | ID | Title | Category |
|---|-----|-------|----------|
| 1 | OPS-1 | GitOps with Flux, via Azure Arc — apply/verify live, then unregister the runner | Operations |
| 2 | SEC-8 | Remaining self-hosted-runner cleanup + fork-PR approval + SHA-pinning | Security |
| 3 | OPS-2 | External Secrets Operator for secret rotation (folded into OPS-1) | Operations |
| 4 | SEC-3 | Enable purge protection on the project Key Vault (now live, not a copy) | Security |
| 5 | SEC-11 | Harden the Terraform state storage account | Security |
| 6 | REL-3 | Back up config data (Gramps/BabyBuddy is irreplaceable) | Reliability |
| 7 | SEC-5 | Pin all images to a real tag or digest | Security |
| 8 | REL-6 | Switch pinned images from `pullPolicy: Always` to `IfNotPresent` | Reliability |
| 9 | SEC-9 | Split the tailnet ACL into consumer/admin tiers | Security |
| 10 | OPS-8 | Validate the Helm chart in CI (`helm template`/`helm lint`) | Operations |
| 11 | REL-1 | Add missing health probes (Gluetun, Home Assistant, Bazarr) | Reliability |
| 12 | SEC-1 | Add resource requests/limits to all pods | Security |
| 13 | OPS-5 | Profile resource usage over a representative period (VPA recommend mode) | Operations |
| 14 | PERF-2 | Prioritize Jellyfin under contention (PriorityClass + guaranteed QoS) | Performance |
| 15 | MAINT-2 | Remove dead values (`calibre` block, unused `clusterIP` pins) | Maintainability |
| 16 | OPS-4 | Add Azure resource locks | Operations |
| 17 | OPS-9 | Detect app-level config drift after infra changes | Operations |
| 18 | SEC-2 | Add pod security contexts (test per-image first — see caveat) | Security |
| 19 | SEC-10 | Pod Security Admission in warn/audit mode | Security |
| 20 | SEC-4 | Add NetworkPolicies | Security |
| 21 | OPS-6 | Rely on Flux's automated rollback on failed deploy | Operations |
| 22 | FEAT-4 | Homepage dashboard (also closes one OPS-9 drift source) | Features |
| 23 | PERF-1 | Scale-to-zero for idle apps (KEDA, cron tier first) | Performance |
| 24 | OBS-1 | Deploy kube-prometheus-stack | Observability |
| 25 | OBS-2 | Deploy Loki + Promtail | Observability |
| 26 | SEC-6 | Container vulnerability scanning (Trivy/Polaris/Falco) | Security |
| 27 | OPS-10 | Pin the k3s version | Operations |
| 28 | OBS-4 | Application-level metrics (APM) | Observability |
| 29 | STOR-1 | Storage class tiering | Storage |
| 30 | STOR-2 | PostgreSQL for *arr metadata | Storage |
| 31 | MAINT-4 | DRY the Helm templates | Maintainability |
| 32 | MAINT-5 | Pin the dev toolchain | Maintainability |
| 33 | FEAT-2 | Unpackerr auto-extraction | Features |
| 34 | FEAT-5 | GPU time-slicing / NVIDIA GPU Operator | Features |
| 35 | OPS-7 | IaC enhancement (Terraform-provisioned k3s, reusable modules) | Operations |
| 36 | REL-5 | Multi-node cluster support (needs new hardware — see caveat) | Reliability |
| 37 | QA-1 | Helm chart automated testing (broader than OPS-8) | Quality |
| 39 | PERF-3 | Usage-aware dynamic throttling (custom build — see note) | Performance |

---

## 🎯 Success Metrics

### Security
- No self-hosted runner remains registered on this repo
- Zero critical vulnerabilities in container images
- Every image pinned to a real tag or digest, none on `latest`
- No containers running as root

### Reliability
- A restore from backup is tested at least quarterly
- Mean Time to Recovery (MTTR) < 15 minutes for a single-app failure
- Every container has both `requests` and `limits` set

### Operations
- Every commit to `main` reconciles onto the cluster via Flux, with no manual deploy step
- CI renders and lints the chart on every PR
- A failed Helm upgrade rolls back automatically, with no manual intervention
- All image updates arrive as automated Renovate PRs
- The cluster is reachable and manageable from outside the home network (Arc cluster connect)
