#!/bin/sh
# gennixbuilder.sh <mode> <n> [prefix_len] : mimic darwin-derivation-builder output for n store inputs
# mode=current : nix's current form (new allow form every 16 KiB of source)
# mode=bucket  : one allow form per distinct hash prefix of prefix_len chars (default 1),
#                guarded by (prefix "<store>/<hash prefix>")
here=$(dirname "$0")
mode=$1
n=$2
prefix_len=${3:-1}
if [ "$prefix_len" -lt 1 ] || [ "$prefix_len" -gt 32 ]; then
  echo "prefix_len must be between 1 and 32" >&2
  exit 2
fi

ops="file-read* file-write* process-exec"
chunk_limit=16384
tab=$(printf '\t')

store_paths() {
  "$here/randstr.sh" "$n" 32 | {
    i=0
    while read -r hash; do
      i=$((i + 1))
      echo "/nix/store/$hash-pkg$i"
    done
  }
}

current_form() {
  header="(allow $ops"
  echo "$header"
  chunk_size=$((${#header} + 1))

  while read -r p; do
    if [ "$chunk_size" -ge "$chunk_limit" ]; then
      echo ")"
      echo "$header"
      chunk_size=0
    fi
    line="$tab(subpath \"$p\")"
    echo "$line"
    chunk_size=$((chunk_size + ${#line} + 1))
  done

  echo ")"
}

# Prints "<hash prefix> <index> <path>" per path, so sort can group by prefix
# while keeping the original order inside each group.
with_bucket_keys() {
  any_prefix=$(printf "%${prefix_len}s" | tr ' ' '?')
  i=0
  while read -r p; do
    i=$((i + 1))
    hash=${p#/nix/store/}
    rest=${hash#$any_prefix}
    key=${hash%"$rest"}
    echo "$key $i $p"
  done
}

bucket_form() {
  previous=""
  while read -r key i p; do
    if [ "$key" != "$previous" ]; then
      if [ -n "$previous" ]; then
        echo ")))"
      fi
      echo "(allow $ops"
      printf '\t(require-all (prefix "/nix/store/%s")\n' "$key"
      printf '\t\t(require-any\n'
      previous=$key
    fi
    printf '\t\t(subpath "%s")\n' "$p"
  done

  if [ -n "$previous" ]; then
    echo ")))"
  fi
}

echo '(version 1)(deny default)'

if [ "$mode" = current ]; then
  store_paths | current_form
else
  store_paths | with_bucket_keys | LC_ALL=C sort -k1,1 -k2,2n | bucket_form
fi
