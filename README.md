# darwin sandbox trials

Some bash scripts to test the limits of `sandbox-exec`. Run `replicate.sh` to watch the tests and re-validate the findings.

One previously known limit was the 64KB limit per data object, and the total profile limit of around 600KBs. The information that was new to me were:

- data objects are compiled, so the 64KB limit doesn't necessarily mean 64k characters.
- the compiled structure is a trie, so you can fit a lot of files if you have shared prefixes
- even better, the compiler optimizes by deduplicating, so `(allow file-read* (subpath "/nix/store"))` will allow you to insert as many `(allow file-read* (subpath "/nix/store/<hash>-<name>/"))`s into the data object as you'd like (as long as you don't hit the object data compiler's limits) as seen in CVE-2026-110451
- there is a way to split data objects: when you have a common prefix for a subset of paths, wrapping the paths inside a `(require-all (prefix "/nix/store/a") (require-any ...))` results in separate data object, with its own 64KB limit
- due to the total profile limit, this only 10x'es the number of store paths we can put inside the sandbox instead of 32x'ing it (we can have 32 buckets)
- data object compilation is quadratic, so splitting paths into different data objects might even save you time

Full results can be found in [LIMITS.md], but beware--this is the only file written by me in this repository. Rest is AI slop.
