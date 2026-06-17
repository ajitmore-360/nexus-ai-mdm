{{/*
=============================================================================
Nexus AI MDM Platform — Helm Template Helpers
=============================================================================
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "nexus-mdm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncates at 63 chars because some Kubernetes name fields are limited to this
(e.g. by the DNS naming spec). If the release name already contains the chart
name it will be used as the full name.
*/}}
{{- define "nexus-mdm.fullname" -}}
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
{{- define "nexus-mdm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
These follow the recommended Kubernetes label schema.
*/}}
{{- define "nexus-mdm.labels" -}}
helm.sh/chart: {{ include "nexus-mdm.chart" . }}
{{ include "nexus-mdm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nexus-mdm
{{- end }}

{{/*
Selector labels — used in matchLabels and service selectors.
These MUST be immutable after initial deployment.
*/}}
{{- define "nexus-mdm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nexus-mdm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service-scoped selector labels.
Usage: include "nexus-mdm.serviceSelectorLabels" (dict "root" . "service" "api-gateway")
*/}}
{{- define "nexus-mdm.serviceSelectorLabels" -}}
app.kubernetes.io/name: {{ .service }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .service }}
{{- end }}

{{/*
Service-scoped common labels (selector labels + chart metadata).
Usage: include "nexus-mdm.serviceLabels" (dict "root" . "service" "api-gateway")
*/}}
{{- define "nexus-mdm.serviceLabels" -}}
{{ include "nexus-mdm.serviceSelectorLabels" . }}
helm.sh/chart: {{ include "nexus-mdm.chart" .root }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: nexus-mdm
{{- end }}

{{/*
Create the image reference for a service sub-values map.
Usage: include "nexus-mdm.image" .Values.apiGateway
The repository value may itself be a template string; we tpl-render it here.
*/}}
{{- define "nexus-mdm.image" -}}
{{- $repo := .image.repository -}}
{{- $tag  := .image.tag | default "latest" -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end }}

{{/*
Return the image pull policy for a service, falling back to IfNotPresent.
*/}}
{{- define "nexus-mdm.imagePullPolicy" -}}
{{- .image.pullPolicy | default "IfNotPresent" -}}
{{- end }}

{{/*
Standard resource limit block.
Usage: include "nexus-mdm.resources" .Values.apiGateway.resources
*/}}
{{- define "nexus-mdm.resources" -}}
requests:
  cpu: {{ .requests.cpu | quote }}
  memory: {{ .requests.memory | quote }}
limits:
  cpu: {{ .limits.cpu | quote }}
  memory: {{ .limits.memory | quote }}
{{- end }}

{{/*
Namespace helper — honours global.namespace or falls back to Release.Namespace.
*/}}
{{- define "nexus-mdm.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end }}
