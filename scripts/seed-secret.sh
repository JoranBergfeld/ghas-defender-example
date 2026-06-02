#!/usr/bin/env bash
set -euo pipefail

target_file="src/backend/src/main/resources/application-local.yml"

# Generate a Stripe live secret key. GitHub Secret Scanning reliably detects
# the "Stripe API Key" pattern `sk_live_<24 base62 chars>` for push protection
# without any checksum requirement. AWS and GitHub PAT patterns embed checksums
# that GitHub validates server-side, so randomly generated values do not
# trigger the detector — Stripe keys give us a deterministic push-protection
# rejection for the demo.
stripe_key="$(python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits
print("sk_live_" + "".join(secrets.choice(alphabet) for _ in range(24)))
PY
)"

python3 - "${target_file}" "${stripe_key}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
stripe_key = sys.argv[2]
label = " # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md"

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    lines = path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

# Drop any prior demo block (header + keys) so re-runs stay idempotent.
filtered = []
skip_demo = False
known_keys = (
    "  awsAccessKeyId:",
    "  awsSecretAccessKey:",
    "  leakedGitHubPat:",
    "  stripeLiveKey:",
)
for line in lines:
    if line.startswith("# Local-only demo values"):
        skip_demo = True
        continue
    if skip_demo:
        if line.startswith("demo:") or line.startswith(known_keys):
            continue
        if line.strip() == "":
            skip_demo = False
            continue
        skip_demo = False
    filtered.append(line)

if filtered and filtered[-1] != "":
    filtered.append("")

filtered.extend([
    "# Local-only demo values; never used by the cloud profile.",
    "demo:",
    f'  stripeLiveKey: "{stripe_key}"{label}',
])

path.write_text("\n".join(filtered) + "\n", encoding="utf-8")
PY

cat <<EOF
WARNING: wrote a Stripe live secret key for the GHAS push-protection demo.
Key written to: ${target_file}
Key value:    ${stripe_key}

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
EOF
