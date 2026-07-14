---
name: crab
description: "Semantic search over codebases and text using mutual-information-based similarity (compression distance). Invoke crab when looking for conceptually related code or text that grep/ripgrep would miss — finding similar functions, duplicate-ish logic, related documentation, or any content where meaning matters more than exact string matching. Two modes: chunk mode (query is a literal string, files partitioned into overlapping chunks ranked by similarity) and file mode (-f, query is a file, each target file scored as a unit). Keywords: crab, semantic search, mutual information, compression distance, similarity, grep, code search, semantic grep, NCD, chunking, file comparison, nearest-neighbor."
---

# crab — Compression-Based Semantic Search

Use `crab` when you need to find text that is *conceptually similar* to a query,
not just text that matches a regex or substring.  `crab` uses dictionary-preloaded
compression to measure mutual information — the amount of shared structure between
two texts.  It finds things that *mean* the same thing even if they use different
words, variable names, or formatting.

**Contrast with grep/ripgrep:**  grep tells you *is this pattern present?*  crab
tells you *how similar is this chunk to my query?*  Use grep for exact matches;
use crab when you want the top-k most-related pieces of text.

## When to Use Crab

- **Find similar functions:**  Given a function body as a query, find other
  functions in the codebase that do roughly the same thing (different naming,
  different style).
- **Locate related documentation:**  Given a doc comment, find source files
  whose implementation matches that description.
- **Detect near-duplicates:**  Query a block of code and see if there's a copy
  elsewhere that's been refactored or reformatted.
- **Explore a codebase by example:**  "Show me code like this" without knowing
  the right keywords.
- **Rank files by relevance to a reference document:**  File mode with a spec or
  design doc as query file to find the most-related implementation files (or
  vice versa).

## How It Works (One Sentence)

Crab compresses the query with the target chunk as a dictionary and vice versa,
then subtracts from the baseline (un-dictionaried) compressed size.  The
difference is the mutual-information approximation.  Higher score = more shared
structure.

This is not embedding-based semantic search.  It's information-theoretic:
content that compresses better against a shared model is more similar.  It
works across languages, file formats, and encodings without training.

## Installation / Prerequisites

`crab` must be built and installed.  From the project root:

```sh
alr build
# binary at bin/crab — ensure it's on PATH or use the full path
```

System dependencies: `libz` (zlib1g-dev), `liblz4` (liblz4-dev), `liblzma`
(liblzma-dev).

## Two Operating Modes

### Chunk Mode (default)

Query is a **literal string**.  Each target file is split into fixed-size
overlapping chunks.  Each chunk scored independently against the query string.
Top-k chunks ranked by score are output with headers showing rank, score, file,
and offset.

```
crab -s 200 -k 5 "some query string" file1.txt file2.txt
crab -r -s 300 "query" /path/to/dir/
```

Required flags: **-s** (chunk size in bytes) or **-L** (chunk size in lines).

### File Mode (-f / --file-mode)

Query is a **file path**.  Each target file scored as a whole unit — no
chunking.  Output is one line per file: `filepath score`.  Ideal for "find
files most similar to this reference file."

```
crab -f -r -k 10 reference.txt candidate_dir/
crab -f -a lz4 reference.bin file_a.bin file_b.bin
```

No chunk-size flag needed; -s/-L/-o are ignored in file mode.

## Key Flags

| Flag | Meaning |
|---|---|
| `-a, --algorithm` | Compression backend: `deflate` (default), `lz4`, `elz`, `lzma` |
| `-s, --chunk-size N` | Chunk size in bytes (chunk mode only, required) |
| `-L, --chunk-lines N` | Chunk size in lines (chunk mode only; alternative to -s) |
| `-o, --overlap P` | Overlap 0-99% (default 0). 50% = each chunk starts halfway into prior |
| `-k, --top N` | Number of results (default 10) |
| `-r, --recursive` | Walk directory trees |
| `-i, --ignore-case` | ASCII case folding (original bytes preserved in output) |
| `-v, --invert` | Return *least*-similar results (ascending score) |
| `-f, --file-mode` | Query is a file path; score whole files |
| `-l, --level N` | Compression level (deflate: -1..9, lz4: 1..65537, lzma: 0..9; default 6) |
| `-D, --dict-size N` | LZMA dictionary size in bytes (default 8M; lzma only) |
| `--elz-max-codes N` | Max ELZ string-table codes (default 10M; 0 = unbounded; elz only) |
| `--include GLOB` | Only files whose basename matches (repeatable) |
| `--exclude GLOB` | Exclude matching files (repeatable; overrides --include) |
| `--max-depth N` | Max directory depth (0 = root only) |
| `--help` | Full usage |

## Algorithm Selection

Choose based on your file size and needs:

| Algorithm | Window | Best For |
|---|---|---|
| `deflate` (default) | 32 KB | Small chunks up to ~32 KB; good general default |
| `lz4` | 64 KB | Speed; medium-sized chunks up to ~64 KB |
| `elz` | 10M codes (~290 MB; 0 = unbounded) | Large files/chunks, no size penalty; pure Ada, slightly slower; bounded by default via LRU eviction |
| `lzma` | configurable (default 8 MB) | Large files/chunks, strongest compression; slower, more memory |

**Window-size warning:** When a chunk exceeds the algorithm's window size,
crab warns to stderr that scoring accuracy may be reduced.  Switch to `elz`
or increase `lzma` dict size to avoid this.  `elz` is bounded to 10M codes
by default (~290 MB); set `--elz-max-codes 0` for unbounded mode.

For file mode with large files (≥ 100 KB), **always use elz or lzma** to
get meaningful scores.

## Practical Recipes

### Find code similar to a pattern

```sh
# Query with a fragment of code, search a codebase
crab -r -s 400 -k 10 "if err != nil { return nil, err }" src/

# Line-based chunking for code (respects line boundaries)
crab -r -L 10 -k 10 "your query pattern" src/
```

### File-mode: most-similar files to a reference

```sh
# Which source files are most like this spec?
crab -f -r -a elz -k 5 design_spec.md src/

# Find duplicate-ish files in a directory
crab -f -r -a lzma -k 20 reference_config.yaml configs/
```

### Case-insensitive search

```sh
crab -r -i -s 300 "Error: connection refused" /var/log/
```

### Least-similar (outlier detection)

```sh
# Find the 5 chunks least like the norm
crab -v -s 200 -k 5 "normal operational log pattern" log.txt
```

### Filter by file type

```sh
crab -r -s 400 --include "*.go" --exclude "*_test.go" "query" src/
```

### Stdin input

```sh
# Pipe data in; chunk size still required, path shows (stdin)
some_command | crab -s 200 -k 5 "query"
```

## Interpreting Output

### Chunk mode output

```
## chunk=1 score=142 file=src/main.go offset=2048
<raw chunk bytes>

## chunk=2 score=95 file=src/util.go offset=512
<raw chunk bytes>
```

- **score:** Signed integer; higher = more similar.  Roughly the number of
  shared-information bytes.  Negative scores are possible and valid — they're
  still ranked.
- **offset:** Byte offset (or line offset with -L) into the file.  0-based.
- Results sorted descending by score (ascending with -v).

### File mode output

```
src/implementation.go 142
src/test_helpers.go 95
src/legacy_wrapper.go -11
```

- One `path score` pair per line, sorted descending by score.

### Stderr diagnostics

- **Window-size warning:**  `WARNING: file X size Y exceeds Z window size for
  algorithm A — scoring accuracy may be reduced`
- **Errors:**  Exit codes 1-4 signal arg parse / I/O / compression / empty-input
  failures.  Always check stderr when crab exits non-zero.

## Tips for Good Results

1. **Query quality matters.**  Crab compares *text*, not abstract concepts.
   A query that's too short (e.g., "error") may not contain enough structure
   for the compressor to build useful models.  Aim for at least 50-100 bytes.
2. **Match chunk size to query size.**  If your query is 200 bytes, use
   `-s 200` or similar.  Chunks much larger than the query dilute the signal.
3. **Overlap helps avoid boundary misses.**  With `-o 50`, the same content
   appears in adjacent chunks, so you won't miss a match that straddles a
   chunk boundary.
4. **For code search, prefer line-based chunking (-L).**  It keeps line
   boundaries intact and typically produces more meaningful chunks.
5. **File mode with large files needs elz or lzma.**  Deflate's 32 KB window
   can't model structure beyond that limit.
6. **Scores are relative, not absolute.**  Compare scores within the same
   invocation.  Scores from different algorithm/size combinations aren't
   comparable.
