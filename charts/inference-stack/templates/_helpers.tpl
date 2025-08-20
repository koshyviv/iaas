{{/*
Expand the name of the chart.
*/}}
{{- define "inference-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "inference-stack.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "inference-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "inference-stack.labels" -}}
helm.sh/chart: {{ include "inference-stack.chart" . }}
{{ include "inference-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "inference-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inference-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "inference-stack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "inference-stack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate PostgreSQL connection string for LiteLLM
*/}}
{{- define "inference-stack.postgresqlConnectionString" -}}
{{- if .Values.postgres.enabled }}
postgresql://{{ .Values.postgres.auth.username }}:{{ .Values.postgres.auth.password }}@{{ .Release.Name }}-postgres-postgresql.{{ .Release.Namespace }}.svc.cluster.local:5432/{{ .Values.postgres.auth.database }}
{{- else }}
""
{{- end }}
{{- end }}

{{/*
Generate Redis connection details for LiteLLM
*/}}
{{- define "inference-stack.redisHost" -}}
{{- if .Values.redis.enabled }}
{{ .Release.Name }}-redis-master.{{ .Release.Namespace }}.svc.cluster.local
{{- else }}
""
{{- end }}
{{- end }}

{{- define "inference-stack.redisPassword" -}}
{{- if .Values.redis.enabled }}
{{ .Values.redis.auth.password }}
{{- else }}
""
{{- end }}
{{- end }}

{{/*
Generate Ollama service endpoints for LiteLLM configuration
*/}}
{{- define "inference-stack.ollamaEndpoints" -}}
{{- $endpoints := list }}
{{- if (index .Values "ollama-llama31").enabled }}
{{- $endpoints = append $endpoints (printf "http://%s-ollama-llama31.models.svc.cluster.local:11434" .Release.Name) }}
{{- end }}
{{- if (index .Values "ollama-mistral").enabled }}
{{- $endpoints = append $endpoints (printf "http://%s-ollama-mistral.models.svc.cluster.local:11434" .Release.Name) }}
{{- end }}
{{- if (index .Values "ollama-phi3").enabled }}
{{- $endpoints = append $endpoints (printf "http://%s-ollama-phi3.models.svc.cluster.local:11434" .Release.Name) }}
{{- end }}
{{- $endpoints | toJson }}
{{- end }}

{{/*
Generate MetalLB IP address pool configuration
*/}}
{{- define "inference-stack.metallbAddressPool" -}}
{{- if .Values.metallb.enabled }}
{{- range .Values.metallb.ipAddressPools }}
- {{ . | toJson }}
{{- end }}
{{- end }}
{{- end }}
