#!/usr/bin/env bash
# 在 geckoview_dev 仓库中生成「Firefox 157.0b5 全量源码 + Carota 定制」分支。
#
#   git checkout geckoview-157-carota
#   ./carota/prepare-157-src.sh            # 生成 geckoview-157-src
#   PUSH=1 ./carota/prepare-157-src.sh     # 生成并推送到 origin
#
# 依赖：git 2.x、约 12GB 可用磁盘（157 源码树 ~9GB + .git 增量）。
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

MOZ_URL="${MOZ_URL:-https://github.com/mozilla-firefox/firefox}"
BASE_REV="${BASE_REV:-46056a25c157e52da994bef01ae29463aa0dba9a}"
SRC_BRANCH="${SRC_BRANCH:-geckoview-157-src}"
PUSH="${PUSH:-0}"

if [ ! -d carota/patches ]; then
  echo "错误：请在 geckoview-157-carota 分支的仓库根目录运行本脚本" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -a carota "$WORK/carota"

echo "==> 1/4 拉取 Firefox 157.0b5 源码（$BASE_REV，整棵树约 500MB）"
if ! git fetch --depth 1 --no-tags "$MOZ_URL" "$BASE_REV"; then
  echo "    按 SHA 拉取失败，回退到标签 FIREFOX_157_0b5_BUILD1"
  git fetch --depth 1 --no-tags "$MOZ_URL" refs/tags/FIREFOX_157_0b5_BUILD1
fi
SRC_VERSION="$(git show FETCH_HEAD:browser/config/version.txt | tr -d '[:space:]')"
if [ "$SRC_VERSION" != "157.0" ]; then
  echo "错误：拉到的源码版本是 '$SRC_VERSION'，期望 157.0" >&2
  exit 1
fi
echo "    源码版本 OK: $SRC_VERSION（$(git show FETCH_HEAD:browser/config/version_display.txt)）"

echo "==> 2/4 新建分支 $SRC_BRANCH，并把工作区整棵替换为 157 源码"
git switch -C "$SRC_BRANCH"
git read-tree --reset -u FETCH_HEAD
git commit -q -m "Import Firefox 157.0b5 GeckoView source

source: $MOZ_URL $BASE_REV
hg-rev: 1d349a6de68c5b3e8e0db2493d871eef1926d837 (FIREFOX_157_0b5)
official AAR: org.mozilla.geckoview:geckoview-beta:157.0.20260923115834"

echo "==> 3/4 应用 Carota 定制补丁"
for p in "$WORK"/carota/patches/*.patch; do
  echo "    + $(basename "$p")"
  git apply --index "$p"
done
git commit -q -m "Carota 定制：媒体控制只对视频注册（含静音视频）

dom/media/mediaelement/HTMLMediaElement.cpp
::HTMLMediaElement::StartMediaControlKeyListenerIfNeeded()

- 纯音频不注册媒体控制，MediaSession.Delegate.onPlay 只代表视频，
  避免音乐/播客在「行车视频抑制」时被误暂停
- 视频豁免上游的可听性延迟检查：静音/零音量/autoplay-muted 视频同样触发 onPlay"

echo "==> 4/4 把 carota/ 构建脚本带回源码分支"
rm -rf "$REPO_ROOT/carota"
cp -a "$WORK/carota" "$REPO_ROOT/carota"
git add -f carota
git commit -q -m "添加 Carota 构建脚本与说明"

git --no-pager log --oneline -4
echo
echo "完成。源码分支: $SRC_BRANCH"
echo "下一步: git checkout $SRC_BRANCH && cp carota/mozconfig-android mozconfig && ./carota/build-aar.sh"

if [ "$PUSH" = "1" ]; then
  echo "==> 推送 $SRC_BRANCH 到 origin"
  git push -u origin "$SRC_BRANCH"
fi