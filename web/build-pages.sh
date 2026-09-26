#!/usr/bin/env bash
# Builds the GitHub Pages site from web/index.html into the given directory.
# web/index.html is written for claude.ai artifacts, which add the document
# skeleton at publish time, so here it is wrapped in one.
set -euo pipefail
out="${1:?usage: web/build-pages.sh <output dir>}"
src="$(dirname "$0")/index.html"
mkdir -p "$out"
{
  printf '<!doctype html>\n<html lang="it">\n<head>\n'
  printf '<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
  printf '</head>\n<body>\n'
  cat "$src"
  printf '\n</body>\n</html>\n'
} > "$out/index.html"
touch "$out/.nojekyll"
