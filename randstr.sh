#!/bin/sh
# randstr.sh <count> <length> [alphabet] : count random strings, same sequence on every run (seed 42)
# alphabet defaults to the nix store hash alphabet
count=$1
len=$2
alphabet=${3:-0123456789abcdfghijklmnpqrsvwxyz}

awk -v count="$count" -v len="$len" -v alphabet="$alphabet" '
BEGIN {
  srand(42)
  for (i = 1; i <= count; i++) {
    s = ""
    for (j = 1; j <= len; j++) {
      pick = int(rand() * length(alphabet)) + 1
      s = s substr(alphabet, pick, 1)
    }
    print s
  }
}'
