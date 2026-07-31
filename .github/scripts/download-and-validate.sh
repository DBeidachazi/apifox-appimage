#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
  echo "用法: $0 <下载地址> <输出文件> <架构名称>" >&2
  exit 2
fi

url="$1"
output="$2"
label="$3"
partial="${output}.part"
min_zip_size="${MIN_ZIP_SIZE:-104857600}"
retry_delay_base="${RETRY_DELAY_BASE:-15}"

if [[ ! "$min_zip_size" =~ ^[0-9]+$ || ! "$retry_delay_base" =~ ^[0-9]+$ ]]; then
  echo "错误: MIN_ZIP_SIZE 和 RETRY_DELAY_BASE 必须是非负整数" >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"

for attempt in 1 2 3; do
  echo "=== 下载 ${label} (第 ${attempt}/3 次尝试) ==="
  rm -f "$output" "$partial"

  if curl --retry 3 --retry-delay 5 --retry-all-errors \
       --connect-timeout 30 --max-time 1800 -fL \
       "$url" -o "$partial"; then
    size=$(stat -c '%s' "$partial")
    echo "${label} 下载大小: ${size} bytes"

    if (( size < min_zip_size )); then
      echo "错误: ${label} 只有 ${size} bytes，小于最低要求 ${min_zip_size} bytes"
    elif ! unzip -tq "$partial" >/dev/null; then
      echo "错误: ${label} 不是完整有效的 ZIP 包"
    else
      appimage_entry=$(unzip -Z1 "$partial" | awk '/(^|\/)Apifox[^\/]*\.AppImage$/ && !found { print; found=1 }')
      if [[ -n "$appimage_entry" ]]; then
        mv "$partial" "$output"
        echo "${label} 校验通过，包含 ${appimage_entry}"
        exit 0
      fi
      echo "错误: ${label} 中未找到 Apifox AppImage"
    fi
  else
    echo "错误: ${label} 下载失败"
  fi

  rm -f "$partial"
  if (( attempt < 3 )); then
    sleep $((attempt * retry_delay_base))
  fi
done

exit 1
