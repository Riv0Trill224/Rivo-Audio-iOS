#!/bin/bash
set -euo pipefail
RIVO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RIVO_ROOT"
mkdir -p Vendor
if [[ ! -f Vendor/taglib-2.3.2.tar.gz ]]; then
  curl --fail --location --retry 3 https://codeload.github.com/taglib/taglib/tar.gz/refs/tags/v2.3.2 -o Vendor/taglib-2.3.2.tar.gz
fi
if [[ ! -f Vendor/utfcpp-4.0.6.tar.gz ]]; then
  curl --fail --location --retry 3 https://codeload.github.com/nemtrif/utfcpp/tar.gz/refs/tags/v4.0.6 -o Vendor/utfcpp-4.0.6.tar.gz
fi
(cd Vendor && shasum -a 256 -c SHA256SUMS)
