#!/usr/bin/env bash
# Builds the GitHub Pages site into the given directory: the presentation
# site (site/) at the root and the game (web/index.html) under play/.
# web/index.html is written for claude.ai artifacts, which add the document
# skeleton at publish time, so here it is wrapped in one.
set -euo pipefail
out="${1:?usage: web/build-pages.sh <output dir>}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out/play"
{
  printf '<!doctype html>\n<html lang="it">\n<head>\n'
  printf '<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
  printf '</head>\n<body>\n'
  cat "$repo/web/index.html"
  printf '\n</body>\n</html>\n'
} > "$out/play/index.html"
cp -R "$repo/site/." "$out/"
touch "$out/.nojekyll"
