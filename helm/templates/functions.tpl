# image - builds an image string from the following structure:

# registry: string
# repository: string
# tag: string

{{- define "image" -}}
{{- $image := printf "%s/%s:%s" .registry .repository .tag -}}
{{- $image | quote -}}
{{- end -}}