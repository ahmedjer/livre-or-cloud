
{{/*
Return the chart name.
Supports overriding the name through values.yaml.
*/}}
{{- define "guestbook.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Return the full application name.
Combines the Helm release and chart name.
Example: stack-dev-guestbook.
*/}}
{{- define "guestbook.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "guestbook.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}


{{/*
Return the chart name and version.
Example: guestbook-0.1.0.
*/}}
{{- define "guestbook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Stable selector labels for Kubernetes Deployments and Services.
These labels identify the Helm release.
*/}}

{{/*
Stable selector labels for Kubernetes Deployments and Services.

By default, use the Helm release name.
For dev migration, preserve the original immutable selector.
*/}}
{{- define "guestbook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "guestbook.name" . }}
app.kubernetes.io/instance: {{ default .Release.Name .Values.selectorInstanceOverride }}
{{- end -}}



{{/*
Common labels applied to application resources.
Includes chart metadata, release information and custom labels.
*/}}
{{- define "guestbook.labels" -}}
helm.sh/chart: {{ include "guestbook.chart" . }}
{{ include "guestbook.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: guestbook
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}
