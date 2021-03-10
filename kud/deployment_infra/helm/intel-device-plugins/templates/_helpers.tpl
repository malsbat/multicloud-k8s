{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "intel-device-plugins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "intel-device-plugins.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "intel-device-plugins.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "intel-device-plugins.labels" -}}
helm.sh/chart: {{ include "intel-device-plugins.chart" . }}
{{ include "intel-device-plugins.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "intel-device-plugins.selectorLabels" -}}
app.kubernetes.io/name: {{ include "intel-device-plugins.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "intel-device-plugins.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "intel-device-plugins.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the certificate
*/}}
{{- define "intel-device-plugins.certName" -}}
{{- if .Values.certificate.name -}}
{{- .Values.certificate.name -}}
{{- else -}}
{{- printf "%s-serving-cert" (include "intel-device-plugins.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the webhook service
*/}}
{{- define "intel-device-plugins.webhook.serviceName" -}}
{{- if .Values.webhook.service.name -}}
{{- .Values.webhook.service.name -}}
{{- else -}}
{{- printf "%s-webhook-service" (include "intel-device-plugins.fullname" .) -}}
{{- end -}}
{{- end -}}
