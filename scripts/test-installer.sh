#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
bash -n "$project_dir/install.sh"
bash -n "$project_dir/Install.command"
python3 "$project_dir/Tests/InstallerChecks.py"
