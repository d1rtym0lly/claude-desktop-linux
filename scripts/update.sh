#!/usr/bin/env bash
# Bring arch/PKGBUILD and sources.json up to date with the newest Claude
# Desktop release in Anthropic's apt repository.
#
# Version and SHA-256 come from the repository's signed Packages index,
# so nothing needs to be downloaded to compute checksums.
#
# Usage: scripts/update.sh          update files in place
#        scripts/update.sh --check  exit 1 if an update is available

set -euo pipefail

repo="${CLAUDE_DESKTOP_REPO:-https://downloads.claude.ai/claude-desktop/apt/stable}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkgbuild="$root/arch/PKGBUILD"
sources="$root/sources.json"

# Print "version filename sha256" of the newest claude-desktop in an index.
latest() {
    curl -fsSL "$repo/dists/stable/main/binary-$1/Packages" | awk '
        /^Package: /  { pkg = $2 }
        /^Version: /  { ver = $2 }
        /^Filename: / { file = $2 }
        /^SHA256: /   { sha = $2 }
        /^$/ { if (pkg == "claude-desktop") print ver, file, sha; pkg = "" }
        END  { if (pkg == "claude-desktop") print ver, file, sha }
    ' | sort -V -k1,1 | tail -n 1
}

read -r ver_amd64 file_amd64 sha_amd64 < <(latest amd64)
read -r ver_arm64 file_arm64 sha_arm64 < <(latest arm64)

if [[ -z ${ver_amd64:-} || -z ${sha_amd64:-} ]]; then
    echo "error: no claude-desktop package in the amd64 index" >&2
    exit 1
fi
if [[ ${ver_arm64:-} != "$ver_amd64" ]]; then
    echo "error: amd64 ($ver_amd64) and arm64 (${ver_arm64:-none}) versions differ" >&2
    exit 1
fi

version="$ver_amd64"
# Arch versions can't contain '-'; Debian revisions like 1.2-3 become 1.2_3.
pkgver="${version//-/_}"
expected="pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb"
if [[ $file_amd64 != "$expected" ]]; then
    echo "error: unexpected file layout in the repository: $file_amd64" >&2
    echo "       PKGBUILD expects $expected; adjust _repo/source there" >&2
    exit 1
fi

current=$(sed -n 's/^pkgver=//p' "$pkgbuild")
if [[ ${1:-} == --check ]]; then
    echo "current: $current, latest: $pkgver"
    [[ $current == "$pkgver" ]]
    exit
fi

local_sums=()
for f in claude-desktop-launcher.sh claude-desktop-autostart.sh; do
    local_sums+=("'$(sha256sum "$root/common/$f" | cut -d' ' -f1)'")
done

sed -i \
    -e "s/^pkgver=.*/pkgver=$pkgver/" \
    -e "s/^_debver=.*/_debver=$version/" \
    -e "s/^sha256sums=.*/sha256sums=(${local_sums[*]})/" \
    -e "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$sha_amd64')/" \
    -e "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('$sha_arm64')/" \
    "$pkgbuild"
if [[ $current != "$pkgver" ]]; then
    sed -i "s/^pkgrel=.*/pkgrel=1/" "$pkgbuild"
fi

cat > "$sources" <<EOF
{
  "version": "$version",
  "amd64": {
    "url": "$repo/$file_amd64",
    "sha256": "$sha_amd64"
  },
  "arm64": {
    "url": "$repo/$file_arm64",
    "sha256": "$sha_arm64"
  }
}
EOF

echo "claude-desktop $version (PKGBUILD pkgver=$pkgver)"
