#!/usr/bin/env bash
# Trigger an Xcode Cloud workflow via the App Store Connect API.
#
# Flow (WWDC24 / App Store Connect API):
#   1. GET  /v1/ciWorkflows/{id}?include=repository  → repository id
#   2. GET  /v1/scmRepositories/{id}/gitReferences   → match branch or tag name
#   3. POST /v1/ciBuildRuns                           → start build
#
# Required env:
#   APP_STORE_CONNECT_ISSUER_ID
#   APP_STORE_CONNECT_KEY_ID
#   APP_STORE_CONNECT_PRIVATE_KEY   (PEM contents of the .p8 key)
#   XCODE_CLOUD_WORKFLOW_ID
#   GIT_REFERENCE_NAME              (branch or tag, e.g. main or v1.2.3)
#
# Optional:
#   GIT_REFERENCE_KIND              (BRANCH|TAG; default: auto — prefer TAG match, else BRANCH)
#   ASC_API_BASE                    (default https://api.appstoreconnect.apple.com)
#
# Exit 0 with a notice when credentials are missing (prep mode).
# Exit non-zero on API / config errors once credentials are present.

set -euo pipefail

ASC_API_BASE="${ASC_API_BASE:-https://api.appstoreconnect.apple.com}"

missing=()
[[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && missing+=(APP_STORE_CONNECT_ISSUER_ID)
[[ -z "${APP_STORE_CONNECT_KEY_ID:-}" ]] && missing+=(APP_STORE_CONNECT_KEY_ID)
[[ -z "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]] && missing+=(APP_STORE_CONNECT_PRIVATE_KEY)
[[ -z "${XCODE_CLOUD_WORKFLOW_ID:-}" ]] && missing+=(XCODE_CLOUD_WORKFLOW_ID)
[[ -z "${GIT_REFERENCE_NAME:-}" ]] && missing+=(GIT_REFERENCE_NAME)

if ((${#missing[@]} > 0)); then
  echo "::notice::Xcode Cloud trigger not configured yet (missing: ${missing[*]})."
  echo "Add App Store Connect API secrets + XCODE_CLOUD_WORKFLOW_ID when Xcode Cloud is ready."
  echo "See Docs/DevWorkflow.md § GitHub Actions / Xcode Cloud."
  exit 0
fi

# Normalize .p8: allow literal \n in GitHub secrets.
PRIVATE_KEY_PEM="${APP_STORE_CONNECT_PRIVATE_KEY//$'\r'/}"
if [[ "$PRIVATE_KEY_PEM" != *"BEGIN PRIVATE KEY"* ]]; then
  PRIVATE_KEY_PEM="$(printf '%b' "$PRIVATE_KEY_PEM")"
fi

export APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_ID
export APP_STORE_CONNECT_PRIVATE_KEY="$PRIVATE_KEY_PEM"

TOKEN="$(
  python3 -c '
import calendar, os, time
try:
    import jwt
except ImportError as exc:
    raise SystemExit("PyJWT required: pip install '\''PyJWT[crypto]'\''") from exc
issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
key_id = os.environ["APP_STORE_CONNECT_KEY_ID"]
key_pem = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]
now = calendar.timegm(time.gmtime())
payload = {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"}
print(jwt.encode(payload, key_pem, algorithm="ES256", headers={"kid": key_id}))
'
)"

asc_get() {
  curl -fsS \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "$1"
}

asc_post() {
  curl -fsS -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "$1"
}

echo "Resolving repository for workflow ${XCODE_CLOUD_WORKFLOW_ID}…"
workflow_json="$(asc_get "${ASC_API_BASE}/v1/ciWorkflows/${XCODE_CLOUD_WORKFLOW_ID}?include=repository")"

repo_id="$(
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["relationships"]["repository"]["data"]["id"])' \
    <<<"$workflow_json"
)"
echo "Repository id: ${repo_id}"

echo "Looking up git reference '${GIT_REFERENCE_NAME}'…"
ref_id=""
ref_kind_found=""
next_url="${ASC_API_BASE}/v1/scmRepositories/${repo_id}/gitReferences?limit=200"
export GIT_REFERENCE_NAME
export GIT_REFERENCE_KIND="${GIT_REFERENCE_KIND:-}"

while [[ -n "$next_url" ]]; do
  page_json="$(asc_get "$next_url")"
  match="$(
    python3 -c '
import json, os, sys
doc = json.load(sys.stdin)
want = os.environ["GIT_REFERENCE_NAME"]
prefer = os.environ.get("GIT_REFERENCE_KIND", "").upper()
candidates = []
for item in doc.get("data", []):
    attrs = item.get("attributes") or {}
    if attrs.get("name") != want:
        continue
    kind = (attrs.get("kind") or "").upper()
    candidates.append((kind, item["id"]))
if not candidates:
    raise SystemExit(0)
if prefer:
    for kind, rid in candidates:
        if kind == prefer:
            print(f"{kind}\t{rid}")
            raise SystemExit(0)
for kind, rid in candidates:
    if kind == "TAG":
        print(f"{kind}\t{rid}")
        raise SystemExit(0)
kind, rid = candidates[0]
print(f"{kind}\t{rid}")
' <<<"$page_json"
  )"
  if [[ -n "$match" ]]; then
    ref_kind_found="${match%%$'\t'*}"
    ref_id="${match#*$'\t'}"
    break
  fi
  next_url="$(
    python3 -c 'import json,sys; print((json.load(sys.stdin).get("links") or {}).get("next") or "")' \
      <<<"$page_json"
  )"
done

if [[ -z "$ref_id" ]]; then
  echo "::error::No scmGitReference named '${GIT_REFERENCE_NAME}' on repository ${repo_id}."
  exit 1
fi
echo "Using ${ref_kind_found} reference id: ${ref_id}"

body="$(
  XCODE_CLOUD_WORKFLOW_ID="$XCODE_CLOUD_WORKFLOW_ID" REF_ID="$ref_id" python3 -c '
import json, os
print(json.dumps({
  "data": {
    "type": "ciBuildRuns",
    "attributes": {},
    "relationships": {
      "workflow": {
        "data": {"type": "ciWorkflows", "id": os.environ["XCODE_CLOUD_WORKFLOW_ID"]}
      },
      "sourceBranchOrTag": {
        "data": {"type": "scmGitReferences", "id": os.environ["REF_ID"]}
      }
    }
  }
}))
'
)"

echo "Starting Xcode Cloud build…"
resp="$(asc_post "${ASC_API_BASE}/v1/ciBuildRuns" "$body")"

python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
a = d.get("attributes") or {}
print(
    "Started ciBuildRun {id} (number={number}, progress={progress})".format(
        id=d["id"],
        number=a.get("number"),
        progress=a.get("executionProgress"),
    )
)
' <<<"$resp"
