#!/usr/bin/env bash
# Прогон проверок ядра. Xcode не требуется — только Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
swift run --quiet SRWLEDTests
