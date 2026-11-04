#!/bin/zsh
set -eu
set -o pipefail
cd "${0:A:h}/.."
./source/build.sh
codesign --verify --deep --strict XDRLight.app
python3 tests/run_integration.py "$@"
