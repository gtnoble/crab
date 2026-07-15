# crab — compression-based mutual-information grep

**crab** is a grep-like CLI tool that selects the *k* most-similar text chunks
(or whole files) from files, directory trees, or stdin, compared against an
input query. Similarity is measured by **mutual information** approximated via
dictionary-preloaded compression.

Two operating modes:

- **Chunk mode** (default) — query is a literal string; input is partitioned
  into fixed-size overlapping chunks; each chunk scored independently.
- **File mode** (`-f` / `--file-mode`) — query is a file path; each target file
  scored as a single unit; output is `filename score`.

## Installation

### System dependencies

```sh
# Debian / Ubuntu
sudo apt install zlib1g-dev liblz4-dev liblzma-dev gnat-13
```

### Build from source

```sh
git clone https://github.com/gtnoble/crab.git
cd crab
alr build
```

The binary lands at `bin/crab`.

## Quick start

```sh
# Top 5 chunks most similar to "error" in a log file
crab -s 200 -k 5 error /var/log/syslog

# Recursive case-insensitive search with LZ4
crab -r -i -a lz4 -s 300 "search term" /path/to/docs/

# Find the 3 least-similar chunks
crab -v -s 150 -k 3 "outlier" data.txt

# Compare a query file against a directory of target files (file mode)
crab -f -r -k 5 template.txt /path/to/candidates/

# File mode with LZMA and custom dictionary size
crab -f -a lzma -D 16777216 reference.txt large_target.bin
```

## How it works

Mutual information is approximated via dictionary-preloaded compression:

```
MI-approx(Q, C) = (|compress(C, dict=∅)| − |compress(C, dict=Q)|
                  + |compress(Q, dict=∅)| − |compress(Q, dict=C)|) / 2
```

where |compress(X, dict=D)| is the compressed size of X in bytes when the
compressor's internal buffers are pre-populated with dictionary D. The empty
dictionary (∅) provides the baseline. Both measurements use identical format
overhead, which cancels out in the subtraction.

This directly approximates I(Q;C) = (K(C) − K(C|Q) + K(Q) − K(Q|C)) / 2.

## Options

| Flag | Description |
|---|---|
| `-h`, `--help` | Print usage summary and exit |
| `--version` | Print version and exit |
| `-a`, `--algorithm ALGO` | Compression algorithm: `deflate` (default), `lz4`, `lzw`, `lzma` |
| `-l`, `--level N` | Compression level (algorithm-dependent) |
| `-D`, `--dict-size N` | LZMA dictionary size in bytes (default: 8 MB) |
| `--lzw-max-codes N` | Max LZW codes (default: 10,000,000; 0 = unbounded) |
| `-s`, `--chunk-size N` | Chunk size in bytes (default: 4096; chunk mode) |
| `-L`, `--chunk-lines N` | Chunk size in lines (optional; chunk mode) |
| `-o`, `--overlap P` | Overlap percentage 0–99 (default: 0) |
| `-k`, `--top N` | Number of results (default: 10) |
| `-r`, `--recursive` | Search directories recursively |
| `-i`, `--ignore-case` | Case-insensitive matching (ASCII only) |
| `-v`, `--invert` | Return least-similar results |
| `-f`, `--file-mode` | Compare query file against target files |
| `--include GLOB` | Include only files matching glob (repeatable) |
| `--exclude GLOB` | Exclude files matching glob (repeatable) |
| `--max-depth N` | Max directory traversal depth |

## Compression backends

| Algorithm | Backend | Window size | Dictionary limit | Level range | Default |
|---|---|---|---|---|---|
| `deflate` | libz | 32 KB | 32 KB | −1..9 | 6 |
| `lz4` | liblz4 | 64 KB | 64 KB | 1..65537 | 1 |
| `lzw` | Pure Ada | unbounded¹ | unbounded¹ | 0 (ignored) | 0 |
| `lzma` | liblzma | user-specified² | user-specified² | 0..9 | 6 |

¹ Bounded to 10M codes (~290 MB) by default; `--lzw-max-codes 0` for unbounded.  
² Default 8 MB; set via `--dict-size`.

## Output format

### Chunk mode

```
## chunk=1 score=1234 file=src/main.adb offset=512
... chunk bytes ...

## chunk=2 score=1100 file=src/utils.adb offset=2048
... chunk bytes ...
```

### File mode

```
path/to/file_a.txt 1234
path/to/file_b.txt 1100
path/to/file_c.txt 987
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Argument parsing error |
| 2 | File I/O error |
| 3 | Compression error |
| 4 | Empty input |

## Building and testing

```sh
# Build the application
alr build

# Build and run tests
cd tests/
alr build
alr run
```

## Documentation

- Man page: `man crab` (installed to section 1)
- [Requirements Specification](requirements/requirements-spec.md)
- [Design Description](design/design-description.md)
- [Project Plan](plan/project-plan.md)

## License

Licensed under MIT OR Apache-2.0 WITH LLVM-exception.

## Author

Garret Noble <garretnoble@gmail.com>
