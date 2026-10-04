# image - builds an image string from the following structure:

# registry: string
# repository: string
# tag: string

{{- define "image" -}}
{{- $image := printf "%s/%s:%s" .registry .repository .tag -}}
{{- $image | quote -}}
{{- end -}}

# tailscaleIngress - renders a Tailscale Ingress exposing one Service as its own MagicDNS name
# (https://<subdomain>.<tailnet>.ts.net), proxied through the shared ProxyGroup. Takes a dict:

# name: string       - the Ingress' own name
# subdomain: string  - short MagicDNS name (no tailnet suffix - the operator appends that)
# service: string    - backend Service name
# port: int          - backend Service port
# proxyGroup: string - the ProxyGroup (see templates/tailscale.yaml) to proxy through
# interceptor: dict  - optional {service, port}. When set, the Ingress routes to the KEDA HTTP
#                      Add-on interceptor instead of the app's own Service, so the app can be
#                      scaled to zero and woken by the next request (see kedaInterceptorRoute /
#                      kedaScaledObject below and the `keda` values block).

{{- define "tailscaleIngress" -}}
{{- $backendService := .service -}}
{{- $backendPort := .port -}}
{{- if .interceptor -}}
{{- $backendService = .interceptor.service -}}
{{- $backendPort = .interceptor.port -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  annotations:
    tailscale.com/proxy-group: {{ .proxyGroup }}
spec:
  ingressClassName: tailscale
  tls:
  - hosts:
    - {{ .subdomain }}
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ $backendService }}
            port:
              number: {{ $backendPort }}
{{- end -}}

# kedaInterceptorRoute - renders the KEDA HTTP Add-on InterceptorRoute that maps an on-demand
# app's MagicDNS Host to its Service and tells the interceptor how to behave during a cold start.
#
# The interceptor routes by the request's Host header, which is why `host` must be the full
# MagicDNS name the Tailscale proxy forwards (https://<subdomain>.<tailnet>). This is the one
# assumption the whole on-demand design rests on: verify on the pilot app that the interceptor
# sees that Host (kubectl logs on the interceptor) before trusting it for the rest.
#
# A placeholder is served immediately while the app scales from zero, rather than the
# interceptor holding the connection for the whole cold start - the Tailscale proxy's timeout
# for a held request is undocumented, and returning fast sidesteps it entirely. The meta-refresh
# re-requests every 5s until the app is ready and the request is forwarded through.
#
# name: string             - app name, also the InterceptorRoute/ScaledObject name
# service: string          - the app's own Service (the interceptor's target)
# port: int                - the app's Service port
# host: string             - full MagicDNS hostname, e.g. kavita.<tailnet>
# readinessTimeout: string - how long the interceptor waits for a cold start before giving up
#                            (the request deadline itself is disabled so long downloads stream)

{{- define "kedaInterceptorRoute" -}}
apiVersion: http.keda.sh/v1beta1
kind: InterceptorRoute
metadata:
  name: {{ .name }}
spec:
  target:
    service: {{ .service }}
    port: {{ .port }}
  rules:
    - hosts:
        - {{ .host }}
  scalingMetric:
    concurrency:
      targetValue: 1
  coldStart:
    placeholder:
      response:
        statusCode: 200
        headers:
          Content-Type: text/html; charset=utf-8
        body: |
          <!doctype html>
          <html>
            <head>
              <meta http-equiv="refresh" content="5">
              <title>Starting {{ .name }}</title>
            </head>
            <body>
              <p>{{ .name }} is starting up. This can take up to a minute; this page will refresh automatically.</p>
            </body>
          </html>
  timeouts:
    readiness: {{ .readinessTimeout }}
    request: 0s
{{- end -}}

# kedaScaledObject - scales an on-demand app's StatefulSet between 0 and 1. maxReplicaCount is
# pinned to 1 because every app here keeps its state in SQLite on a shared PVC - a second
# replica would corrupt it rather than share load (see improvements.md REL-4).
#
# Two triggers:
#   - external-push: the HTTP Add-on's scaler, which counts in-flight requests. A request for a
#     scaled-to-zero app wakes it.
#   - cron: forces the app to zero during an off-hours window, so an otherwise-idle app reliably
#     reaches zero instead of being pinned up by a stray request. A request during the window
#     still wakes it - KEDA's HPA takes the max across triggers.
#
# Emit this *after* the matching InterceptorRoute: KEDA reconciles a ScaledObject with an
# external-push trigger by calling the scaler's GetMetricSpec, and if the InterceptorRoute does
# not exist yet it falls back to a CPU metric and scale-from-zero never works.
#
# name: string           - app name; must match the InterceptorRoute name and StatefulSet name
# cooldownPeriod: int    - seconds idle before scaling to zero (measured from the last request)
# timezone: string       - IANA timezone for the cron window
# cronStart: string      - cron expression for the start of the off-hours window
# cronEnd: string        - cron expression for the end of the off-hours window
# scalerAddress: string  - the HTTP Add-on external scaler gRPC address

{{- define "kedaScaledObject" -}}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .name }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: {{ .name }}
  minReplicaCount: 0
  maxReplicaCount: 1
  cooldownPeriod: {{ .cooldownPeriod }}
  triggers:
    - type: external-push
      metadata:
        scalerAddress: {{ .scalerAddress }}
        interceptorRoute: {{ .name }}
    - type: cron
      metadata:
        timezone: {{ .timezone }}
        start: {{ .cronStart }}
        end: {{ .cronEnd }}
        desiredReplicas: "0"
{{- end -}}

# arrExternalAuthInitContainer - patches a *arr app's config.xml to AuthenticationMethod:External
# on every pod start, before the main container reads it. Sonarr/Radarr's own auth is redundant
# here - tailnet membership is this chart's whole authorization boundary, nothing else can reach
# these apps at all - and their "Disabled for Local Addresses" mode never actually applies over
# the tailnet anyway, since Tailscale's IP range (100.64.0.0/10) isn't one of the ranges *arr
# apps treat as local (a deliberate "Won't Fix" upstream, not a bug: github.com/Radarr/Radarr/issues/9242).
# External is a real, supported *arr setting for exactly this "something in front of me already
# handles trust" case - just not exposed in the UI, only settable in config.xml directly.
#
# Runs on every start, not just once, because Radarr has a known bug (Radarr#9353) where this
# setting can get reverted or duplicated in config.xml across restarts - reapplying it here on
# every boot makes that self-healing instead of a one-off manual fix. Skips silently if
# config.xml doesn't exist yet (a brand new install's first boot, before the app has created it);
# takes effect from that pod's next restart onward.
#
# Searches for config.xml with `find` rather than assuming it sits directly at /config/config.xml,
# because not every *arr image puts it there: Bookshelf's Dockerfile sets XDG_CONFIG_HOME=/config/xdg
# (unlike the mainline linuxserver Sonarr/Radarr/Prowlarr images this was written against), so its
# config.xml actually lands a couple of directories deeper, under /config/xdg/<app>/. The search is
# still scoped correctly since this container's /config is already that one app's own subPath, never
# shared with another app's config.

# image: dict    - {registry, repository, tag, pullPolicy} - reuses hostStorageBootstrap's busybox
# subPath: string - the app's own subdirectory under the shared config PVC (e.g. "sonarr")

{{- define "arrExternalAuthInitContainer" -}}
- name: force-external-auth
  image: {{ include "image" .image }}
  imagePullPolicy: {{ .image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      find /config -name config.xml -exec sed -i 's|<AuthenticationMethod>.*</AuthenticationMethod>|<AuthenticationMethod>External</AuthenticationMethod>|' {} +
  volumeMounts:
    - name: config
      mountPath: /config
      subPath: {{ .subPath }}
{{- end -}}

# bazarrSubsyncInitContainer - patches Bazarr's config.yaml subsync settings on every pod start,
# before the main container reads them. Bazarr's own UI is the only place these are otherwise
# settable, so without this a redeploy or a fresh PVC silently loses them - and off is a bad
# default: `use_subsync: false` means subtitles are never aligned to the film's audio, while
# `no_fix_framerate: true` skips the 23.976-vs-25fps correction that is the classic cause of drift
# that gets steadily worse through a film.
#
# Runs on every start, not just once, so the settings self-heal if the app rewrites them, and
# skips silently if config.yaml doesn't exist yet (a brand new install's first boot, before the
# app has created it); takes effect from that pod's next restart onward. The sed is scoped to the
# top-level `subsync:` block so it can never touch a same-named key elsewhere (e.g. `subtitlecat:`),
# and anchors each key with its exact `: ` suffix so `use_subsync` never matches
# `use_subsync_threshold`. Both `use_subsync_*_threshold` flags are forced on so the series/movie
# thresholds actually gate syncing rather than being ignored.
#
# image: dict    - {registry, repository, tag, pullPolicy} - reuses hostStorageBootstrap's busybox
# subPath: string - the app's own subdirectory under the shared config PVC (e.g. "bazarr")
# subsync: dict  - {useSubsync, seriesThreshold, movieThreshold, fixFramerate, maxOffsetSeconds}

{{- define "bazarrSubsyncInitContainer" -}}
- name: force-subsync
  image: {{ include "image" .image }}
  imagePullPolicy: {{ .image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      if [ -f /config/config/config.yaml ]; then
        sed -i -e '/^subsync:/,/^[a-z_]*:$/{ s|^  use_subsync: .*|  use_subsync: {{ .subsync.useSubsync }}|; s|^  use_subsync_threshold: .*|  use_subsync_threshold: true|; s|^  use_subsync_movie_threshold: .*|  use_subsync_movie_threshold: true|; s|^  subsync_threshold: .*|  subsync_threshold: {{ .subsync.seriesThreshold }}|; s|^  subsync_movie_threshold: .*|  subsync_movie_threshold: {{ .subsync.movieThreshold }}|; s|^  no_fix_framerate: .*|  no_fix_framerate: {{ not .subsync.fixFramerate }}|; s|^  max_offset_seconds: .*|  max_offset_seconds: {{ .subsync.maxOffsetSeconds }}| }' /config/config/config.yaml
      fi
  volumeMounts:
    - name: config
      mountPath: /config
      subPath: {{ .subPath }}
{{- end -}}
