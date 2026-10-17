#!/bin/sh
# bisect.sh <kind> <lo_ok> <hi_fail> : largest n that compiles
kind=$1
lo=$2
hi=$3

while [ $((hi - lo)) -gt 1 ]; do
  mid=$(( (lo + hi) / 2 ))
  if ./gen.sh "$kind" "$mid" | ./sbcompile - >/dev/null 2>&1; then
    lo=$mid
  else
    hi=$mid
  fi
done

echo "$kind max=$lo"
./gen.sh "$kind" "$lo" | ./sbcompile -
./gen.sh "$kind" "$hi" | ./sbcompile -
