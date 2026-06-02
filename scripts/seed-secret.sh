#!/usr/bin/env bash
set -euo pipefail

target_file="src/backend/src/main/resources/application-local.yml"

token_body="$(python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(40)))
PY
)"
token="ghp_${token_body}"

python3 - "${target_file}" "${token}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
token = sys.argv[2]
label = " # SEEDED VULN #4 — see scripts/seed-vulnerabilities.md"
key = "leakedGitHubPat:"
replacement_value = f'{key} "{token}"{label}'

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    lines = path.read_text(encoding="utf-8").splitlines()
else:
    lines = []

replaced = False
for index, line in enumerate(lines):
    if line.strip().startswith(key):
        indent = line[: len(line) - len(line.lstrip())]
        lines[index] = f"{indent}{replacement_value}"
        replaced = True
        break

if not replaced:
    if lines and lines[-1] != "":
        lines.append("")
    lines.extend([
        "# Local-only demo values; never used by the cloud profile.",
        "demo:",
        f"  {replacement_value}",
    ])

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat <<EOF
WARNING: generated a fake GitHub PAT-pattern token for the GHAS push-protection demo.
Token written to: ${target_file}
Token value: ${token}

This script does not run git add, git commit, or git push.
Run it only on a disposable feature branch created from vulnerable.
Commit and push manually when demonstrating seed #4; the expected result is a push-protection rejection.
Do not use --allow-secret-scanning-bypass in automation because the rejection is the demo moment.
EOF
