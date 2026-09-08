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
