#!/usr/bin/env bash
set -euo pipefail

target_file="src/backend/src/main/resources/application-local.yml"

# Use canonical AWS EXAMPLE keys. GitHub Secret Scanning reliably detects the
# pattern "Amazon AWS Access Key ID" + "Amazon AWS Secret Access Key" without
# any provider-side checksum requirement, so push protection will reject the
# push. The "EXAMPLE" suffix on the secret marks it as a documented test value
# that AWS itself publishes for tutorials.
access_key_id="AKIAIOSFODNN7EXAMPLE"
secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

python3 - "${target_file}" "${access_key_id}" "${secret_access_key}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
access_key_id = sys.argv[2]
secret_access_key = sys.argv[3]
label = " # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md"

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    lines = path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

# Drop any prior demo block (header + keys) so re-runs stay idempotent.
filtered = []
skip_demo = False
for line in lines:
    if line.startswith("# Local-only demo values"):
        skip_demo = True
        continue
    if skip_demo:
        if line.startswith(("demo:", "  awsAccessKeyId:", "  awsSecretAccessKey:", "  leakedGitHubPat:")):
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
    f'  awsAccessKeyId: "{access_key_id}"{label}',
    f'  awsSecretAccessKey: "{secret_access_key}"{label}',
])

path.write_text("\n".join(filtered) + "\n", encoding="utf-8")
PY

cat <<EOF
WARNING: wrote canonical AWS EXAMPLE credentials for the GHAS push-protection demo.
Credentials written to: ${target_file}
  AccessKeyId:     ${access_key_id}
  SecretAccessKey: ${secret_access_key}

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
EOF
