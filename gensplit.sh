#!/bin/sh
# gensplit.sh <n> <bucket> <mode> : prefix rules bucketed so each bucket gets its own data object
# mode: store | bucketprefix | anything else (unique require-not guard per bucket of <bucket> rules)
here=$(dirname "$0")
n=$1
bucket_size=$2
mode=$3

echo '(version 1)(deny default)'

"$here/randstr.sh" "$n" 32 | {
  i=0
  while read -r hash; do
    i=$((i + 1))
    bucket=$(( (i - 1) / bucket_size ))
    rest=${hash#?}
    first_char=${hash%"$rest"}

    case $mode in
      store)        guard='(subpath "/nix/store")' ;;
      bucketprefix) guard="(prefix \"/nix/store/$first_char\")" ;;
      *)            guard="(require-not (literal \"/nonexistent/$bucket\"))" ;;
    esac

    echo "(allow file-read* (require-all $guard (prefix \"/nix/store/$hash-\")))"
  done
}
