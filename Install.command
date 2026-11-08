#!/bin/bash
set -euo pipefail
install_command_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_command_temp=""
trap '[[ -z "$install_command_temp" ]] || rm -rf "$install_command_temp"' EXIT
if [[ -f "$install_command_dir/install.sh" && ! -L "$install_command_dir/install.sh" ]]; then
    /bin/bash "$install_command_dir/install.sh" "$@"
else
    umask 077
    install_command_temp="$(mktemp -d "${TMPDIR:-/tmp}/sanju-snapdrive-command.XXXXXXXX")"
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 60 \
        --proto '=https' --tlsv1.2 \
        'https://raw.githubusercontent.com/sanjuantala/sanju-snapdrive/v1.5.0/install.sh' \
        --output "$install_command_temp/install.sh"
    /bin/bash "$install_command_temp/install.sh" "$@"
fi
