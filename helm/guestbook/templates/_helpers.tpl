{{/*
Fonctions communes du chart : noms des objets et labels.
Les templates des objets utilisent ces fonctions, comme ça
aucun nom ni label n'est écrit à la main.
*/}}

{{/*
Nom du chart ("guestbook"), modifiable avec nameOverride.
*/}}
{{- define "guestbook.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nom complet : <release>-guestbook (exemple : stack-test-guestbook).
Modifiable avec fullnameOverride. Coupé à 63 caractères car
Kubernetes refuse les noms plus longs.
*/}}
{{- define "guestbook.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "guestbook.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Nom et version du chart pour le label helm.sh/chart (exemple : guestbook-0.2.0).
*/}}
{{- define "guestbook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels utilisés dans les selectors.
Pas de numéro de version ici : le selector d'un Deployment ne peut
plus être modifié après la création, sinon le helm upgrade échoue.
*/}}
{{- define "guestbook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "guestbook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Labels mis sur tous les objets : infos du chart et de la release,
plus les commonLabels des fichiers values (environment, team).
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

{{/*
Les 3 fonctions suivantes prennent 2 paramètres :
  root      = le contexte du chart (le point ".")
  component = frontend, redis-leader ou redis-follower
Exemple : include "guestbook.componentName" (dict "root" . "component" "frontend")
*/}}

{{/*
Nom d'un objet d'un composant (exemple : stack-test-guestbook-redis-leader).
*/}}
{{- define "guestbook.componentName" -}}
{{- printf "%s-%s" (include "guestbook.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels communs + label du composant (pour metadata.labels).
*/}}
{{- define "guestbook.componentLabels" -}}
{{ include "guestbook.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Labels du selector + label du composant (pour spec.selector).
*/}}
{{- define "guestbook.componentSelectorLabels" -}}
{{ include "guestbook.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}
