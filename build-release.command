#!/bin/zsh
# Reproducible local packaging. Does not install, launch, upload or publish.
set -eu
set -o pipefail
cd "${0:A:h}"
VER=$(python3 -c "import json; print(json.load(open('source/release.json'))['version'])")
OUT="$PWD/dist"
STAGE=$(mktemp -d -t xdrlight-release)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT" "$STAGE/dmg" "$STAGE/XDRLight-source"
./source/build.sh
codesign --verify --deep --strict XDRLight.app
# Keep all build dependencies; omit local logs, backups and generated app bundles.
rsync -a --exclude '*backup*' --exclude '.DS_Store' source/ "$STAGE/XDRLight-source/source/"
rsync -a --exclude '.DS_Store' --exclude 'prism-4x.png' assets/ "$STAGE/XDRLight-source/assets/"
for doc in LICENSE README.md THIRD_PARTY.md CODE_PROVENANCE.md CLAUDE_REVIEW.md VALIDATION.md .gitignore 使用说明.md 安装说明.txt; do
  if [[ -f "$doc" ]]; then cp "$doc" "$STAGE/XDRLight-source/"; fi
done
cp build-release.command 恢复色彩.command "$STAGE/XDRLight-source/"
if [[ -d tests ]]; then ditto tests "$STAGE/XDRLight-source/tests"; fi
COPYFILE_DISABLE=1 tar -czf "$OUT/XDRLight-$VER-source.tar.gz" -C "$STAGE" XDRLight-source
ditto --norsrc --noextattr --noqtn -c -k --keepParent "$STAGE/XDRLight-source" "$OUT/XDRLight-$VER-source.zip"
ditto --norsrc --noextattr --noqtn -c -k --keepParent XDRLight.app "$OUT/XDRLight-$VER-macOS.zip"
ditto XDRLight.app "$STAGE/dmg/XDRLight.app"
ln -s /Applications "$STAGE/dmg/Applications"
cp 安装说明.txt LICENSE 恢复色彩.command "$STAGE/dmg/"
cp "$OUT/XDRLight-$VER-source.zip" "$OUT/XDRLight-$VER-source.tar.gz" "$STAGE/dmg/"
hdiutil create -volname "XDRLight $VER" -srcfolder "$STAGE/dmg" -ov -format UDZO "$OUT/XDRLight-$VER.dmg"
hdiutil verify "$OUT/XDRLight-$VER.dmg"
(cd "$OUT" && shasum -a 256 "XDRLight-$VER-source.zip" "XDRLight-$VER-source.tar.gz" "XDRLight-$VER-macOS.zip" "XDRLight-$VER.dmg" > "SHA256SUMS-$VER.txt")
echo "Release artifacts: $OUT"
