#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
TARBALL="/Users/jfishin/Downloads/crossover-sources-26.2.0.tar.gz"

mkdir -p "$WV_ROOT/src"
if [ -d "$WV_SRC/.git" ]; then echo "Source already staged at $WV_SRC"; exit 0; fi

echo "Extracting sources/wine ..."
tmp="$WV_ROOT/src/_extract"
mkdir -p "$tmp"
tar -xzf "$TARBALL" -C "$tmp" sources/wine
mv "$tmp/sources/wine" "$WV_SRC"
rm -rf "$tmp"

cd "$WV_SRC"
git init -q -b main
git add -A
git -c user.email=build@winevideo -c user.name=winevideo commit -q -m "vendor: CrossOver 26.2.0 Wine 11.0 source (pristine)"
echo "Staged + git baseline at $WV_SRC"
cat VERSION
