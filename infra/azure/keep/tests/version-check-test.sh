#!/usr/bin/env bash
# version-check-test.sh: offline tests of require_server_version in lib-uninstall-test.sh, with a stub kubectl
# first on PATH. No cluster call and no credentials.
#
# The stub rejects "kubectl version -o jsonpath=...", which is what kubectl does on a real cluster. It answers
# "kubectl get --raw /version" with a real response (fixtures/version-k3s-v1.36.4.json, read from the k3d cluster)
# or with a case-specific response. The library is sourced with set -u and set -C, like the real scripts.
#
# Cases:
#   1. real /version from k3s v1.36.4                 -> accepted
#   2. minor "34+" (a GKE-style value, synthetic)     -> accepted (non-digits stripped)
#   3. minor "29", below the 1.30 minimum             -> INCONCLUSIVE
#   4. discovery fails (kubectl get --raw errors)     -> INCONCLUSIVE
#   5. response has no major or minor key             -> INCONCLUSIVE
#
# LOG_CAPTURE_LIB-style override: VERSION_CHECK_LIB may name another copy of the library. It is used only for
# the regression check, which must fail on the old copy and pass on the current one.
# Exit 0 when every case behaves as expected, 1 otherwise.

set -u
set -C

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 2
LIB="${VERSION_CHECK_LIB:-$DIR/lib-uninstall-test.sh}"
# shellcheck disable=SC1090 # the path is VERSION_CHECK_LIB (regression check) or the library beside this file
if ! . "$LIB"; then
  echo "cannot load the library from $LIB" >&2
  exit 2
fi
REAL_VERSION="$DIR/fixtures/version-k3s-v1.36.4.json"
W="$(mktemp -d "${TMPDIR:-/tmp}/version-check.XXXXXX")" || exit 2
STUB="$W/bin"
mkdir -p "$STUB"
CASES_PASSED=0
CASES_FAILED=0

cat > "$STUB/kubectl" <<'SH'
#!/usr/bin/env bash
# Stub kubectl for the version check. Records every call in STUB_DIR.
echo "$*" >> "$STUB_DIR/calls.log"
case "$1 $2" in
  "get --raw")
    if [ "$3" = /version ] && [ -r "$STUB_DIR/version.json" ]; then
      cat "$STUB_DIR/version.json"
      exit 0
    fi
    echo "Error from server (Forbidden): the server could not be reached" >&2
    exit 1
    ;;
  "version -o")
    # Real shape of "kubectl version -o json": clientVersion and serverVersion. Not used by the fixed code.
    echo '{"clientVersion":{"major":"1","minor":"34"},"serverVersion":{"major":"1","minor":"36"}}'
    exit 0
    ;;
  version*)
    # kubectl version rejects every output format except yaml and json.
    echo "error: --output must be 'yaml' or 'json'" >&2
    exit 1
    ;;
esac
echo "stub: unexpected call: $*" >&2
exit 9
SH
chmod +x "$STUB/kubectl"

# make_version_json MINOR: a /version response with the given minor, from the real fixture.
make_version_json() {
  sed "s/\"minor\": \"36\"/\"minor\": \"$1\"/" "$REAL_VERSION"
}

# run_case NAME WANT(accepted|inconclusive) VERSION_FILE_CONTENT_MODE
# shellcheck disable=SC2034 # INCS and FAILS are read by the sourced library functions
run_case() {
  local name="$1" want="$2" mode="$3" d rc got
  d="$W/case-$(echo "$name" | tr -c 'a-z0-9' '_')"
  rm -rf "$d"
  mkdir -p "$d"
  case "$mode" in
    real) cp "$REAL_VERSION" "$d/version.json" ;;
    minor34plus) make_version_json '34+' > "$d/version.json" ;;
    minor29) make_version_json '29' > "$d/version.json" ;;
    discovery_fail) : ;;
    no_keys) printf '{\n  "gitVersion": "v1.36.4+k3s1"\n}\n' > "$d/version.json" ;;
  esac
  export STUB_DIR="$d"
  # shellcheck disable=SC2034 # EV is read by the sourced library functions
  EV="$d"
  INCS=""
  FAILS=""
  PATH="$STUB:$PATH"
  require_server_version
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$INCS" ]; then got=accepted; else got=inconclusive; fi
  if [ "$got" = "$want" ]; then
    CASES_PASSED=$((CASES_PASSED + 1))
    echo "pass   $name (want $want, got $got, rc=$rc)"
  else
    CASES_FAILED=$((CASES_FAILED + 1))
    echo "FAIL   $name (want $want, got $got, rc=$rc)"
  fi
  if [ -n "$INCS" ]; then echo "       reason: $INCS"; fi
  return 0
}

echo "library under test: $LIB"
run_case "1 real /version k3s v1.36.4" accepted real
run_case "2 minor 34+ (synthetic GKE-style)" accepted minor34plus
run_case "3 minor 29 below the minimum" inconclusive minor29
run_case "4 discovery fails" inconclusive discovery_fail
run_case "5 response has no major or minor" inconclusive no_keys

rm -rf "$W"
echo
echo "cases passed: $CASES_PASSED, cases failed: $CASES_FAILED"
if [ "$CASES_FAILED" -eq 0 ]; then exit 0; fi
exit 1
