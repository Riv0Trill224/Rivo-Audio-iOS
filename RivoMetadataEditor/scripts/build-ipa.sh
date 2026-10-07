#!/bin/bash
set -euo pipefail
RIVO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RIVO_ROOT"
if [[ ! -d Vendor/TagLib.xcframework ]]; then bash scripts/build-taglib.sh; fi
command -v xcodegen >/dev/null || { echo 'Instala XcodeGen: brew install xcodegen'; exit 1; }
xcodegen generate
xcodebuild -project RivoMetadataEditor.xcodeproj -scheme RivoMetadataEditor \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
mkdir -p .build/Package/Payload
rm -rf .build/Package/Payload/RivoMetadataEditor.app
cp -R .build/DerivedData/Build/Products/Release-iphoneos/RivoMetadataEditor.app .build/Package/Payload/
mkdir -p dist
RIVO_IPA="$RIVO_ROOT/dist/RivoMetadataEditor-v0.2.0-unsigned.ipa"
rm -f "$RIVO_IPA"
(cd .build/Package && zip -qry "$RIVO_IPA" Payload)
echo "IPA creada: $RIVO_IPA"
echo 'Firma e instala esta IPA con SideStore o AltStore. No contiene una firma de distribución de Apple.'
