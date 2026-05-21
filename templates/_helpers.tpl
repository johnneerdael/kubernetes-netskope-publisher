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

{{- define "kubernetes-netskope-publisher.isLwipNetworking" -}}
{{- if eq (include "kubernetes-netskope-publisher.networkingMode" .) "lwip" -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.publisherImageRepository" -}}
{{- if include "kubernetes-netskope-publisher.isLwipNetworking" . -}}
{{- .Values.lwipImage.repository -}}
{{- else -}}
{{- .Values.image.repository -}}
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.publisherImageTag" -}}
{{- if include "kubernetes-netskope-publisher.isLwipNetworking" . -}}
{{- .Values.lwipImage.tag -}}
{{- else -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.publisherImagePullPolicy" -}}
{{- if include "kubernetes-netskope-publisher.isLwipNetworking" . -}}
{{- .Values.lwipImage.pullPolicy | default .Values.image.pullPolicy -}}
{{- else -}}
{{- .Values.image.pullPolicy -}}
{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.publisherImage" -}}
{{- printf "%s:%s" (include "kubernetes-netskope-publisher.publisherImageRepository" .) (include "kubernetes-netskope-publisher.publisherImageTag" .) -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.hostNetwork" -}}
{{- if or (include "kubernetes-netskope-publisher.isPodNetworking" .) (include "kubernetes-netskope-publisher.isLwipNetworking" .) -}}false{{- else -}}true{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.dnsPolicy" -}}
{{- if or (include "kubernetes-netskope-publisher.isPodNetworking" .) (include "kubernetes-netskope-publisher.isLwipNetworking" .) -}}ClusterFirst{{- else -}}ClusterFirstWithHostNet{{- end -}}
{{- end -}}

{{- define "kubernetes-netskope-publisher.securityContext" -}}
{{- if include "kubernetes-netskope-publisher.isLwipNetworking" . -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
privileged: false
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
{{- else if include "kubernetes-netskope-publisher.isPodNetworking" . -}}
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

{{- define "kubernetes-netskope-publisher.podSecurityContext" -}}
{{- if include "kubernetes-netskope-publisher.isLwipNetworking" . -}}
fsGroup: 65532
fsGroupChangePolicy: OnRootMismatch
runAsGroup: 65532
runAsNonRoot: true
runAsUser: 65532
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
{{- if not (or (eq $networkingMode "host") (eq $networkingMode "pod") (eq $networkingMode "lwip")) -}}
{{- fail "networking.mode must be one of 'host', 'pod', or 'lwip'" -}}
{{- end -}}
{{- if and (eq $workloadType "statefulset") (not (or (eq $networkingMode "pod") (eq $networkingMode "lwip"))) -}}
{{- fail "workload.type=statefulset requires networking.mode=pod or networking.mode=lwip" -}}
{{- end -}}
{{- if and (ne $networkingMode "host") .Values.bind.forwarders -}}
{{- fail "bind.forwarders is only supported when networking.mode=host; configure Kubernetes CoreDNS forwarding for private domains in pod or lwip mode" -}}
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
