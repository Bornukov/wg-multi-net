#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Использование: $0 <имя_сети> [--follow]"
    echo "Пример: $0 net1 --follow"
    exit 1
fi

name="$1"
shift || true

docker logs "wg-${name}" "$@"
