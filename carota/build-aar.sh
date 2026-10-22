#!/usr/bin/env bash
# 构建 Carota 定制 GeckoView 157 AAR，并生成本地 Maven 仓库布局。
#
#   git checkout geckoview-157-src
#   cp carota/mozconfig-android mozconfig   # 按构建机改 SDK/NDK/JDK 路径
#   ./mach bootstrap                        # 首次
#   ./carota/build-aar.sh
#
# 产物：
#   carota/out/geckoview-beta-<VERSION>.aar
#   carota/maven-repo/org/mozilla/geckoview/geckoview-beta/<VERSION>/*.{aar,pom,sha1}
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

VERSION="${VERSION:-157.0b5-carota1}"
ARTIFACT_ID="${ARTIFACT_ID:-geckoview-beta}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/carota/out}"

if ! grep -q "Carota customization (GeckoView 157)" \
      dom/media/mediaelement/HTMLMediaElement.cpp 2>/dev/null; then
  echo "错误：当前工作区不是已打补丁的 157 源码分支（缺少 Carota 定制标记）" >&2
  echo "      请先 git checkout geckoview-157-src" >&2
  exit 1
fi

if [ ! -f mozconfig ]; then
  echo "错误：未找到 mozconfig。先执行：" >&2
  echo "      cp carota/mozconfig-android mozconfig && \$EDITOR mozconfig" >&2
  exit 1
fi

echo "==> 1/4 ./mach build（首次 40-120 分钟，后续增量）"
./mach build

echo "==> 2/4 打 release AAR（含 gecko binaries + omni.ja）"
./mach gradle geckoview:assembleRelease

echo "==> 3/4 定位并校验 AAR"
OBJDIR="$(./mach environment --format json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["topobjdir"])' 2>/dev/null || true)"
if [ -z "${OBJDIR:-}" ] || [ ! -d "$OBJDIR" ]; then
  OBJDIR="$(ls -d obj-* 2>/dev/null | head -n1)"
fi
AAR_DIR="$OBJDIR/gradle/build/mobile/android/geckoview/outputs/aar"
AAR="$(ls -1 "$AAR_DIR"/*.aar 2>/dev/null | grep -v sources | head -n1 || true)"
if [ -z "${AAR:-}" ]; then
  echo "错误：未在 $AAR_DIR 找到 AAR" >&2
  exit 1
fi
echo "    objdir: $OBJDIR"
echo "    aar   : $AAR ($(du -h "$AAR" | cut -f1))"

unzip -l "$AAR" | grep -q 'jni/arm64-v8a/libxul.so' || {
  echo "错误：AAR 内缺少 jni/arm64-v8a/libxul.so（machStagePackage 没跑？）" >&2
  exit 1
}
unzip -l "$AAR" | grep -q 'assets/omni.ja' || {
  echo "错误：AAR 内缺少 assets/omni.ja" >&2
  exit 1
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$AAR" 'jni/arm64-v8a/libxul.so' -d "$TMP"
if grep -a -q "Not listening because it's an audio element" "$TMP/jni/arm64-v8a/libxul.so"; then
  echo "    OK: 定制补丁已编入 libxul.so"
else
  echo "错误：libxul.so 中未找到定制字符串，补丁未生效或用了旧 objdir" >&2
  exit 1
fi

echo "==> 4/4 生成本地 Maven 仓库布局"
DEST="$REPO_ROOT/carota/maven-repo/org/mozilla/geckoview/$ARTIFACT_ID/$VERSION"
mkdir -p "$DEST" "$OUT_DIR"
cp "$AAR" "$DEST/$ARTIFACT_ID-$VERSION.aar"
sed -e "s|@ARTIFACT_ID@|$ARTIFACT_ID|g" -e "s|@VERSION@|$VERSION|g" \
  carota/maven/pom-template.xml > "$DEST/$ARTIFACT_ID-$VERSION.pom"
( cd "$DEST" && sha1sum "$ARTIFACT_ID-$VERSION.aar" > "$ARTIFACT_ID-$VERSION.aar.sha1" )
cp "$AAR" "$OUT_DIR/$ARTIFACT_ID-$VERSION.aar"

echo
echo "完成："
echo "  AAR      : $OUT_DIR/$ARTIFACT_ID-$VERSION.aar"
echo "  Maven 仓 : $REPO_ROOT/carota/maven-repo"
echo
echo "接入：把 carota/maven-repo 同步到 Android 构建机，例如"
echo "  scp -r carota/maven-repo <user>@<win-host>:D:/carotaapp/geckoview-m2"
echo "然后用工程侧的 init 脚本（carota/consume/init-carota-geckoview.gradle.kts）替换依赖。"