#!/usr/bin/env bash

set -euo pipefail

if (( $# != 4 )); then
  echo "用法: $0 <版本号> <x86_64 SHA-256> <aarch64 SHA-256> <GitHub 仓库>" >&2
  exit 2
fi

version="$1"
x86_64_sha256="$2"
aarch64_sha256="$3"
repository="$4"

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "错误: 无效版本号 $version" >&2
  exit 2
fi

if [[ ! "$x86_64_sha256" =~ ^[0-9a-f]{64}$ || \
      ! "$aarch64_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "错误: SHA-256 格式无效" >&2
  exit 2
fi

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "错误: GitHub 仓库格式无效: $repository" >&2
  exit 2
fi

for required_line in \
  '^pkgver=' \
  '^pkgrel=' \
  '^source_x86_64=' \
  '^source_aarch64=' \
  '^sha256sums_x86_64=' \
  '^sha256sums_aarch64='
do
  if [[ $(grep -c "$required_line" PKGBUILD) -ne 1 ]]; then
    echo "错误: PKGBUILD 中应有且仅有一行匹配 $required_line" >&2
    exit 1
  fi
done

current_version=$(sed -n 's/^pkgver=//p' PKGBUILD)
current_pkgrel=$(sed -n 's/^pkgrel=//p' PKGBUILD)

if [[ ! "$current_version" =~ ^[0-9]+(\.[0-9]+)+$ || \
      ! "$current_pkgrel" =~ ^[0-9]+$ ]]; then
  echo "错误: 当前 pkgver/pkgrel 无效: ${current_version}-${current_pkgrel}" >&2
  exit 1
fi

highest_version=$(printf '%s\n%s\n' "$current_version" "$version" | sort -V | tail -n 1)
if [[ "$current_version" != "$version" && "$highest_version" != "$version" ]]; then
  echo "错误: Release 版本 $version 低于当前软件包版本 $current_version，拒绝降级" >&2
  exit 1
fi

release_base="https://github.com/${repository}/releases/download/v\${pkgver}"
x86_64_source="apifox-\${pkgver}-linux.zip::${release_base}/Apifox-linux-\${pkgver}.zip"
aarch64_source="apifox-\${pkgver}-linux-arm64.zip::${release_base}/Apifox-linux-\${pkgver}-arm64.zip"

metadata_current=false
if [[ "$current_version" == "$version" ]] && \
   grep -Fqx "source_x86_64=(\"${x86_64_source}\")" PKGBUILD && \
   grep -Fqx "source_aarch64=(\"${aarch64_source}\")" PKGBUILD && \
   grep -Fqx "sha256sums_x86_64=('${x86_64_sha256}')" PKGBUILD && \
   grep -Fqx "sha256sums_aarch64=('${aarch64_sha256}')" PKGBUILD; then
  metadata_current=true
fi

if [[ "$metadata_current" == true ]]; then
  echo "软件包元数据已是 ${version}-${current_pkgrel}，无需修改"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "changed=false" >> "$GITHUB_OUTPUT"
    echo "version=$version" >> "$GITHUB_OUTPUT"
    echo "pkgrel=$current_pkgrel" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

if [[ "$current_version" == "$version" ]]; then
  pkgrel=$((current_pkgrel + 1))
else
  pkgrel=1
fi

sed -i \
  -e "s/^pkgver=.*/pkgver=${version}/" \
  -e "s/^pkgrel=.*/pkgrel=${pkgrel}/" \
  -e "s|^source_x86_64=.*|source_x86_64=(\"${x86_64_source}\")|" \
  -e "s|^source_aarch64=.*|source_aarch64=(\"${aarch64_source}\")|" \
  -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('${x86_64_sha256}')/" \
  -e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('${aarch64_sha256}')/" \
  PKGBUILD

sed -i \
  -e "s/^[[:space:]]*pkgver = .*/\tpkgver = ${version}/" \
  -e "s/^[[:space:]]*pkgrel = .*/\tpkgrel = ${pkgrel}/" \
  -e "s|^[[:space:]]*source_x86_64 = .*|\tsource_x86_64 = apifox-${version}-linux.zip::https://github.com/${repository}/releases/download/v${version}/Apifox-linux-${version}.zip|" \
  -e "s|^[[:space:]]*source_aarch64 = .*|\tsource_aarch64 = apifox-${version}-linux-arm64.zip::https://github.com/${repository}/releases/download/v${version}/Apifox-linux-${version}-arm64.zip|" \
  -e "s/^[[:space:]]*sha256sums_x86_64 = .*/\tsha256sums_x86_64 = ${x86_64_sha256}/" \
  -e "s/^[[:space:]]*sha256sums_aarch64 = .*/\tsha256sums_aarch64 = ${aarch64_sha256}/" \
  .SRCINFO

bash -n PKGBUILD

echo "软件包元数据已更新到 ${version}-${pkgrel}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=true" >> "$GITHUB_OUTPUT"
  echo "version=$version" >> "$GITHUB_OUTPUT"
  echo "pkgrel=$pkgrel" >> "$GITHUB_OUTPUT"
fi
