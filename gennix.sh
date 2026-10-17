#!/bin/sh
# gennix.sh <style> <n> [group] : n unique /nix/store hashes in the given rule style
# style: subpath | prefix | regex | altregex (group hashes per regex, default 100)
here=$(dirname "$0")
style=$1
n=$2
group=${3:-100}

package_name() {
  case $(($1 % 6)) in
    0) echo glibc-2.40 ;;
    1) echo bash-5.2p37 ;;
    2) echo coreutils-9.5 ;;
    3) echo python3-3.12.8 ;;
    4) echo openssl-3.3.2 ;;
    5) echo zlib-1.3.1 ;;
  esac
}

echo '(version 1)(deny default)'

"$here/randstr.sh" "$n" 32 | {
  i=0
  pending=""
  pending_count=0
  while read -r hash; do
    i=$((i + 1))

    case $style in
      subpath)
        echo "(allow file-read* (subpath \"/nix/store/$hash-$(package_name $i)\"))"
        ;;
      prefix)
        echo "(allow file-read* (prefix \"/nix/store/$hash-\"))"
        ;;
      regex)
        echo "(allow file-read* (regex #\"^/nix/store/$hash-\"))"
        ;;
      altregex)
        if [ -z "$pending" ]; then
          pending=$hash
        else
          pending="$pending|$hash"
        fi
        pending_count=$((pending_count + 1))

        if [ "$pending_count" -eq "$group" ] || [ "$i" -eq "$n" ]; then
          echo "(allow file-read* (regex #\"^/nix/store/($pending)-\"))"
          pending=""
          pending_count=0
        fi
        ;;
    esac
  done
}
