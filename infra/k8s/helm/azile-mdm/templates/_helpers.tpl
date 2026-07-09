{{/*
=============================================================================
Nexus AI MDM Platform â€” Helm Template Helpers
=============================================================================
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "azile-mdm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncates at 63 chars because some Kubernetes name fields are limited to this
(e.g. by the DNS naming spec). If the release name already contains the chart
name it will be used as the full name.
*/}}
{{- define "azile-mdm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label value (chart name + version).
*/}}
{{- define "azile-mdm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
These follow the recommended Kubernetes label schema.
*/}}
{{- define "azile-mdm.labels" -}}
helm.sh/chart: {{ include "azile-mdm.chart" . }}
{{ include "azile-mdm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nexus-mdm
{{- end }}

{{/*
Selector labels â€” used in matchLabels and service selectors.
These MUST be immutable after initial deployment.
*/}}
{{- define "azile-mdm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "azile-mdm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service-scoped selector labels.
Usage: include "azile-mdm.serviceSelectorLabels" (dict "root" . "service" "api-gateway")
*/}}
{{- define "azile-mdm.serviceSelectorLabels" -}}
app.kubernetes.io/name: {{ .service }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .service }}
{{- end }}

{{/*
Service-scoped common labels (selector labels + chart metadata).
Usage: include "azile-mdm.serviceLabels" (dict "root" . "service" "api-gateway")
*/}}
{{- define "azile-mdm.serviceLabels" -}}
{{ include "azile-mdm.serviceSelectorLabels" . }}
helm.sh/chart: {{ include "azile-mdm.chart" .root }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: nexus-mdm
{{- end }}

{{/*
Create the image reference for a service sub-values map.
Usage: include "azile-mdm.image" .Values.apiGateway
The repository value may itself be a template string; we tpl-render it here.
*/}}
{{- define "azile-mdm.image" -}}
{{- $repo := .image.repository -}}
{{- $tag  := .image.tag | default "latest" -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end }}

{{/*
Return the image pull policy for a service, falling back to IfNotPresent.
*/}}
{{- define "azile-mdm.imagePullPolicy" -}}
{{- .image.pullPolicy | default "IfNotPresent" -}}
{{- end }}

{{/*
Standard resource limit block.
Usage: include "azile-mdm.resources" .Values.apiGateway.resources
*/}}
{{- define "azile-mdm.resources" -}}
requests:
  cpu: {{ .requests.cpu | quote }}
  memory: {{ .requests.memory | quote }}
limits:
  cpu: {{ .limits.cpu | quote }}
  memory: {{ .limits.memory | quote }}
{{- end }}

{{/*
Namespace helper â€” honours global.namespace or falls back to Release.Namespace.
*/}}
{{- define "azile-mdm.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end }}
