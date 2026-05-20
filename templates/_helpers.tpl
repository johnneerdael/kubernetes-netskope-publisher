{{- define "kubernetes-netskope-publisher.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "kubernetes-netskope-publisher.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "kubernetes-netskope-publisher.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.labels" -}}
helm.sh/chart: {{ include "kubernetes-netskope-publisher.chart" . }}
app.kubernetes.io/name: {{ include "kubernetes-netskope-publisher.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "kubernetes-netskope-publisher.enrollmentMode" -}}
{{- default "api" .Values.enrollment.mode -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.isApiEnrollment" -}}
{{- if eq (include "kubernetes-netskope-publisher.enrollmentMode" .) "api" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.apiAuthMode" -}}
{{- default "token" .Values.enrollment.api.authMode -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.isApiTokenAuth" -}}
{{- if eq (include "kubernetes-netskope-publisher.apiAuthMode" .) "token" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.isApiOauth2Auth" -}}
{{- if eq (include "kubernetes-netskope-publisher.apiAuthMode" .) "oauth2" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.workloadType" -}}
{{- default "daemonset" .Values.workload.type -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.isStatefulSet" -}}
{{- if eq (include "kubernetes-netskope-publisher.workloadType" .) "statefulset" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.networkingMode" -}}
{{- default "pod" .Values.networking.mode -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.isPodNetworking" -}}
{{- if eq (include "kubernetes-netskope-publisher.networkingMode" .) "pod" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.hostNetwork" -}}
{{- if include "kubernetes-netskope-publisher.isPodNetworking" . -}}false{{- else -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.dnsPolicy" -}}
{{- if include "kubernetes-netskope-publisher.isPodNetworking" . -}}ClusterFirst{{- else -}}ClusterFirstWithHostNet{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.securityContext" -}}
{{- if include "kubernetes-netskope-publisher.isPodNetworking" . -}}
allowPrivilegeEscalation: false
capabilities:
  add:
    - NET_ADMIN
    - NET_RAW
privileged: false
runAsNonRoot: false
runAsUser: 0
{{- else -}}
allowPrivilegeEscalation: true
capabilities:
  add:
    - NET_ADMIN
    - NET_RAW
privileged: true
runAsNonRoot: false
runAsUser: 0
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.validateEnrollment" -}}
{{- $mode := include "kubernetes-netskope-publisher.enrollmentMode" . -}}
{{- if not (or (eq $mode "token") (eq $mode "api")) -}}
{{- fail "enrollment.mode must be either 'token' or 'api'" -}}
{{- end -}}
{{- $workloadType := include "kubernetes-netskope-publisher.workloadType" . -}}
{{- if not (or (eq $workloadType "daemonset") (eq $workloadType "statefulset")) -}}
{{- fail "workload.type must be either 'daemonset' or 'statefulset'" -}}
{{- end -}}
{{- if and (eq $workloadType "statefulset") (ne $mode "api") -}}
{{- fail "workload.type=statefulset is only supported when enrollment.mode=api" -}}
{{- end -}}
{{- $networkingMode := include "kubernetes-netskope-publisher.networkingMode" . -}}
{{- if not (or (eq $networkingMode "host") (eq $networkingMode "pod")) -}}
{{- fail "networking.mode must be either 'host' or 'pod'" -}}
{{- end -}}
{{- if and (eq $workloadType "statefulset") (ne $networkingMode "pod") -}}
{{- fail "workload.type=statefulset requires networking.mode=pod" -}}
{{- end -}}
{{- if and (eq $networkingMode "pod") .Values.bind.forwarders -}}
{{- fail "bind.forwarders is only supported when networking.mode=host; configure Kubernetes CoreDNS forwarding for private domains in pod network mode" -}}
{{- end -}}
{{- if eq $mode "api" -}}
{{- $_ := required "enrollment.commonName is required when enrollment.mode=api" .Values.enrollment.commonName -}}
{{- $_ := required "enrollment.api.baseUrl is required when enrollment.mode=api" .Values.enrollment.api.baseUrl -}}
{{- $apiAuthMode := include "kubernetes-netskope-publisher.apiAuthMode" . -}}
{{- if not (or (eq $apiAuthMode "token") (eq $apiAuthMode "oauth2")) -}}
{{- fail "enrollment.api.authMode must be either 'token' or 'oauth2'" -}}
{{- end -}}
{{- if eq $apiAuthMode "token" -}}
{{- $_ := required "enrollment.api.existingSecret is required when enrollment.mode=api" .Values.enrollment.api.existingSecret -}}
{{- $_ := required "enrollment.api.tokenKey is required when enrollment.mode=api" .Values.enrollment.api.tokenKey -}}
{{- end -}}
{{- if eq $apiAuthMode "oauth2" -}}
{{- $_ := required "enrollment.api.oauth2.tokenUrl is required when enrollment.api.authMode=oauth2" .Values.enrollment.api.oauth2.tokenUrl -}}
{{- $_ := required "enrollment.api.oauth2.existingSecret is required when enrollment.api.authMode=oauth2" .Values.enrollment.api.oauth2.existingSecret -}}
{{- $_ := required "enrollment.api.oauth2.clientIdKey is required when enrollment.api.authMode=oauth2" .Values.enrollment.api.oauth2.clientIdKey -}}
{{- $_ := required "enrollment.api.oauth2.clientSecretKey is required when enrollment.api.authMode=oauth2" .Values.enrollment.api.oauth2.clientSecretKey -}}
{{- end -}}
{{- end -}}
{{- end -}}
