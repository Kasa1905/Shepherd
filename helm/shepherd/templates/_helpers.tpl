{{/*
Expand the name of the chart.
*/}}
{{- define "shepherd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "shepherd.fullname" -}}
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
{{- define "shepherd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "shepherd.labels" -}}
helm.sh/chart: {{ include "shepherd.chart" . }}
{{ include "shepherd.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "shepherd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shepherd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "shepherd.serviceAccountName" -}}
{{- if .Values.rbac.create }}
{{- default (include "shepherd.fullname" .) .Values.rbac.serviceAccountName }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Create the MongoDB connection string
*/}}
{{- define "shepherd.mongodbConnectionString" -}}
{{- if .Values.mongodb.external.enabled }}
{{- $hosts := "" }}
{{- if .Values.mongodb.external.hosts }}
{{- $hosts = join "," .Values.mongodb.external.hosts }}
{{- else }}
{{- $hosts = printf "%s:%d" .Values.mongodb.external.host .Values.mongodb.external.port }}
{{- end }}
{{- $params := "" }}
{{- if .Values.mongodb.external.replicaSet }}
{{- $params = printf "%s&replicaSet=%s" $params .Values.mongodb.external.replicaSet }}
{{- end }}
{{- if .Values.mongodb.external.readPreference }}
{{- $params = printf "%s&readPreference=%s" $params .Values.mongodb.external.readPreference }}
{{- end }}
{{- if .Values.mongodb.external.ssl }}
{{- $params = printf "%s&ssl=true" $params }}
{{- if .Values.mongodb.external.sslCA }}
{{- $params = printf "%s&ssl_ca_certs=%s" $params .Values.mongodb.external.sslCA }}
{{- end }}
{{- if .Values.mongodb.external.sslAllowInvalidCertificates }}
{{- $params = printf "%s&ssl_cert_reqs=CERT_NONE" $params }}
{{- end }}
{{- end }}
{{- if .Values.mongodb.external.connectTimeoutMS }}
{{- $params = printf "%s&connectTimeoutMS=%d" $params .Values.mongodb.external.connectTimeoutMS }}
{{- end }}
{{- if .Values.mongodb.external.serverSelectionTimeoutMS }}
{{- $params = printf "%s&serverSelectionTimeoutMS=%d" $params .Values.mongodb.external.serverSelectionTimeoutMS }}
{{- end }}
{{- printf "mongodb://%s:%s@%s/%s?authSource=%s%s" 
    .Values.mongodb.external.username 
    .Values.mongodb.external.password 
    $hosts
    .Values.mongodb.external.database 
    .Values.mongodb.external.authSource
    $params }}
{{- else if .Values.mongodb.internal.enabled }}
{{- printf "mongodb://%s-mongodb:27017/%s" (include "shepherd.fullname" .) .Values.mongodb.external.database }}
{{- end }}
{{- end }}