#!/bin/bash
# check-observability-placement.sh — the offline deployment check for the AKS
# observability path (specs/002-azure-observability-stack, FR-011).
#
# A thin wrapper around Python 3 + PyYAML (yq is not in install-deps.sh).
# PyYAML comes from the system python3 when it has it; otherwise the check
# runs under `uv run --with pyyaml` (uv is in `make install`'s tool list), so
# a plain `make install` is enough for `make lint` to pass. It reads each chart-values/manifest file and asserts the
# placement at the exact key path each chart actually reads — not a text
# match — so a placement key the chart silently ignores fails here
# (research.md finding 16: the new Loki chart ignores top-level
# nodeSelector/tolerations entirely).
#
# Checked files:
#   - infra/azure/chart-values/loki.yaml       (new, AKS-specific)
#   - infra/azure/chart-values/alloy.yaml      (new, AKS-specific)
#   - monitoring/chart-values/prometheus-values.yaml (shared; wired into the
#     AKS chain unmodified)
#   - monitoring/istio-observability-addons/kiali.yaml (shared; applied on
#     the AKS path by setup-aks-kiali)
#
# The two per-machine helpers (Alloy DaemonSet, node-exporter) run on every
# pool by spec decision (Clarification 2026-10-05), so neither is required to
# select o11y — Alloy only proves it tolerates every taint; node-exporter is
# not asserted at all.
#
# Prints one PASS/FAIL line per file (plus a detail line per failure) and
# exits non-zero when any check fails. No cluster needed.

set -u

_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${_repo_root}" ]; then
    _repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL cannot run: python3 not found (install it, then re-run)." >&2
    exit 1
fi

# Pick an interpreter that can `import yaml`.
if python3 -c 'import yaml' >/dev/null 2>&1; then
    _python=(python3)
elif command -v uv >/dev/null 2>&1; then
    _python=(uv run --quiet --no-project --with pyyaml python3)
else
    echo "FAIL cannot run: the python3 yaml module is not installed and uv is not available (run 'make install', or install PyYAML, then re-run)." >&2
    exit 1
fi

"${_python[@]}" - "${_repo_root}" <<'PYEOF'
import sys
import os

try:
    import yaml
except ImportError:
    print("FAIL cannot run: the python3 yaml module is not installed (install PyYAML, then re-run).")
    sys.exit(1)

root = sys.argv[1]
failures = 0


def check_file(relpath, run_checks):
    """Print one PASS/FAIL line per file; run_checks returns a list of
    problem strings (empty means the file passes)."""
    global failures
    path = os.path.join(root, relpath)
    if not os.path.isfile(path):
        print(f"FAIL {relpath}: file not found")
        failures += 1
        return
    try:
        problems = run_checks(path)
    except (OSError, ValueError) as exc:
        problems = [f"could not be read/parsed: {exc}"]
    if problems:
        print(f"FAIL {relpath}")
        for problem in problems:
            print(f"  - {problem}")
        failures += 1
    else:
        print(f"PASS {relpath}")


def select_toleration_ok(tolerations):
    """True when one toleration entry admits the o11y=true:NoSchedule taint
    (a key/equal/value entry) or admits every taint (operator: Exists)."""
    if not isinstance(tolerations, list):
        return False
    for t in tolerations:
        if not isinstance(t, dict):
            continue
        if t.get("operator") == "Exists":
            return True
        if (t.get("key") == "o11y" and t.get("value") == "true"
                and t.get("effect") == "NoSchedule"):
            return True
    return False


def pod_spec_problems(pod_spec):
    """Problems in a pod spec that must select and tolerate o11y."""
    problems = []
    if not isinstance(pod_spec, dict):
        return ["pod spec is missing entirely"]
    selector = pod_spec.get("nodeSelector")
    if not isinstance(selector, dict) or selector.get("workload") != "o11y":
        problems.append("nodeSelector does not select workload=o11y "
                        "(or uses a key path the chart ignores)")
    if not select_toleration_ok(pod_spec.get("tolerations")):
        problems.append("tolerations do not admit the o11y=true:NoSchedule taint")
    return problems


def check_loki(path):
    doc = yaml.safe_load(open(path))
    if not isinstance(doc, dict):
        return ["top-level document is not a mapping"]
    problems = []
    single = doc.get("singleBinary")
    if not isinstance(single, dict):
        return ["singleBinary key is missing — placement at singleBinary.* "
                "is what chart 18.13.7 reads (there are no top-level keys)"]
    selector = single.get("nodeSelector")
    if not isinstance(selector, dict) or selector.get("workload") != "o11y":
        problems.append("singleBinary.nodeSelector does not select workload=o11y")
    tolerations = single.get("tolerations")
    if not isinstance(tolerations, list) or not any(
            isinstance(t, dict) and t.get("key") == "o11y"
            and t.get("effect") == "NoSchedule" for t in tolerations):
        problems.append("singleBinary.tolerations lacks the o11y/NoSchedule entry")
    return problems


def check_alloy(path):
    doc = yaml.safe_load(open(path))
    if not isinstance(doc, dict):
        return ["top-level document is not a mapping"]
    controller = doc.get("controller")
    if not isinstance(controller, dict):
        return ["controller key is missing — this chart's placement lives "
                "under controller.* (there are no top-level keys)"]
    tolerations = controller.get("tolerations")
    if not isinstance(tolerations, list) or not any(
            isinstance(t, dict) and t.get("operator") == "Exists"
            for t in tolerations):
        problems = (["controller.tolerations lacks an operator: Exists entry "
                     "(a per-machine helper must run on every pool)"])
        return problems
    return []


def check_otel(path):
    """The optional collector's values carry top-level nodeSelector and
    tolerations (a single Deployment, not a per-machine helper)."""
    doc = yaml.safe_load(open(path))
    if not isinstance(doc, dict):
        return ["top-level document is not a mapping"]
    return pod_spec_problems(doc)


PROMETHEUS_SECTIONS = [
    ("prometheus.prometheusSpec", ["prometheus", "prometheusSpec"]),
    ("alertmanager.alertmanagerSpec", ["alertmanager", "alertmanagerSpec"]),
    ("grafana", ["grafana"]),
    ("prometheusOperator", ["prometheusOperator"]),
    ("kube-state-metrics", ["kube-state-metrics"]),
]


def check_prometheus(path):
    doc = yaml.safe_load(open(path))
    if not isinstance(doc, dict):
        return ["top-level document is not a mapping"]
    problems = []
    for label, keypath in PROMETHEUS_SECTIONS:
        section = doc
        for key in keypath:
            section = section.get(key) if isinstance(section, dict) else None
            if section is None:
                break
        if not isinstance(section, dict):
            problems.append(f"{label} key is missing entirely")
            continue
        for problem in pod_spec_problems(section):
            problems.append(f"{label}: {problem}")
    return problems


def check_kiali(path):
    """kiali.yaml is a pre-rendered multi-document manifest; find the
    Deployment named kiali and check its pod template spec."""
    problems = []
    deployment = None
    for doc in yaml.safe_load_all(open(path)):
        if (isinstance(doc, dict) and doc.get("kind") == "Deployment"
                and doc.get("metadata", {}).get("name") == "kiali"):
            deployment = doc
            break
    if deployment is None:
        return ["no Deployment named kiali found in the manifest"]
    spec = deployment.get("spec", {})
    template_spec = spec.get("template", {}).get("spec", {})
    for problem in pod_spec_problems(template_spec):
        problems.append(f"deployment/kiali pod spec: {problem}")
    return problems


check_file("infra/azure/chart-values/loki.yaml", check_loki)
check_file("infra/azure/chart-values/alloy.yaml", check_alloy)
check_file("infra/azure/chart-values/otel-collector.yaml", check_otel)
check_file("monitoring/chart-values/prometheus-values.yaml", check_prometheus)
check_file("infra/azure/kiali/kiali.yaml", check_kiali)

if failures:
    print(f"placement check: {failures} file(s) failed")
    sys.exit(1)
print("placement check: all files select and tolerate the o11y pool correctly")
sys.exit(0)
PYEOF
