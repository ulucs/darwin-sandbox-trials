# sandbox-exec profile size limits (macOS 26 / Darwin 25.6, arm64e)

Measured by compiling profiles with `sbcompile` (libsandbox `sandbox_compile_string`).
Applying the profile was NOT tested here; the kernel may enforce further limits.

Re-run everything with `./replicate.sh` (add `--slow` for the guard-splitting,
compile-time and crash checks). The limit and guard-splitting numbers were re-checked
on macOS 27.0.1 (26A434), arm64, as were the compile times except where marked;
the crashes under "Other observations" were not.

## Limit 1: 64 KiB per filter data object

Error: `data object length N exceeds maximum (65535)`

All path/name filters attached to the same operation under the same guard are merged
into one data object (a compressed pattern trie). Its size must fit in 16 bits.

| Rule shape (one operation)                         | Max rules |
|----------------------------------------------------|-----------|
| `literal`, random 24-char paths (no shared prefix) | ~2,300    |
| `literal`, paths with a long shared prefix         | 3,438     |
| `subpath`, shared prefix                           | 6,540     |
| `mach-lookup (global-name ...)`, shared prefix     | 10,886    |

- Shared prefixes compress well; path length matters less than how unique paths are.
- The limit is per operation: the same 6,000 subpaths on 2 or 4 operations compile fine.
- `require-any` does not help: two groups of 2,000 random literals on one operation fail.
- A distinct `require-all` guard does help; see below.

### Splitting one operation with guards

Wrapping filters in `(require-all <guard> ...)` does not create a new operation, but
each distinct guard gets its own data object. Tested with 3,000 random
`/nix/store/<hash>-` prefix rules on `file-read*` (`gensplit.sh`):

| Guard                                                   | Result                    |
|---------------------------------------------------------|---------------------------|
| none                                                    | FAIL, data object 105,532 |
| same `(subpath "/nix/store")` on every rule             | FAIL, data object 105,532 |
| `(prefix "/nix/store/<first hash char>")`               | OK, 107,705 B             |
| a different `(require-not (literal ...))` per 500 rules | OK, 107,217 B             |
| the same `require-not` on all 3,000 rules               | FAIL, data object 105,532 |

- What matters is that the guards differ, not what they match: a meaningless
  `require-not` guard splits just as well as a real prefix.
- This only gets around Limit 1. The split profile is about the same size in total,
  so Limit 2 still applies.

### Nix darwin builder

`gennixbuilder.sh` mimics the profile nix generates for a derivation's store inputs,
with each input as a `subpath` on `file-read* file-write* process-exec`:

| Form                                                          | Max store inputs |
|---------------------------------------------------------------|------------------|
| `current`: flat, new `allow` form every 16 KiB of source       | < 3,000 (Limit 1) |
| `bucket`: one `require-all (prefix "/nix/store/<c>")` per first hash char | 10,984-11,000 (Limit 2) |

- Splitting the source into several `allow` forms on the same operations does not
  help: they still share one data object (3,000 inputs: 143,905 bytes).
- Bucketing costs about 48 B of bytecode per input: 10,000 inputs compile to
  477,425 B, 10,984 to 524,865 B; 11,000 fails with `profile too large`.

## Limit 2: total profile size, ~525-625 KB of bytecode

Error: `profile too large`

- 14 ops x 2,309 distinct literals = 568,311 bytes OK; 14 x 2,310 fails.
- `regex` rules are about 100 bytes of bytecode each (vs 6-20 for literal/subpath),
  so regexes hit this first: max 5,545 regex rules on one op (624,601 B), 5,965
  spread round-robin over 14 ops (624,489 B).
- The largest passing profile varies by rule shape: ~525 KB for bucketed nix inputs,
  ~568 KB for literals, ~625 KB for regexes. So the cap is not simply bytecode
  length; most likely a 16-bit offset into part of the bytecode. A generator cannot
  rely on a byte threshold; it has to compile and check, or stay well below ~500 KB.

## Compile time

Compile time is roughly quadratic in the number of rules: doubling the rules
multiplies the time by about 4.

| `subpath` rules, shared prefix, one op | Time   | t / n²        |
|----------------------------------------|--------|---------------|
| 5,000                                  | 5.9 s  | 0.23 µs       |
| 6,000                                  | 8.4 s  | 0.23 µs       |
| 10,000                                 | 23.4 s | 0.23 µs       |
| 20,000 (old run, not re-checked)       | 95 s   | 0.24 µs       |

- Approximation: **t ≈ 0.23 µs × n²** for shared-prefix subpaths. Random
  `/nix/store` prefixes are about half that (1,000: 0.12 s, 2,000: 0.48 s,
  4,000: 1.98 s; ≈ 0.12 µs × n²).
- Bucketed nix builder profiles near 11,000 inputs take ~36 s each.

### Splitting does not speed it up

Measured with only the compile timed (profiles generated to a file first).

6,000 shared-prefix subpaths on one op, split into groups with
`(require-all <distinct guard> (require-any ...))`:

| Guards     | Time   |
|------------|--------|
| none, flat | 8.4 s  |
| 1          | 8.4 s  |
| 4          | 8.1 s  |
| 16         | 21.7 s |
| 64         | 79.4 s |

- There is no k-fold speedup from k groups. Past a few guards, each extra guard adds
  about 1.2 s here, so many small groups are much slower than one big one.
- Where the guard goes matters a lot. With 2,000 random prefixes and 4 guards, one
  `require-all` per group (guard wrapping a `require-any`) compiled in 1 s; the same
  guard repeated on every rule, as `gensplit.sh` does, took 56 s for identical
  bytecode (71,633 B). With 100 rules per guard, 1,000 rules took 11.7 s and 2,000
  took 115 s.
- So for Limit 1, use as few guards as fit under 64 KiB each, and put each guard
  around its group, not on each rule (`gennixbuilder.sh bucket` already does).

## Other observations

- Profiles with 20,000+ regex or 50,000 literal rules crash libsandbox (SIGSEGV,
  exit 139) instead of returning an error.
