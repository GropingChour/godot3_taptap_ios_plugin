#!/bin/bash
#
# update_sdk.sh - 从 GitHub 下载并更新 TapTap iOS SDK 到最新版本
#
# 用法:
#   ./scripts/update_sdk.sh [version]
#
# 示例:
#   ./scripts/update_sdk.sh           # 下载最新版本 (默认 4.10.1)
#   ./scripts/update_sdk.sh 4.10.1    # 下载指定版本
#
# SDK 来源: https://github.com/taptap/tapsdk-frameworks
#

set -euo pipefail

SDK_VERSION="${1:-4.10.1}"
REPO_URL="https://github.com/taptap/tapsdk-frameworks"
ARCHIVE_URL="${REPO_URL}/archive/refs/tags/${SDK_VERSION}.tar.gz"

# 项目根目录 (脚本所在目录的上一级)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_DIR="${PROJECT_DIR}/plugins/godot3_taptap/sdk"
TMP_DIR="${PROJECT_DIR}/bin/temp/sdk_update_${SDK_VERSION}"

# 本插件需要的 SDK 文件列表
REQUIRED_FRAMEWORKS=(
    # 核心模块
    "THEMISLite.xcframework"
    "TapTapBasicToolsSDK.xcframework"
    "TapTapCoreSDK.xcframework"
    "TapTapGidSDK.xcframework"
    "TapTapNetworkSDK.xcframework"
    "tapsdkcorecpp.xcframework"
    "TapTapSDKBridgeCore.xcframework"
    # 登录
    "TapTapLoginSDK.xcframework"
    "TapTapLoginResource.bundle"
    # 合规认证
    "TapTapComplianceSDK.xcframework"
    "TapTapComplianceResource.bundle"
    # 云存档
    "TapTapCloudSaveSDK.xcframework"
    "cloudsave_sdk.xcframework"
    # 成就系统
    "TapTapAchievementSDK.xcframework"
    "TapTapAchievementResource.bundle"
)

echo "============================================"
echo "TapTap iOS SDK Updater"
echo "============================================"
echo "Version:    ${SDK_VERSION}"
echo "Source:     ${REPO_URL}"
echo "Target:     ${SDK_DIR}"
echo "============================================"
echo ""

# 1. 创建临时目录
echo "[1/4] Creating temp directory..."
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# 2. 下载 SDK 源码包
echo "[2/4] Downloading SDK v${SDK_VERSION}..."
ARCHIVE_FILE="${TMP_DIR}/tapsdk-${SDK_VERSION}.tar.gz"

if command -v curl &> /dev/null; then
    curl -L --fail --progress-bar -o "${ARCHIVE_FILE}" "${ARCHIVE_URL}"
elif command -v wget &> /dev/null; then
    wget --show-progress -O "${ARCHIVE_FILE}" "${ARCHIVE_URL}"
else
    echo "ERROR: Neither curl nor wget found. Please install one of them."
    exit 1
fi

if [ ! -f "${ARCHIVE_FILE}" ]; then
    echo "ERROR: Download failed!"
    exit 1
fi

echo "Download complete: $(du -h "${ARCHIVE_FILE}" | cut -f1)"

# 3. 解压
echo "[3/4] Extracting..."
tar -xzf "${ARCHIVE_FILE}" -C "${TMP_DIR}"

# 找到解压后的 Frameworks 目录
EXTRACTED_DIR=$(find "${TMP_DIR}" -maxdepth 1 -type d -name "tapsdk-frameworks-*" | head -1)
FRAMEWORKS_DIR="${EXTRACTED_DIR}/Frameworks"

if [ ! -d "${FRAMEWORKS_DIR}" ]; then
    echo "ERROR: Frameworks directory not found in extracted archive!"
    echo "Expected: ${FRAMEWORKS_DIR}"
    ls -la "${TMP_DIR}"
    exit 1
fi

echo "Found frameworks at: ${FRAMEWORKS_DIR}"

# 4. 复制需要的 SDK 文件
echo "[4/4] Updating SDK files..."
mkdir -p "${SDK_DIR}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for item in "${REQUIRED_FRAMEWORKS[@]}"; do
    SRC="${FRAMEWORKS_DIR}/${item}"
    DST="${SDK_DIR}/${item}"

    if [ -e "${SRC}" ]; then
        # 删除旧的文件/目录
        rm -rf "${DST}"
        # 复制新的
        cp -R "${SRC}" "${DST}"
        echo "  ✓ ${item}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "  ✗ ${item} (not found in SDK)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# 清理临时文件
echo ""
echo "Cleaning up temp files..."
rm -rf "${TMP_DIR}"

# 打印结果
echo ""
echo "============================================"
echo "SDK Update Complete!"
echo "============================================"
echo "Updated: ${SUCCESS_COUNT} files"
if [ ${FAIL_COUNT} -gt 0 ]; then
    echo "Missing:  ${FAIL_COUNT} files"
fi
echo "Version:  ${SDK_VERSION}"
echo "Target:   ${SDK_DIR}"
echo "============================================"

# 列出最终 sdk 目录内容
echo ""
echo "SDK directory contents:"
ls -1 "${SDK_DIR}"
