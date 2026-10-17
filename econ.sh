#!/bin/sh
# econ.sh: compare compiled size of the same string set under different encodings
N=${1:-1000}
header='(version 1)(deny default)'

paths_file=$(mktemp)
sorted_file=$(mktemp)
trap 'rm -f "$paths_file" "$sorted_file"' EXIT

./randstr.sh "$N" 24 abcdefghijklmnopqrstuvwxyz0123456789 | sed 's|^|/|' > "$paths_file"
LC_ALL=C sort "$paths_file" > "$sorted_file"

# Reads a profile on stdin, prints its bytecode size or FAIL.
compiled_size() {
  result=$(./sbcompile -)
  case $result in
    FAIL*) echo FAIL ;;
    *)
      size=${result##*bytecode_bytes=}
      echo "${size%% *}"
      ;;
  esac
}

print_row() {
  label=$1
  size=$2
  if [ "$size" = FAIL ]; then
    printf "%-48s FAIL\n" "$label"
    return
  fi
  tenths=$(( ((size - baseline) * 20 / N + 1) / 2 ))
  printf "%-48s %7s B  %4d.%d B/str\n" "$label" "$size" $((tenths / 10)) $((tenths % 10))
}

one_rule_per_path() {
  filter=$1
  file=$2
  echo "$header"
  while read -r p; do
    echo "(allow file-read-data ($filter \"$p\"))"
  done < "$file"
}

literals_in_require_any() {
  echo "$header"
  printf "(allow file-read-data (require-any"
  while read -r p; do
    printf ' (literal "%s")' "$p"
  done < "$paths_file"
  echo "))"
}

literal_with_many_args() {
  echo "$header"
  printf "(allow file-read-data (literal"
  while read -r p; do
    printf ' "%s"' "$p"
  done < "$paths_file"
  echo "))"
}

regex_per_path() {
  suffix=$1
  echo "$header"
  while read -r p; do
    printf '(allow file-read-data (regex #"^%s%s"))\n' "$p" "$suffix"
  done < "$paths_file"
}

regex_alternation() {
  per_regex=$1
  echo "$header"
  group=""
  count=0
  while read -r p; do
    if [ -z "$group" ]; then
      group=${p#/}
    else
      group="$group|${p#/}"
    fi
    count=$((count + 1))
    if [ "$count" -eq "$per_regex" ]; then
      printf '(allow file-read-data (regex #"^/(%s)$"))\n' "$group"
      group=""
      count=0
    fi
  done < "$paths_file"
  if [ -n "$group" ]; then
    printf '(allow file-read-data (regex #"^/(%s)$"))\n' "$group"
  fi
}

baseline=$(echo "$header" | compiled_size)
print_row "baseline (empty profile)" "$baseline"

for filter in literal subpath prefix; do
  print_row "$filter, one rule per string" "$(one_rule_per_path $filter "$paths_file" | compiled_size)"
done
print_row "literal, sorted order" "$(one_rule_per_path literal "$sorted_file" | compiled_size)"
print_row "literal, one rule with require-any" "$(literals_in_require_any | compiled_size)"
print_row "literal, multi-arg (literal p1 p2 ...)" "$(literal_with_many_args | compiled_size)"

print_row "regex ^p\$, one rule per string" "$(regex_per_path '$' | compiled_size)"
print_row "regex ^p (prefix semantics), one per string" "$(regex_per_path '' | compiled_size)"
for k in 10 50 100 200; do
  print_row "regex alternation, $k strings per regex" "$(regex_alternation $k | compiled_size)"
done
