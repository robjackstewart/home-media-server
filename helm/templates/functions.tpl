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

{{- define "tailscaleIngress" -}}
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
            name: {{ .service }}
            port:
              number: {{ .port }}
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
      if [ -f /config/config.xml ]; then
        sed -i 's|<AuthenticationMethod>.*</AuthenticationMethod>|<AuthenticationMethod>External</AuthenticationMethod>|' /config/config.xml
      fi
  volumeMounts:
    - name: config
      mountPath: /config
      subPath: {{ .subPath }}
{{- end -}}
