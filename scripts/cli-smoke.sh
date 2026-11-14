#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
real_root="$HOME/.local/stria"
real_root_existed=0
if [[ -e "$real_root" ]]; then real_root_existed=1; fi

swift build --product stria
BIN="$(swift build --show-bin-path)/stria"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export STRIA_HOME="$WORK/home"

fail() { printf 'SMOKE FAILED: %s\n' "$1" >&2; exit 1; }
run_json() {
  local step="$1"
  shift
  if ! "$BIN" "$@" >"$WORK/$step.json" 2>"$WORK/$step.stderr"; then
    cat "$WORK/$step.stderr" >&2
    fail "$step exited nonzero"
  fi
}
get() {
  /usr/bin/python3 -c 'import json,sys; value=json.load(open(sys.argv[1]));
for part in sys.argv[2].split("."):
 value = value[int(part)] if isinstance(value,list) else value[part]
print(value)' "$1" "$2"
}
count() {
  /usr/bin/python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2"
}

swift "$ROOT/scripts/make-sample-pdf.swift" "$WORK/a.pdf" a
swift "$ROOT/scripts/make-sample-pdf.swift" "$WORK/b.pdf" b
run_json import-a import "$WORK/a.pdf" --no-ocr
run_json import-b import "$WORK/b.pdf" --no-ocr
id_a="$(get "$WORK/import-a.json" document.id)"
id_b="$(get "$WORK/import-b.json" document.id)"
run_json list list
[[ "$(count "$WORK/list.json" documents)" == 2 ]] || fail "list count was not 2"
run_json image page image "$id_a" 1
image_path="$(get "$WORK/image.json" path)"
[[ -f "$image_path" ]] || fail "page image path does not exist"
run_json config-set config set ocr.vendor pdf-text-layer
run_json ocr-a ocr "$id_a"
run_json ocr-b ocr "$id_b"
run_json search-phrase search "zebra quantum lattice"
[[ "$(get "$WORK/search-phrase.json" results.0.docId)" == "$id_b" ]] || fail "phrase search returned wrong document"
[[ "$(get "$WORK/search-phrase.json" results.0.page)" == 2 ]] || fail "phrase search returned wrong page"
run_json search-japanese search 学習
[[ "$(get "$WORK/search-japanese.json" matchMode)" == like ]] || fail "Japanese query did not use LIKE"
[[ "$(count "$WORK/search-japanese.json" results)" -ge 1 ]] || fail "Japanese query had no results"
run_json history history
get "$WORK/history.json" messages >/dev/null || fail "history messages key missing"

if [[ "$real_root_existed" == 0 && -e "$real_root" ]]; then fail "real data root was created"; fi
printf 'SMOKE OK\n'
