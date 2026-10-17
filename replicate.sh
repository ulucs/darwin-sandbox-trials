#!/bin/sh
# replicate.sh [--slow] : rebuild sbcompile and re-measure every number in LIMITS.md
# --slow also runs the compile-time and libsandbox-crash checks (several minutes)
cd "$(dirname "$0")" || exit 1

slow=false
if [ "$1" = --slow ]; then
  slow=true
fi

header='(version 1)(deny default)'
file_ops="file-read-data file-read-metadata file-read-xattr file-link file-ioctl
file-write-data file-write-create file-write-unlink file-write-mode file-write-owner
file-write-flags file-write-times file-write-xattr file-write-acl"

first_ops() {
  echo $file_ops | cut -d ' ' -f "1-$1"
}

section() {
  echo
  echo "== $1"
}

report() {
  printf "  %-55s expected %-10s got %s\n" "$1" "$2" "$3"
}

# Reads a profile on stdin; prints "OK <bytes>", "FAIL <error>" or "CRASH exit=<code>".
compile_result() {
  output=$(./sbcompile - 2>&1)
  exit_code=$?
  if [ "$exit_code" -gt 128 ]; then
    echo "CRASH exit=$exit_code"
    return
  fi
  case $output in
    OK*)
      size=${output##*bytecode_bytes=}
      echo "OK ${size%% *}"
      ;;
    *)
      echo "FAIL $(echo "${output#*error=}" | head -n 1)"
      ;;
  esac
}

compiles() {
  "$@" | ./sbcompile - >/dev/null 2>&1
}

# Binary search for the largest n where "<generator...> n" compiles.
largest_n() {
  low=$1
  high=$2
  shift 2
  while [ $((high - low)) -gt 1 ]; do
    mid=$(( (low + high) / 2 ))
    if compiles "$@" "$mid"; then
      low=$mid
    else
      high=$mid
    fi
  done
  echo "$low"
}

random_paths() {
  ./randstr.sh "$1" 24 abcdefghijklmnopqrstuvwxyz0123456789 | sed 's|^|/|'
}

random_literals() {
  echo "$header"
  random_paths "$1" | while read -r p; do
    echo "(allow file-read-data (literal \"$p\"))"
  done
}

subpaths_on_ops() {
  ops=$(first_ops "$1")
  n=$2
  echo "$header"
  i=1
  while [ "$i" -le "$n" ]; do
    echo "(allow $ops (subpath \"/tmp/probe/dir$i\"))"
    i=$((i + 1))
  done
}

require_any_rule() {
  printf "(allow file-read-data (require-any"
  while read -r p; do
    printf ' (literal "%s")' "$p"
  done
  echo "))"
}

two_require_any_groups() {
  n=$1
  echo "$header"
  random_paths $((2 * n)) | head -n "$n" | require_any_rule
  random_paths $((2 * n)) | tail -n "$n" | require_any_rule
}

literals_on_ops() {
  ops=$(first_ops "$1")
  n=$2
  echo "$header"
  for op in $ops; do
    i=1
    while [ "$i" -le "$n" ]; do
      echo "(allow $op (literal \"/tmp/probe/$op/dir$i/file$i.txt\"))"
      i=$((i + 1))
    done
  done
}

regex_on_ops() {
  op_count=$1
  n=$2
  set -- $(first_ops "$op_count")
  echo "$header"
  i=1
  while [ "$i" -le "$n" ]; do
    for op in "$@"; do
      if [ "$i" -gt "$n" ]; then
        break
      fi
      printf '%s\n' "(allow $op (regex #\"^/tmp/probe/dir$i/.*\\.txt\$\"))"
      i=$((i + 1))
    done
  done
}

seconds_to_compile() {
  start=$(date +%s)
  "$@" | ./sbcompile - >/dev/null 2>&1
  echo "$(( $(date +%s) - start ))s"
}

section "Build"
clang -O2 -o sbcompile sbcompile.c -lsandbox || exit 1
echo "  macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
report "empty profile bytecode" "464" "$(echo "$header" | compile_result)"

section "Limit 1: 64 KiB per filter data object"
report "error message (7,000 subpaths)" "data object length N exceeds maximum (65535)" \
  "$(./gen.sh subpath 7000 | compile_result)"
report "max literal, random 24-char paths" "~2,300" "$(largest_n 1000 4000 random_literals)"
report "max literal, shared prefix" "3,438" "$(largest_n 3000 4000 ./gen.sh literal)"
report "max subpath, shared prefix" "6,540" "$(largest_n 6000 7000 ./gen.sh subpath)"
report "max mach-lookup global-name" "10,886" "$(largest_n 10000 12000 ./gen.sh mach)"
report "6,000 subpaths on 2 ops" "OK" "$(subpaths_on_ops 2 6000 | compile_result)"
report "6,000 subpaths on 4 ops" "OK" "$(subpaths_on_ops 4 6000 | compile_result)"
report "2 require-any groups of 2,000 random literals" "FAIL" \
  "$(two_require_any_groups 2000 | compile_result)"

section "Limit 2: total profile size"
per_op=$(largest_n 1000 4000 literals_on_ops 14)
report "largest 14-op literal profile" "~575 KB" \
  "$per_op/op: $(literals_on_ops 14 "$per_op" | compile_result)"
report "one more literal per op" "FAIL profile too large" \
  "$(literals_on_ops 14 $((per_op + 1)) | compile_result)"
max_regex=$(largest_n 5000 6000 ./gen.sh regex)
report "max regex rules, one op" "~5,545" \
  "$max_regex: $(./gen.sh regex "$max_regex" | compile_result)"
max_regex=$(largest_n 5000 7000 regex_on_ops 14)
report "max regex rules, spread over 14 ops" "~5,545" \
  "$max_regex: $(regex_on_ops 14 "$max_regex" | compile_result)"

if $slow; then
  section "Splitting one operation with guards (slow)"
  report "3,000 prefixes, no guard" "FAIL" "$(./gennix.sh prefix 3000 | compile_result)"
  report "same subpath guard on every rule" "FAIL" "$(./gensplit.sh 3000 500 store | compile_result)"
  report "guard on first hash char" "OK" "$(./gensplit.sh 3000 500 bucketprefix | compile_result)"
  report "distinct guard per 500 rules" "OK" "$(./gensplit.sh 3000 500 unique | compile_result)"
  report "one guard for all 3,000 rules" "FAIL" "$(./gensplit.sh 3000 3000 unique | compile_result)"

  section "Nix darwin builder (slow)"
  report "current form, 3,000 inputs" "FAIL data object" "$(./gennixbuilder.sh current 3000 | compile_result)"
  report "bucket form, 10,000 inputs" "OK 477425" "$(./gennixbuilder.sh bucket 10000 | compile_result)"
  report "bucket form, 10,984 inputs" "OK 524865" "$(./gennixbuilder.sh bucket 10984 | compile_result)"
  report "bucket form, 11,000 inputs" "FAIL profile too large" "$(./gennixbuilder.sh bucket 11000 | compile_result)"

  section "Other observations (slow)"
  report "compile time, 5,000 subpaths" "6s" "$(seconds_to_compile ./gen.sh subpath 5000)"
  report "compile time, 10,000 subpaths" "23s" "$(seconds_to_compile ./gen.sh subpath 10000)"
  report "compile time, 20,000 subpaths" "95s" "$(seconds_to_compile ./gen.sh subpath 20000)"
  report "20,000 regex rules" "CRASH exit=139" "$(./gen.sh regex 20000 | compile_result)"
  report "50,000 literal rules" "CRASH exit=139" "$(./gen.sh literal 50000 | compile_result)"
else
  echo
  echo "Skipped compile-time and crash checks; run with --slow to include them."
fi
