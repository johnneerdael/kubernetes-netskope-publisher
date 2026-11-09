#!/bin/bash
# Token-mode enrollment for the `enroll` init container.
#
# The registration token is delivered pre-provisioned (for example by the
# Netskope Terraform provider's netskope_npa_publisher_token resource) through
# a Kubernetes Secret, so this path needs no Netskope API credential.
#
# Behaviour:
#   - NPA_TOKEN_KEY_BY selects which Secret key this pod enrolls with:
#       single  -> <token dir>/token           (one Publisher per release)
#       ordinal -> <token dir>/<ordinal>       (StatefulSet replica N uses key
#                                               "N", one token per replica)
#       node    -> <token dir>/<NODE_NAME>     (DaemonSet, one token per node)
#   - Registration tokens are single-use. When the resources volume already
#     holds enrollment artifacts for the current token, enrollment is skipped.
#   - A SHA-256 fingerprint of the token used for enrollment is kept in the
#     resources volume. If a different token is delivered (token rotation),
#     the Publisher re-enrolls with it; on failure the previous state is
#     restored and the init container fails loudly.

set -euo pipefail

RESOURCES_DIR="/home/resources"
TOKEN_DIR="${NPA_TOKEN_DIR:-/tmp/token}"
TOKEN_STAMP="${RESOURCES_DIR}/.k8s-registration-token.sha256"
BACKUP_DIR="${RESOURCES_DIR}/.k8s-reenroll-backup"
# Present only while the wizard runs. If a run is interrupted (crash, OOM,
# SIGKILL), the next start finds it and discards the partial state instead
# of mistaking it for a finished enrollment.
ENROLL_MARKER="${RESOURCES_DIR}/.k8s-enrollment-in-progress"
# Files the enrollment wizard and the first bootstrap write for one Publisher
# identity. nsconfig.json is included so bootstrap re-pulls it after a
# re-enrollment instead of reusing configuration for the previous identity.
ENROLLMENT_STATE=(publisherid sslcert settings.json nsconfig.json stitcher tenant)

log() {
  echo "[npa-token-enrollment] $*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

# A complete enrollment has every artifact k8s-bootstrap.sh waits for.
have_enrollment_artifacts() {
  test -s "${RESOURCES_DIR}/publisherid" \
    && test -s "${RESOURCES_DIR}/sslcert/agent.key" \
    && test -s "${RESOURCES_DIR}/sslcert/agent.pem" \
    && test -s "${RESOURCES_DIR}/sslcert/tenantca.pem" \
    && test -s "${RESOURCES_DIR}/settings.json"
}

have_any_enrollment_state() {
  local item
  for item in "${ENROLLMENT_STATE[@]}"; do
    [ -e "${RESOURCES_DIR}/${item}" ] && return 0
  done
  return 1
}

discard_enrollment_state() {
  local item
  for item in "${ENROLLMENT_STATE[@]}"; do
    rm -rf "${RESOURCES_DIR:?}/${item}"
  done
}

token_fingerprint() {
  printf '%s' "$1" | sha256sum | awk '{ print $1 }'
}

backup_enrollment_state() {
  local item
  rm -rf "${BACKUP_DIR}"
  mkdir -p "${BACKUP_DIR}"
  for item in "${ENROLLMENT_STATE[@]}"; do
    if [ -e "${RESOURCES_DIR}/${item}" ]; then
      mv "${RESOURCES_DIR}/${item}" "${BACKUP_DIR}/${item}"
    fi
  done
  if [ -e "${TOKEN_STAMP}" ]; then
    mv "${TOKEN_STAMP}" "${BACKUP_DIR}/token.sha256"
  fi
}

restore_enrollment_state() {
  local item
  [ -d "${BACKUP_DIR}" ] || return 0
  log "Restoring previous enrollment state"
  # Drop everything the failed attempt wrote, including files the previous
  # enrollment did not have, before putting the backup back.
  discard_enrollment_state
  for item in "${ENROLLMENT_STATE[@]}"; do
    if [ -e "${BACKUP_DIR}/${item}" ]; then
      mv "${BACKUP_DIR}/${item}" "${RESOURCES_DIR}/${item}"
    fi
  done
  if [ -e "${BACKUP_DIR}/token.sha256" ]; then
    mv "${BACKUP_DIR}/token.sha256" "${TOKEN_STAMP}"
  fi
  rm -rf "${BACKUP_DIR}"
}

# Undo a failed or interrupted attempt: restore the previous enrollment if one
# was backed up, otherwise remove the partial state so it is never adopted.
roll_back_attempt() {
  if [ -d "${BACKUP_DIR}" ]; then
    restore_enrollment_state
  else
    log "Removing partial state from the failed enrollment attempt"
    discard_enrollment_state
  fi
  rm -f "${ENROLL_MARKER}"
}

TOKEN_KEY_BY="${NPA_TOKEN_KEY_BY:-single}"
case "${TOKEN_KEY_BY}" in
  single)
    token_key="token"
    token_source="the single registration token"
    ;;
  ordinal)
    [ -n "${POD_NAME:-}" ] || fail "POD_NAME is not set; per-replica token lookup needs the downward API"
    # StatefulSet pods are named <statefulset>-<ordinal>.
    token_key="${POD_NAME##*-}"
    case "${token_key}" in
      ''|*[!0-9]*) fail "Cannot derive a StatefulSet ordinal from pod name '${POD_NAME}'" ;;
    esac
    token_source="Secret key '${token_key}' (replica ${token_key})"
    ;;
  node)
    [ -n "${NODE_NAME:-}" ] || fail "NODE_NAME is not set; per-node token lookup needs the downward API"
    token_key="${NODE_NAME}"
    token_source="Secret key '${token_key}' (node ${NODE_NAME})"
    ;;
  *)
    fail "Unsupported NPA_TOKEN_KEY_BY=${TOKEN_KEY_BY}; expected single, ordinal, or node"
    ;;
esac
token_file="${TOKEN_DIR}/${token_key}"

# Recover from an interrupted previous run.
if [ -e "${ENROLL_MARKER}" ]; then
  if [ -s "${TOKEN_STAMP}" ] && have_enrollment_artifacts; then
    # The stamp is written only after a successful wizard run (and is moved
    # into the backup while an attempt runs), so the run finished and was
    # interrupted only during cleanup.
    rm -rf "${BACKUP_DIR}"
    rm -f "${ENROLL_MARKER}"
  else
    log "Found an interrupted enrollment attempt"
    roll_back_attempt
  fi
elif [ -d "${BACKUP_DIR}" ] && ! have_enrollment_artifacts; then
  restore_enrollment_state
fi

if [ ! -s "${token_file}" ]; then
  case "${TOKEN_KEY_BY}" in
    ordinal)
      fail "No registration token found for replica ${token_key}. The token Secret needs one key per replica (\"0\" .. \"N-1\"); issue one netskope_npa_publisher_token per replica in Terraform, or lower workload.replicas."
      ;;
    node)
      fail "No registration token found for node '${NODE_NAME}'. Add a '${NODE_NAME}' key to the token Secret (one netskope_npa_publisher_token per node in Terraform), or keep this node out of the DaemonSet with nodeSelector/affinity."
      ;;
  esac
  fail "Registration token is empty or missing. Check registrationToken.value or registrationToken.existingSecret/existingSecretKey."
fi

registration_token="$(cat "${token_file}")"
# Tolerate CRLF or trailing whitespace from hand-made Secrets.
registration_token="${registration_token//$'\r'/}"
registration_token="${registration_token%"${registration_token##*[![:space:]]}"}"
[ -n "${registration_token}" ] || fail "Registration token is blank (${token_source})"
current_fingerprint="$(token_fingerprint "${registration_token}")"

if have_enrollment_artifacts; then
  if [ ! -s "${TOKEN_STAMP}" ]; then
    # Enrolled before token fingerprinting existed. Adopt the current token so
    # a later rotation is detected, and keep the working identity.
    log "Existing enrollment found without a recorded token fingerprint; adopting the current token and skipping enrollment"
    printf '%s\n' "${current_fingerprint}" > "${TOKEN_STAMP}"
    exit 0
  fi

  if [ "$(cat "${TOKEN_STAMP}")" = "${current_fingerprint}" ]; then
    log "Already enrolled with the current registration token; skipping enrollment"
    exit 0
  fi

  log "Registration token changed since the last enrollment; re-enrolling with the new token"
  backup_enrollment_state
elif have_any_enrollment_state; then
  # Incomplete state (for example left by an older chart version after a
  # failed enrollment) is not a usable identity. Start from a clean slate.
  log "Discarding incomplete enrollment state before enrolling"
  discard_enrollment_state
  rm -f "${TOKEN_STAMP}"
fi

log "Running Publisher enrollment wizard (${token_source})"
cd /home
touch "${ENROLL_MARKER}"
wizard_status=0
/home/npa_publisher_wizard -token "${registration_token}" || wizard_status=$?
unset registration_token

if [ "${wizard_status}" -ne 0 ] || ! have_enrollment_artifacts; then
  roll_back_attempt
  fail "Publisher enrollment failed (wizard exit ${wizard_status}). Registration tokens are single-use: if this token was already consumed (for example because the pod lost its state on emptyDir storage), issue a new token, e.g. 'terraform apply -replace=netskope_npa_publisher_token.<name>', then restart the pod."
fi

printf '%s\n' "${current_fingerprint}" > "${TOKEN_STAMP}"
rm -rf "${BACKUP_DIR}"
rm -f "${ENROLL_MARKER}"
log "Enrollment complete"
