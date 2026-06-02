#!/usr/bin/env bash
set -euo pipefail

target_file="src/backend/src/main/resources/application-local.yml"

# Generate realistic-looking AWS credentials. The canonical AKIA...EXAMPLE
# values are allow-listed by GitHub Secret Scanning (they appear in AWS
# documentation), so we generate fresh random values that still match
# both detector patterns:
#   * Access Key ID: AKIA + 16 uppercase base36 chars
#   * Secret Access Key: 40 base64-safe chars (A-Z, a-z, 0-9, +, /)
read -r access_key_id secret_access_key < <(python3 - <<'PY'
import secrets
import string

uppercase = string.ascii_uppercase + string.digits
base64ish = string.ascii_letters + string.digits + "+/"

access_key_id = "AKIA" + "".join(secrets.choice(uppercase) for _ in range(16))
secret_access_key = "".join(secrets.choice(base64ish) for _ in range(40))
print(access_key_id, secret_access_key)
PY
)

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
WARNING: wrote randomly generated AWS-format credentials for the GHAS push-protection demo.
Credentials written to: ${target_file}
  AccessKeyId:     ${access_key_id}
  SecretAccessKey: ${secret_access_key}

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
EOF
