# Software Requirements Specification — Crab

**Project:** Crab — Compression-based mutual-information grep
**Date:** 2026-06-18
**Version:** 1.2 — stack trace on fatal error
**Component:** `crab` (sole component)

---

## 1. Scope

### 1.1 Component Identifier

`crab` — a CLI executable that selects and outputs the *k* chunks of text from input
files, directory trees, or stdin that have the greatest (or, optionally, least) mutual
information with a user-supplied query string or query file. Mutual information is
approximated via a compression-based measure. Two operating modes are supported:
**chunk mode** (query string vs chunked input) and **file mode** (query file vs whole
target files).

### 1.2 System Context

Crab is a standalone command-line utility. It has no runtime dependencies beyond the
system libraries `libz`, `liblz4`, and `liblzma` (loaded dynamically by the OS linker). It
interacts with the user via command-line arguments, stdin, stdout, stderr, and
exit codes.

### 1.3 Document Overview

Section 3 defines all functional and non-functional requirements. Section 4 provides
the qualification provisions (traceability from requirements to verification methods).
Section 5 traces requirements to their sources in the project brief.

---

## 2. Referenced Documents

| Document | Reference |
|---|---|
| Project Plan | `plan/project-plan.md` v1.0-draft |
| Project Brief | User description (2026-06-18) and subsequent clarifications |

---

## 3. Requirements

### 3.1 Capability Requirements

#### CLI Invocation

**REQ-001 — Argument parsing**
`crab` shall accept command-line arguments specifying: the query string (or query
file path in file mode), the compression algorithm, the compression level, the
chunk size (in bytes or lines), the chunk overlap percentage, the number of
results to return (*k*), a recursive-search flag, a case-insensitivity flag,
include and exclude glob patterns, a maximum traversal depth, an inversion flag,
a file-mode flag, an LZMA dictionary-size flag, and zero or more input file or directory paths.

**REQ-002 — --help / -h**
`crab` shall support a `--help` (and `-h`) flag that prints a usage summary to
stdout and exits with code 0. The usage message shall list all available flags
and arguments with a brief description of each.

**REQ-003 — --version**
`crab` shall support a `--version` flag that prints the crate version to stdout and
exits with code 0.

**REQ-004 — Query**
`crab` shall accept a non-empty query as the first positional argument. In chunk
mode (default), the query is a literal string. In file mode (`-f`/`--file-mode`),
the query is a file path whose contents are read and used as the query. If the
query is empty or the query file is unreadable, `crab` shall exit with a non-zero
exit code and an error message on stderr.

#### Operating Modes

**REQ-063 — File mode flag**
`crab` shall accept a `--file-mode` (or `-f`) flag. When set:

- The first positional argument shall be interpreted as a **query file path**
  rather than a literal query string. The file's contents are read and used as
  the query for compression-based scoring.
- Each target file shall be scored as a **single unit** — no chunking is
  performed. The entire file content is passed to the scorer as one chunk.
- The `--chunk-size` (`-s`), `--chunk-lines` (`-L`), and `--overlap` (`-o`)
  flags are not required and have no effect in file mode.
- The query file shall be excluded from the target file list if it appears
  there (matched by path).
- Output shall use the file-mode format (REQ-066): one line per file with
  the file path and score, sorted descending by score.

**REQ-064 — File mode query**
In file mode, the query is read from the specified file. The query file's
contents are loaded as a compression dictionary once at initialisation time
and reused for scoring every target file. Case folding (`-i`) applies to the
query file contents when set.

**REQ-065 — File mode scoring**
In file mode, each target file is scored as a single unit using the same
MI‑approx formula as chunk mode: `(|compress(C, dict=∅)| − |compress(C, dict=Q)| + |compress(Q, dict=∅)| − |compress(Q, dict=C)|) / 2`,
where *C* is the entire target file content and *Q* is the query file content.
The scorer's persistent stream objects are reused across all target files.

**REQ-066 — File mode output format**
In file mode, output shall consist of one line per result:

> `filepath score`

Where *filepath* is the path of the target file and *score* is the signed
integer MI‑approx score. Results shall be sorted in descending order of score
(highest similarity first) unless `--invert` is set, in which case results
shall be sorted in ascending order. No chunk headers, no chunk data, no blank
line separators — one line per file only.

#### Window-Size Warning

**REQ-067 — Window-size warning**
When using a compression algorithm with a fixed sliding-window size (DEFLATE: 32 KB; LZ4: 64 KB; LZMA: user-specified dictionary size,
default 8 MB), `crab` shall emit a warning to stderr if any input file
or chunk exceeds the window size. The warning shall identify the file path,
its size in bytes, the algorithm name, and the window size, and shall note
that scoring accuracy may be reduced. The warning shall not prevent
processing; the file or chunk is still scored and may appear in results.
LZW has no fixed window size and shall not produce this warning.
For LZMA, the window size equals the dictionary size for the selected
compression level; the warning shall be emitted when input exceeds that
level's dictionary size.

The warning applies in both operating modes:
- **Chunk mode:** when a file's total size exceeds the window size (the
  dictionary cannot cover the full file, though individual chunks may still
  fit within the window).
- **File mode:** when the query file or any target file exceeds the window
  size.

#### Case Sensitivity

**REQ-047 — Case insensitivity flag**
`crab` shall accept an `--ignore-case` (or `-i`) flag. When set:

- The query string (or query file contents in file mode) and all input text
  shall be case-folded to lowercase before compression. This makes the
  MI‑approx score insensitive to ASCII letter case (A–Z folded to a–z).
  Non-ASCII bytes are passed through unchanged.
- Case folding shall apply to all input sources: files, directory traversal,
  and stdin.
- In chunk mode, the original (not folded) bytes shall be preserved for
  output (REQ-030): the header shows the folded score; the chunk content
  output is the original bytes from the input. In file mode, only the score
  is output — no original bytes are emitted.

#### Input Sources

**REQ-005 — File input**
`crab` shall read input text from one or more regular files specified as positional
arguments. Each file shall be processed independently: chunked and scored (chunk
mode), or scored as a whole (file mode). The top-*k* accumulator is shared across
all files. Files are processed in the order given on the command line (or Scanner
traversal order with `-r`; see REQ-043). No concatenation of files is performed.
Files may be further filtered by include/exclude globs (see REQ-049, REQ-050).

**REQ-006 — Stdin input**
When no file or directory arguments are provided and the recursive flag is not
set, `crab` shall read input text from standard input until EOF. This enables
pipeline usage. In chunk mode, stdin is chunked and scored. In file mode, stdin
is treated as a single target file compared against the query file. Case folding
(REQ-047) applies to stdin input when `-i` is set.

**REQ-007 — Input encoding**
`crab` shall treat input as a sequence of octets (bytes). It does not interpret
character encodings. Chunk boundaries (in chunk mode) shall be defined in terms
of byte counts or line counts.

**REQ-008 — Missing or unreadable files**
If any specified file cannot be opened for reading, `crab` shall print an error
message to stderr and exit with a non-zero exit code.

#### Directory and Recursive Search

**REQ-041 — Recursive search flag**
`crab` shall accept a `--recursive` (or `-r`) flag. When set:

- Each directory given as a positional argument shall be traversed recursively;
  all regular files encountered are read as input.
- If no file or directory arguments are given, the current working directory
  (`"."`) shall be searched recursively.
- Stdin input (REQ-006) is disabled; the flag implies directory-based input.
- Without `-r`, if a positional argument is a directory, `crab` shall print an
  error message to stderr and exit with a non-zero exit code (matching the
  conventional grep behavior).

**REQ-042 — Directory traversal scope**
When traversing a directory, `crab` shall descend into every subdirectory and
read every regular file encountered. If `--max-depth` is set, descent shall stop
at the specified depth (see REQ-053). Special directory entries `"."` and `".."`
shall be skipped during traversal.

**REQ-043 — Traversal order**
Files encountered during directory traversal shall be processed in a deterministic
order: lexicographic sort by path (using byte-value ordering), depth-first. This
ensures reproducible results across invocations.

**REQ-044 — Symlink handling**
`crab` shall follow symbolic links encountered during directory traversal, whether
they point to files or directories. Symlinks passed directly as command-line
arguments shall be followed and processed as their target type (file or directory).

**REQ-045 — Traversal error handling**
If a directory or file cannot be accessed during traversal (e.g., permission
denied), `crab` shall print a warning message to stderr identifying the path and
the reason, then continue processing the remaining accessible files. The tool
shall exit with code 0 if at least some input was successfully read and processed.
If no files were readable at all, the tool shall exit with a non-zero code (code 2,
I/O error).

**REQ-046 — Empty directory**
If the recursive flag is set and the traversal encounters no regular files (e.g.,
an empty directory tree), the tool shall behave as for empty input (REQ-014): print
a message to stderr and exit with a non-zero exit code.

#### File Filtering

**REQ-049 — Include glob**
`crab` shall accept a `--include GLOB` argument, repeatable, specifying shell-style
glob patterns. When at least one `--include` is given, only files whose filename
(basename) matches any of the patterns shall be processed during recursive traversal
or when directory arguments are provided. If no `--include` is given, all files are
included by default.

**REQ-050 — Exclude glob**
`crab` shall accept an `--exclude GLOB` argument, repeatable, specifying shell-style
glob patterns. Files whose filename (basename) matches any exclude pattern shall be
skipped. Excludes are applied after includes: if a file matches both an include and
an exclude pattern, it is excluded.

**REQ-051 — Glob pattern syntax**
Glob patterns shall support the following wildcard characters:

- `*` — matches any sequence of zero or more characters (excluding directory
  separators, which are not present in basename matching)
- `?` — matches exactly one character
- `[...]` — matches any one character in the bracket expression; `[!...]` negates

Pattern matching shall be case-sensitive unless `--ignore-case` is also set, in
which case pattern matching against filenames is also case-insensitive.

**REQ-052 — Include/exclude with non-recursive mode**
Include and exclude globs shall apply only when `-r` is active or when a directory
is given as a positional argument. When processing explicitly-named regular files
(no `-r`, no directory arguments), include/exclude globs shall have no effect: all
named files are processed.

#### Depth Limiting

**REQ-053 — Maximum depth**
`crab` shall accept a `--max-depth N` argument where *N* is a non-negative integer
specifying the maximum recursion depth during directory traversal. Depth counting
shall be:

- Depth 0: only the explicitly-named files and directories (or the default `"."`
  directory when no paths are given with `-r`). Files passed directly on the
  command line are always at depth 0 and are always processed regardless of the
  `--max-depth` setting.
- Depth 1: depth-0 items plus immediate children of named directories.
- Depth *N*: depth 0 through *N* levels of subdirectories below named directories.

**REQ-054 — No depth limit default**
When `--max-depth` is not specified, traversal shall have no depth limit (subject
only to symlink-cycle detection per risk register R5).

#### Chunking (Chunk Mode Only)

**REQ-009 — Fixed-size chunks**
In chunk mode, `crab` shall partition the input text into fixed-size chunks of *S*
bytes, where *S* is the chunk size specified by the user. The last chunk may be
shorter if fewer than *S* bytes remain.

**REQ-010 — Chunk size parameter**
`crab` shall accept a `--chunk-size N` (or `-s N`) argument where *N* is a positive
integer specifying the chunk size in bytes. Required in chunk mode; ignored in file
mode.

**REQ-011 — Chunk overlap**
Consecutive chunks shall overlap by *O* percent of the chunk size, where *O* is
specified by `--overlap P` (or `-o P`). An overlap of 0% produces adjacent
non-overlapping chunks. An overlap of 50% means each successive chunk starts
*S × 50%* bytes after the start of the previous chunk.

**REQ-012 — Overlap range**
`crab` shall reject overlap values outside the range [0, 99] with an error message
and non-zero exit code. 100% overlap is explicitly excluded to prevent infinite
chunking. Overlap is ignored in file mode.

**REQ-013 — Single chunk — input shorter than chunk size**
If the total input is shorter than the chunk size, `crab` shall treat the entire
input as a single chunk.

**REQ-014 — Minimum input**
If the input is empty (zero bytes), `crab` shall print a message to stderr indicating
no chunks could be formed and exit with a non-zero exit code.

**REQ-059 — Line-based chunk size parameter**
`crab` shall accept a `--chunk-lines N` (or `-L N`) argument where *N* is a
positive integer specifying the chunk size in lines. This flag is mutually
exclusive with `--chunk-size` (`-s`); exactly one of the two must be provided
in chunk mode. In file mode, neither is required.

**REQ-060 — Line-based chunking semantics**
When `--chunk-lines` is specified, `crab` shall partition the input text into
chunks of *N* consecutive lines. A line is defined as zero or more bytes
terminated by a newline character (ASCII 0x0A, `\n`). The final line of the
input need not be newline-terminated; any trailing bytes after the last
newline shall be treated as a line. The last chunk may contain fewer than *N*
lines if insufficient lines remain in the input.

**REQ-061 — Line-based overlap**
When `--chunk-lines` is used with `--overlap`, the overlap percentage shall be
applied to the chunk line count. The step between successive chunks (in lines)
shall be `max(1, ⌊N × (100 − overlap) / 100⌋)`. Overlap values shall be
constrained to [0, 99] as per REQ-012. Edge cases for empty input (REQ-014)
and input shorter than the configured chunk size (REQ-013) apply equivalently
to line-based chunking.

**REQ-062 — Line-mode offset semantics**
When `--chunk-lines` is specified (REQ-059), the `offset=O` field in the output
header (REQ-029) shall report the chunk's starting position as a 0‑based line
offset (line number) within the source file, rather than a byte offset. For
stdin input, *O* is the 0‑based line offset from the beginning of the stream.
Tie-breaking within a file (REQ-032) shall also use line offsets: among chunks
with equal scores in the same file, the chunk with the lower line offset ranks
higher.

#### Compression

**REQ-015 — Compression algorithm selection**
`crab` shall accept a `--algorithm ALGO` (or `-a ALGO`) argument. Supported values
are `deflate`, `lz4`, `lzw`, and `lzma`. The argument shall be case-insensitive.

**REQ-016 — DEFLATE compression**
When `deflate` is selected, `crab` shall compress strings using the DEFLATE
algorithm via the streaming API from `libz`
(`deflateInit`/`deflateSetDictionary`/`deflate`/`deflateEnd`). Compression uses
the standard zlib wrapper format (zlib header + DEFLATE data + Adler-32 checksum).
The dictionary (previously-compressed reference data) is loaded via
`deflateSetDictionary` before each compression call. The DEFLATE sliding window
is 32 KB.

**REQ-017 — LZ4 compression**
When `lz4` is selected, `crab` shall compress strings using the LZ4 block
compression algorithm via the streaming dictionary API from `liblz4`
(`LZ4_createStream`/`LZ4_loadDict`/`LZ4_compress_fast_continue`/`LZ4_freeStream`).
The dictionary is loaded via `LZ4_loadDict` before each compression call. The
LZ4 dictionary limit is 64 KB.


**REQ-069 — LZMA compression**
When `lzma` is selected, `crab` shall compress strings using the LZMA
algorithm via the streaming API from `liblzma`
(`lzma_easy_encoder`/`lzma_code`/`lzma_end`). The dictionary is loaded
by compressing the query through the encoder before each target compression.
The LZMA dictionary size is set via the `--dict-size` flag (see REQ-070).
The default dictionary size is 8 MB.

**REQ-070 — LZMA dictionary size**
`crab` shall accept a `--dict-size N` (or `-D N`) argument where *N* is a
positive integer specifying the LZMA dictionary size in bytes. This flag is
only valid when `--algorithm lzma` is selected; if specified with any other
algorithm, `crab` shall print an error message to stderr and exit with a
non-zero exit code. The default dictionary size is 8,388,608 bytes (8 MB).
The dictionary size shall be passed to `lzma_stream_encoder` via the
`lzma_options_lzma.dict_size` field. The dictionary size also determines
the sliding-window size for the window-size warning (REQ-067).


**REQ-018 — Compression level**
`crab` shall accept a `--level N` (or `-l N`) argument specifying the compression
level:

- For DEFLATE: an integer in the range [−1, 9], where 1 is fastest and 9 produces
  the best compression. A value of 0 selects the zlib default (level 6). A value of
  −1 selects no compression (stored blocks only).
- For LZ4: the level is passed via the *acceleration* parameter
  to the streaming dictionary API (`LZ4_compress_fast_continue`).
  The range is [1, 65537]; higher values are faster but
  produce larger output. The default is 1 (best compression).
- For LZW: the level is accepted for interface compatibility but ignored
  (LZW has no compression-level tuning).
- For LZMA: an integer in the range [0, 9], where 0 is fastest and 9 produces
  the best compression. The default is 6. The dictionary size is controlled
  independently via the `--dict-size` flag (see REQ-070).


**REQ-019 — Invalid compression level**
If the compression level is outside the valid range for the selected algorithm,
`crab` shall reject it with an error message and non-zero exit code.

**REQ-020 — Compressed size retrieval**
After each compression operation, `crab` shall record the number of bytes written
to the output buffer as a `Natural` value.

**REQ-021 — MI approximation formula**
For a query *Q* and a chunk or file *C*, `crab` shall compute the mutual
information approximation via dictionary-preloaded compression:

> *MI‑approx(Q, C)* = (|compress(C, dict=∅)| − |compress(C, dict=Q)| + |compress(Q, dict=∅)| − |compress(Q, dict=C)|) / 2

where |compress(X, dict=D)| is the compressed size of *X* in bytes when compressed
with dictionary *D* pre-loaded into the compressor's internal buffers.
Both compressions use the same algorithm and compression level. When
`--ignore-case` is active, the strings *Q* and *C* are case-folded before
compression.

The query *Q* is pre-loaded as a dictionary once; the empty-dictionary baseline
uses a separate stream initialised with an empty dictionary.

**REQ-022 — Dictionary pre-loading**
The query (string or file contents) shall be loaded as a compression dictionary
once at initialisation time and reused for every scoring call. No re-compression
or re-loading of the query dictionary is performed on the scoring hot path.

**REQ-023 — Dictionary order**
The dictionary loaded into the compressor shall be the query *Q*.
There is no concatenation — the dictionary provides reference data that the
compressor uses to find matches in *C*. The compressor's internal window is
pre-populated with *Q* before *C* is compressed.

**REQ-024 — Scoring all input**
`crab` shall compute the MI‑approx score for every chunk extracted from the
input (chunk mode) or for every target file (file mode).

**REQ-025 — Score sign**
Scores may be negative (when the dictionary misleads the compressor — e.g.,
when Q and C are dissimilar). Negative scores shall be retained and ranked
correctly; they are not clamped to zero.

#### Output

**REQ-026 — Top-k selection**
`crab` shall select the *k* results with the greatest MI‑approx scores (or the
least, when `--invert` is set; see REQ-055), where *k* is specified by
`--top N` (or `-k N`).

**REQ-027 — k parameter**
`crab` shall accept a positive integer for *k*. If *k* exceeds the number of
available results, all results shall be returned (limited to the number available).

**REQ-028 — Output order**
Results shall be output in descending order of MI‑approx score (highest similarity
first) unless `--invert` is set, in which case results shall be output in ascending
order (lowest similarity first).

**REQ-029 — Output format (chunk mode)**
In chunk mode, each selected chunk shall be output preceded by a header line
containing the chunk rank (1‑based), the MI‑approx score, the source file path,
and the offset of the chunk within its source file. The header format shall be:

> `## chunk=N score=S file=P offset=O`

Where *N* is the 1‑based rank, *S* is the MI‑approx score (signed integer), *P*
is the path of the file containing the chunk start (relative to the working
directory, or `"(stdin)"` for stdin input), and *O* is the 0‑based byte offset
within that file. When `--chunk-lines` is specified, *O* is the 0‑based line
offset (line number) within that file (see REQ-062). When input is from stdin,
*O* is the 0‑based offset from the beginning of the stream (byte offset in
byte mode, line offset in line mode).

**REQ-030 — Chunk content output**
In chunk mode, the chunk's raw bytes shall be written to stdout immediately
following its header line. No transformation, escaping, or encoding conversion
shall be applied. Even when `--ignore-case` is set, the original (non-folded)
bytes shall be output.

**REQ-031 — Separator**
In chunk mode, consecutive chunk outputs shall be separated by a blank line.

**REQ-032 — Ties**
When multiple results have the same MI‑approx score, ties shall be broken by:
- The result appearing earlier in the file-processing order (files are processed
  deterministically per REQ-043 or command-line order) ranks higher.
- Within the same file (chunk mode), the chunk with the lower offset ranks higher.
In inversion mode, the same tie-breaking applies: the earlier result ranks higher
(lower rank number) among tied scores.

#### Inversion

**REQ-055 — Invert flag**
`crab` shall accept an `--invert` (or `-v`) flag. When set:

- The *k* results with the **least** MI‑approx scores shall be selected instead
  of the greatest.
- Output order shall be ascending (lowest similarity first; REQ-028).
- All other scoring behavior is unchanged. Applies to both chunk mode and file mode.

### 3.2 External Interface Requirements

**REQ-033 — Exit codes**
`crab` shall exit with code 0 on success. Non-zero exit codes shall indicate:

- 1: argument parsing error (invalid flag, missing value, value out of range)
- 2: file I/O error (missing or unreadable input file, or no readable files
  found during traversal)
- 3: compression error (library returned an error code)
- 4: empty input (no chunks could be formed, or no target files processed)

**REQ-034 — stderr for diagnostics**
All error messages, warnings, and diagnostic output shall be written to stderr.
Only result output shall be written to stdout.

**REQ-068 — Stack trace on fatal error**
Whenever `crab` encounters a fatal error (any condition that results in a
non-zero exit code), it shall print a stack trace to stderr identifying the
source location (file name and line number) of the exception or error raise
point. The stack trace shall be printed after the error message and before
program termination.


### 3.3 Internal Interface Requirements

No internal interfaces between separately maintained components. All internal
interfaces are design decisions (see Design Description).

### 3.4 Internal Data Requirements

No persistent data. All data is ephemeral for the duration of a single invocation.

### 3.5 Adaptation Requirements

**REQ-035 — System library discovery**
`crab` shall link against `libz`, `liblz4`, and `liblzma` at build time. At runtime, the
OS dynamic linker resolves these libraries. The Alire crate shall declare
`libz`, `liblz4`, and `liblzma` as external system dependencies.

### 3.6 Safety Requirements

No safety requirements identified for this project.

### 3.7 Security and Privacy Requirements

No security or privacy requirements identified for this project. The tool
processes only user-supplied text and does not access network resources,
elevate privileges, or persist data.

### 3.8 Environment Requirements

**REQ-036 — Platform**
`crab` shall build and run on Linux x86_64 with the GNAT 13 Ada compiler and
the system libraries `libz` (≥1.2), `liblz4` (≥1.9), and `liblzma` (≥5.2).

**REQ-037 — Build system**
`crab` shall build via the Alire build system (`alr build`) using the GPR
project file `crab.gpr`.

### 3.9 Resource Requirements

No hard resource limits are imposed. The following are noted as expectations:

| Resource | Expectation |
|---|---|
| Memory | O(input size + top‑k result storage). All input is read into memory. |
| Processing time | O(num_results × compress_time). Compression is the dominant factor. |

### 3.10 Software Quality Factors

| Factor | Target |
|---|---|
| Correctness | All requirements verified by test cases and AUnit unit tests |
| Reliability | Graceful error handling for all failure modes (bad args, missing files, compression errors, empty input, traversal errors) |
| Portability | Bindings use standard C ABI types via `Interfaces.C` |
| Maintainability | Modular Ada package design; one concern per package |
| Usability | Clear --help and -h output; conventional CLI argument patterns; man page installed |

### 3.11 Design and Implementation Constraints

**REQ-038 — Language**
The application shall be written in Ada 2012. C header declarations are permitted
for binding to system libraries.

**REQ-039 — License**
The crate shall be licensed under MIT OR Apache-2.0 WITH LLVM-exception (per the
existing `alire.toml`).

**REQ-040 — GNAT style**
All Ada source shall conform to the GNAT style switches defined in
`config/crab_config.gpr` (indentation 3, strict casing, no tabs, etc.).

**REQ-056 — Glob implementation constraint**
Glob pattern matching for `--include` and `--exclude` (REQ-049, REQ-050,
REQ-051) shall be implemented via a thin Ada binding to the POSIX `fnmatch()`
function from the system C library (`FNM_PATHNAME` flag not set, since
matching is against basenames only). No hand-rolled glob engine shall be used.

### 3.12 Personnel and Training Requirements

No personnel or training requirements. The tool is a CLI utility for technically
proficient users.

### 3.13 Other Requirements

**REQ-057 — Man page**
`crab` shall include a man page installed to the standard system manual
location (section 1, `crab.1`). The man page shall document:
- All command-line flags and arguments with descriptions.
- The mutual-information scoring method and its approximation formula.
- Supported compression algorithms and level ranges.
- Chunking semantics (chunk size, overlap, sliding window) and file mode.
- Output format specification for both modes.
- Exit codes and their meanings.
- Examples of typical usage.

**REQ-058 — Unit testing with AUnit**
All Ada packages with algorithmic logic shall have corresponding AUnit test
packages that exercise their public interfaces.  C-binding packages (`Crab_Zlib`,
`Crab_LZ4`, `Crab_Fnmatch`) shall be exercised via integration tests using the
same AUnit harness.  The tests shall reside in a nested Alire crate
(`tests/`) with its own `alire.toml` depending on `crab` (via path dependency)
and `aunit`.  `alr build` from the `tests/` directory shall compile and link
the test harness executable.  `alr run` from the `tests/` directory shall
execute all tests and report pass/fail counts.

---

## 4. Qualification Provisions

### 4.1 Verification Methods

| Method | Symbol | Description |
|---|---|---|
| Test | T | Executed test case with specified input and expected output |
| Demonstration | D | Manual execution observed by evaluator |
| Inspection | I | Code or document review |
| Analysis | A | Logical argument or calculation |

### 4.2 Requirements-to-Verification Traceability

| Requirement | Method | Test Case(s) |
|---|---|---|
| REQ-001 — Argument parsing (all flags) | T | TC-ARG-01 through TC-ARG-18 |
| REQ-002 — --help / -h | T | TC-ARG-01, TC-ARG-19 |
| REQ-003 — --version | T | TC-ARG-02 |
| REQ-004 — Query validation | T | TC-ARG-03, TC-ARG-04 |
| REQ-063 — File mode flag | T | TC-FILE-01 through TC-FILE-04 |
| REQ-064 — File mode query | T | TC-FILE-01 |
| REQ-065 — File mode scoring | T | TC-FILE-02 |
| REQ-066 — File mode output format | T | TC-FILE-03 |
| REQ-067 — Window-size warning | T | TC-WARN-01 through TC-WARN-03 |
| REQ-047 — Case insensitivity flag | T | TC-CASE-01 through TC-CASE-04 |
| REQ-005 — File input | T | TC-IO-01 |
| REQ-006 — Stdin input | T | TC-IO-02 |
| REQ-007 — Input encoding (bytes) | T | TC-IO-03 |
| REQ-008 — Missing/unreadable files | T | TC-IO-04 |
| REQ-041 — Recursive search flag | T | TC-DIR-01, TC-DIR-02 |
| REQ-042 — Directory traversal scope | T | TC-DIR-03 |
| REQ-043 — Traversal order | T | TC-DIR-04 |
| REQ-044 — Symlink handling | T | TC-DIR-05 |
| REQ-045 — Traversal error handling | T | TC-DIR-06 |
| REQ-046 — Empty directory | T | TC-DIR-07 |
| REQ-049 — Include glob | T | TC-FILT-01, TC-FILT-02 |
| REQ-050 — Exclude glob | T | TC-FILT-03, TC-FILT-04 |
| REQ-051 — Glob pattern syntax | T | TC-FILT-05 |
| REQ-052 — Include/exclude with non-recursive | T | TC-FILT-06 |
| REQ-053 — Maximum depth | T | TC-DEPTH-01, TC-DEPTH-02 |
| REQ-054 — No depth limit default | T | TC-DEPTH-03 |
| REQ-009 — Fixed-size chunks | T | TC-CHUNK-01 |
| REQ-010 — Chunk size parameter | T | TC-CHUNK-01, TC-ARG-05 |
| REQ-011 — Chunk overlap | T | TC-CHUNK-02 |
| REQ-012 — Overlap range | T | TC-ARG-06 |
| REQ-013 — Input shorter than chunk size | T | TC-CHUNK-03 |
| REQ-014 — Empty input | T | TC-CHUNK-04 |
| REQ-059 — Line-based chunk size parameter | T | TC-CHUNK-05 |
| REQ-060 — Line-based chunking semantics | T | TC-CHUNK-06 |
| REQ-061 — Chunk mode mutual exclusivity | T | TC-CHUNK-07 |
| REQ-062 — Line-mode offset semantics | T | TC-OUT-07 |
| REQ-015 — Algorithm selection | T | TC-ARG-07, TC-ARG-20 |
| REQ-016 — DEFLATE compression | T | TC-COMP-01 |
| REQ-017 — LZ4 compression | T | TC-COMP-02 |
| REQ-069 — LZMA compression | T | TC-COMP-05 |
| REQ-070 — LZMA dictionary size | T | TC-ARG-22, TC-COMP-07 |
| REQ-018 — Compression level | T | TC-ARG-08, TC-COMP-03, TC-COMP-06 |
| REQ-019 — Invalid compression level | T | TC-ARG-09, TC-ARG-21 |
| REQ-020 — Compressed size retrieval | T | TC-COMP-04 |
| REQ-021 — MI approximation formula | T | TC-MI-01 |
| REQ-022 — Query compression caching | A | Inspect `scorer` package — query compressed once |
| REQ-023 — Dictionary order | T | TC-MI-02 |
| REQ-024 — Scoring all input | T | TC-MI-03 |
| REQ-025 — Score sign | T | TC-MI-04 |
| REQ-026 — Top-k selection | T | TC-OUT-01 |
| REQ-027 — k parameter | T | TC-OUT-02, TC-ARG-10 |
| REQ-028 — Output order | T | TC-OUT-01 |
| REQ-029 — Output format (chunk mode) | T | TC-OUT-03 |
| REQ-030 — Chunk content output | T | TC-OUT-04 |
| REQ-031 — Separator (blank line) | T | TC-OUT-05 |
| REQ-032 — Ties | T | TC-OUT-06 |
| REQ-055 — Invert flag | T | TC-INV-01 through TC-INV-04 |
| REQ-033 — Exit codes | T | TC-ERR-01 through TC-ERR-05 |
| REQ-034 — stderr for diagnostics | T | TC-ERR-01 |
| REQ-068 — Stack trace on fatal error | T | TC-ERR-06 |
| REQ-035 — System library discovery | D | Build and run on target platform; verify liblzma linkage |
| REQ-036 — Platform | D | Build and test on Linux x86_64 with liblzma ≥5.2 |
| REQ-037 — Build system | D | `alr build` succeeds |
| REQ-038 — Language | I | Source inspection |
| REQ-039 — License | I | `alire.toml` inspection |
| REQ-040 — GNAT style | I | Code review; no `-gnaty*` warnings during build |
| REQ-057 — Man page | I | Document inspection; verify man page content and installation |
| REQ-058 — Unit testing | T+D | `alr build` in `tests/`; all AUnit tests pass |
| REQ-056 — Glob implementation constraint | I | Source inspection; verify `fnmatch` binding used |

---

## 5. Requirements Traceability

### 5.1 Requirements-to-Source Map

| Requirement | Source |
|---|---|
| REQ-001 | Project Brief: "grep-like cli application" |
| REQ-002 | Standard CLI convention; Project Plan §4.13 |
| REQ-003 | Standard CLI convention; Project Plan §4.13 |
| REQ-004 | Project Brief: "input string"; amended: file path in file mode |
| REQ-063 | Client: file mode — compare query file against target files |
| REQ-064 | Derived from REQ-063: query file semantics |
| REQ-065 | Derived from REQ-063: whole-file scoring |
| REQ-066 | Client: file mode output — "filename score" one line per file |
| REQ-067 | Client: warn when file/chunk exceeds LZ77/LZMA sliding window |
| REQ-047 | Client: agreed recommendation — ignore-case flag |
| REQ-005 | Project Brief: "selecting chunks of text from files" |
| REQ-005 (streaming) | Client: "more streaming manner ... each file in isolation" |
| REQ-006 | Project Brief: "and streams" |
| REQ-007 | Design decision: byte-oriented processing avoids encoding assumptions |
| REQ-008 | Standard CLI robustness |
| REQ-041 | Client: "directory and recursive searching like grep" |
| REQ-042 | Derived from REQ-041: completeness of directory traversal |
| REQ-043 | Determinism requirement — reproducible results |
| REQ-044 | Grep compatibility: grep follows symlinks |
| REQ-045 | Robustness: don't abort on inaccessible files within a tree |
| REQ-046 | Edge-case: empty directory tree |
| REQ-049 | Client: agreed recommendation — include glob for file filtering |
| REQ-050 | Client: agreed recommendation — exclude glob for file filtering |
| REQ-051 | Derived from REQ-049/050: glob syntax definition |
| REQ-052 | Robustness: include/exclude semantics for non-recursive mode |
| REQ-016 | Project Brief: "DEFLATE"; amended: streaming dictionary API from libz |
| REQ-017 | Project Brief: "LZ4"; amended: streaming dictionary API from liblz4 |
| REQ-069 | Client: LZMA compression via liblzma streaming API |
| REQ-070 | Client: LZMA dictionary size via --dict-size / -D flag |
| REQ-054 | Derived from REQ-053: default behavior explicit |
| REQ-009 | Project Brief: "chunks" — defined as fixed-size sliding window |
| REQ-010 | Derived: chunk size must be configurable to make overlap meaningful |
| REQ-011 | Project Brief: "degree of overlap of the chunks as a percentage" |
| REQ-012 | Risk R4 mitigation |
| REQ-013 | Edge-case correctness |
| REQ-021 | Project Brief: amended — symmetric dictionary-preloaded compression: (|compress(C, dict=∅)| − |compress(C, dict=Q)| + |compress(Q, dict=∅)| − |compress(Q, dict=C)|) / 2 |
| REQ-022 | Performance optimization: dictionary pre-loaded once per invocation |
| REQ-023 | Determinism: dictionary order is Q; no concatenation |
| REQ-059 | Client: line-based chunking mode |
| REQ-060 | Client: line-based chunking mode |
| REQ-061 | Derived: mutual exclusivity with byte-based chunking |
| REQ-062 | Client: line-mode offsets shall be line-based rather than byte-based |
| REQ-015 | Project Brief: "DEFLATE and LZ4 algorithms"; amended: add LZMA |
| REQ-016 | Project Brief: "DEFLATE"; client: "write thin Ada bindings for zlib" |
| REQ-017 | Project Brief: "LZ4"; client: "write thin Ada bindings for liblz4" |
| REQ-069 | Client: "write thin Ada bindings for liblzma" |
| REQ-070 | Client: "add --dict-size / -D flag for LZMA dictionary size" |
| REQ-018 | Client: "user should be able to tune the compression level" |
| REQ-019 | Robustness |
| REQ-020 | Enables REQ-021 |
| REQ-021 | Project Brief: symmetric MI — (|compress(C,∅)| − |compress(C,Q)| + |compress(Q,∅)| − |compress(Q,C)|) / 2 |
| REQ-022 | Performance optimization |
| REQ-023 | Determinism |
| REQ-024 | Project Brief: "k chunks with greatest mutual information" |
| REQ-025 | Correctness: MI approximation can yield negative values |
| REQ-026 | Project Brief: "k chunks with the greatest mutual information with the input will be output" |
| REQ-027 | Project Brief: "specify the number of chunks to be returned" |
| REQ-028 | Project Brief: "greatest mutual information" implies descending order |
| REQ-029 | Design decision: output format for machine-parseability; file path added per client directory-search requirement |
| REQ-030 | Project Brief: "output" of the chunks; amended: original bytes even with -i |
| REQ-031 | Readability |
| REQ-032 | Determinism |
| REQ-032 (streaming) | Client: per-file processing; tie-break by file order + per-file offset |
| REQ-055 | Client: agreed recommendation — inversion flag for least-similar search |
| REQ-033 | Standard CLI convention |
| REQ-034 | Standard CLI convention |
| REQ-068 | Client: stack trace to stderr on fatal errors |
| REQ-035 | Project Plan: Alire crate with system dependencies; amended: add liblzma |
| REQ-036 | Project Plan §6: Linux x86_64; amended: add liblzma ≥5.2 |
| REQ-037 | Project Plan §4.4: Alire build system |
| REQ-038 | Client: "We will be using the Ada programming language" |
| REQ-039 | Existing `alire.toml` |
| REQ-057 | Client: "I want to add a man page for the application as a requirement" |
| REQ-058 | Client: "include unit testing using the AUnit testing framework ... nested alire crate" |
| REQ-056 | Client: "use bindings to the POSIX C libraries for implementing globbing" |
| REQ-040 | Existing `crab_config.gpr` |

---

## 6. Notes

### 6.1 Key Design Decisions Deferred to Design Phase

- **Chunk size semantics:** The "chunk" is defined here as a fixed-size byte
  window. The specific data structure for chunk extraction (sliding window
  iterator) is a design decision.
- **Compression abstraction:** The internal interface between the scoring engine
  and the compression backends (how to dispatch on algorithm) is a design
  decision.
- **Memory management:** Holding both the original and case-folded input when
  `-i` is set (to output original bytes) is a design decision — options include
  keeping both copies or tracking offsets into a single buffer.
- **Argument parsing library:** Choice of Ada CLI library (e.g., GNAT.Command_Line
  vs. a third-party crate) is a design decision.
- **Directory traversal implementation:** Choice of Ada directory-walking approach
  (GNAT.OS_Lib, POSIX bindings, or a third-party crate) is a design decision.
- **Glob matching implementation:** Choice of glob-matching approach (hand-rolled,
  POSIX `fnmatch` binding, or an Ada library) is a design decision.
  *Note: Per client direction, glob matching shall use a thin Ada binding to POSIX
  `fnmatch()` from libc.*
- **File mode architecture:** The file-mode processing path is a separate branch
  in `crab.adb` that reuses the same Scorer and TopK packages. The query file is
  read once; target files are scored as single units. The TopK heap is reused
  with a different print routine (`Print_File_Scores`).

### 6.2 Open Questions Resolved with Client

| Question | Resolution |
|---|---|
| Chunk size | Exposed as `--chunk-size` parameter |
| Line-based chunking | `--chunk-lines N` / `-L N`; mutually exclusive with `--chunk-size`; chunks of N lines; overlap applied to line count |
| Minimum input handling | Empty input → error exit |
| Input shorter than chunk | Single chunk of available bytes |
| Overlap semantics | Percentage of chunk size; step = chunk_size × (1 − overlap/100) |
| Output format (chunk mode) | Header line + raw chunk bytes + blank line separator; file path in header |
| Output format (file mode) | One line per file: `filename score`; descending by score |
| Ties | Broken by input offset (earlier first) |
| Compression level for LZ4 | Maps to acceleration parameter |
| Compression level for LZMA | 0–9; default 6; dictionary size set independently via --dict-size |
| Directory search | `-r`/`--recursive` flag; grep-like behavior (directories error without `-r`) |
| Recursive without args | Searches current directory |
| Symlinks | Followed |
| Traversal errors | Warn and continue |
| File path in output | Added `file=P` field to header |
| Offset semantics | Byte mode: per-file byte offset in header; line mode: per-file line offset (REQ-062). Tie-breaking uses the corresponding offset unit. |
| Case insensitivity | `-i`/`--ignore-case`; ASCII-only case folding; original bytes preserved in output |
| File filtering | `--include`/`--exclude` globs against basename; repeatable; excludes override includes |
| Traversal depth | `--max-depth N`; 0 = root only; unlimited by default |
| Inversion | `-v`/`--invert`; output k least-similar results in ascending order |
| File mode | `-f`/`--file-mode`; query is a file path; whole-file scoring; `filename score` output |
| Window-size warning | Warn on stderr when file/chunk exceeds DEFLATE (32 KB), LZ4 (64 KB), or LZMA (user-specified dictionary size) window |
| Man page | Installed as share/man/man1/crab.1 via Alire crate |
| -h flag | Short flag for --help; prints usage message |
| Streaming architecture | Files processed independently; top-k accumulator across files; bounded heap |
| Unit testing | AUnit framework; nested Alire test crate at `tests/` |
