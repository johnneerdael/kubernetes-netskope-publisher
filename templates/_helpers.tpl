{{- define "npa-publisher.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "npa-publisher.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "npa-publisher.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "npa-publisher.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "npa-publisher.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "npa-publisher.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "npa-publisher.labels" -}}
helm.sh/chart: {{ include "npa-publisher.chart" . }}
app.kubernetes.io/name: {{ include "npa-publisher.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "npa-publisher.enrollmentMode" -}}
{{- default "api" .Values.enrollment.mode -}}
{{- end -}}

{{- define "npa-publisher.isApiEnrollment" -}}
{{- if eq (include "npa-publisher.enrollmentMode" .) "api" -}}true{{- end -}}
{{- end -}}

{{- define "npa-publisher.workloadType" -}}
{{- default "daemonset" .Values.workload.type -}}
{{- end -}}

{{- define "npa-publisher.isStatefulSet" -}}
{{- if eq (include "npa-publisher.workloadType" .) "statefulset" -}}true{{- end -}}
{{- end -}}

{{- define "npa-publisher.networkingMode" -}}
{{- default "host" .Values.networking.mode -}}
{{- end -}}

{{- define "npa-publisher.isPodNetworking" -}}
{{- if eq (include "npa-publisher.networkingMode" .) "pod" -}}true{{- end -}}
{{- end -}}

{{- define "npa-publisher.hostNetwork" -}}
{{- if include "npa-publisher.isPodNetworking" . -}}false{{- else -}}{{ .Values.hostNetwork }}{{- end -}}
{{- end -}}

{{- define "npa-publisher.dnsPolicy" -}}
{{- if include "npa-publisher.isPodNetworking" . -}}ClusterFirst{{- else -}}{{ .Values.dnsPolicy }}{{- end -}}
{{- end -}}

{{- define "npa-publisher.securityContext" -}}
{{- if include "npa-publisher.isPodNetworking" . -}}
allowPrivilegeEscalation: false
capabilities:
  add:
    - NET_ADMIN
    - NET_RAW
privileged: false
runAsNonRoot: false
runAsUser: 0
{{- else -}}
{{- toYaml .Values.securityContext -}}
{{- end -}}
{{- end -}}

{{- define "npa-publisher.validateEnrollment" -}}
{{- $mode := include "npa-publisher.enrollmentMode" . -}}
{{- if not (or (eq $mode "token") (eq $mode "api")) -}}
{{- fail "enrollment.mode must be either 'token' or 'api'" -}}
{{- end -}}
{{- $workloadType := include "npa-publisher.workloadType" . -}}
{{- if not (or (eq $workloadType "daemonset") (eq $workloadType "statefulset")) -}}
{{- fail "workload.type must be either 'daemonset' or 'statefulset'" -}}
{{- end -}}
{{- if and (eq $workloadType "statefulset") (ne $mode "api") -}}
{{- fail "workload.type=statefulset is only supported when enrollment.mode=api" -}}
{{- end -}}
{{- $networkingMode := include "npa-publisher.networkingMode" . -}}
{{- if not (or (eq $networkingMode "host") (eq $networkingMode "pod")) -}}
{{- fail "networking.mode must be either 'host' or 'pod'" -}}
{{- end -}}
{{- if and (eq $workloadType "statefulset") (ne $networkingMode "pod") -}}
{{- fail "workload.type=statefulset requires networking.mode=pod" -}}
{{- end -}}
{{- if eq $mode "api" -}}
{{- $_ := required "enrollment.commonName is required when enrollment.mode=api" .Values.enrollment.commonName -}}
{{- $_ := required "enrollment.api.baseUrl is required when enrollment.mode=api" .Values.enrollment.api.baseUrl -}}
{{- $_ := required "enrollment.api.existingSecret is required when enrollment.mode=api" .Values.enrollment.api.existingSecret -}}
{{- $_ := required "enrollment.api.tokenKey is required when enrollment.mode=api" .Values.enrollment.api.tokenKey -}}
{{- end -}}
{{- end -}}
