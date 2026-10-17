#!/bin/sh
# gen.sh <kind> <n> : emit a profile with n rules of the given kind
kind=$1
n=$2

echo '(version 1)(deny default)'

i=1
while [ "$i" -le "$n" ]; do
  case $kind in
    literal)  echo "(allow file-read* (literal \"/tmp/probe/dir$i/file$i.txt\"))" ;;
    subpath)  echo "(allow file-read* (subpath \"/tmp/probe/dir$i\"))" ;;
    regex)    printf '%s\n' "(allow file-read* (regex #\"^/tmp/probe/dir$i/.*\\.txt\$\"))" ;;
    mach)     echo "(allow mach-lookup (global-name \"com.example.service$i\"))" ;;
    deny)     echo "(deny file-write* (subpath \"/tmp/probe/dir$i\"))" ;;
    mixedops) echo "(allow file-read* file-write* (subpath \"/tmp/probe/dir$i\"))" ;;
  esac
  i=$((i + 1))
done
