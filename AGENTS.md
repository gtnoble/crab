# AGENTS.md Ã¢ÂÂ crab Coding Agent Guide

## Project Overview

**crab** is a grep-like CLI tool that selects the *k* most-similar text chunks
from files or stdin, compared against an input query string or query file.
Similarity is measured by **mutual information** approximated via
dictionary-preloaded compression (the Normalized Compression Distance family).

Two operating modes:
- **Chunk mode** (default) Ã¢ÂÂ query is a literal string; input is partitioned
  into fixed-size overlapping chunks; each chunk scored independently.
- **File mode** (`-f`/`--file-mode`) Ã¢ÂÂ query is a file path; each target file
  scored as a single unit; output is `filename score`.

Language: **Ada 2012/2022** (GNAT 13.3.0).  Build system: **Alire** (`alr`).
License: MIT OR Apache-2.0 WITH LLVM-exception.

---

## Repository Layout

```
crab/
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ alire.toml              # Alire crate manifest
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab.gpr                # GPR project file (links -lz, -llz4, -llzma)
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ .gitignore              # Ignores obj/, bin/, alire/, config/, *.ali, *.o
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ config/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_config.gpr     # Abstract project: compiler switches, build profile
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ src/                    # All application source (27 files)
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab.adb            # CLI main: arg parsing, streaming orchestrator
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_buffers.ads    # Controlled heap-allocated Byte_Buffer (auto-cleanup)
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_buffers.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_zlib.ads       # Thin binding to libz streaming API
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_zlib.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lz4.ads        # Thin binding to liblz4 streaming dictionary API
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lz4.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lzw.ads        # Pure Ada LZW compression (no C types)
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lzw.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lzma.ads       # Thin binding to liblzma streaming API
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lzma.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_fnmatch.ads    # Thin binding to POSIX fnmatch()
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_fnmatch.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_compression.ads # Abstraction: backend dispatch + window-size query
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_compression.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_fold.ads       # ASCII case folding for --ignore-case
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_fold.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_glob.ads       # Multi-pattern include/exclude matching
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_glob.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scanner.ads    # Directory traversal with glob filtering + depth limit
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scanner.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_chunker.ads    # Streaming sliding-window chunk iterator
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_chunker.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scorer.ads     # Stateful MI scorer (variant record, typed stream components)
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scorer.adb
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_topk.ads       # Bounded binary heap: top-k accumulation + output
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_topk.adb
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ tests/                  # Nested Alire crate (depends on crab + aunit)
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ alire.toml
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_tests.gpr
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ src/
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_tests.adb              # Main harness (registers all suites)
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_chunker_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_compression_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_fold_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_glob_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_lzw_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scorer_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_topk_tests.ads/adb
Ã¢ÂÂ       Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab_scanner_tests.ads/adb  # Integration tests
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ bin/                    # Build output: crab executable
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ obj/                    # Build objects (gitignored)
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ share/man/man1/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ crab.1              # Man page
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ share/agents/skills/crab/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ SKILL.md            # Agent skill for semantic search
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ plan/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ project-plan.md     # MIL-STD-498 project plan
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ requirements/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ requirements-spec.md # Software Requirements Specification (v1.2)
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ design/
Ã¢ÂÂ   Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ design-description.md # Software Design Description (v1.2)
Ã¢ÂÂ
Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ AGENTS.md               # This file
```

---

## Architecture

### Dependency graph (DAG rooted at crab.adb)

```
crab.adb
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Compression Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ¬Ã¢ÂÂÃ¢ÂÂ Crab_Zlib   (C binding: libz)
 Ã¢ÂÂ                           Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_LZ4    (C binding: liblz4)
 Ã¢ÂÂ                           Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_LZMA   (C binding: liblzma)
 Ã¢ÂÂ                           Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_LZW    (pure Ada)
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Fold              (pure computation)
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Scanner Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ¬Ã¢ÂÂÃ¢ÂÂ Crab_Glob Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Fnmatch (C binding: libc)
 Ã¢ÂÂ                           Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ GNAT.OS_Lib
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Chunker           (pure computation)
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Scorer Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂÃ¢ÂÂ¬Ã¢ÂÂÃ¢ÂÂ Crab_Compression
 Ã¢ÂÂ                           Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_Buffers
 Ã¢ÂÂÃ¢ÂÂÃ¢ÂÂ Crab_TopK              (pure computation)
```

No circular dependencies.  `Crab_Buffers` depends only on `Ada.Finalization`.

### Streaming architecture

Files are processed **one at a time** Ã¢ÂÂ no concatenation, no global buffer.
In chunk mode, chunks are scored on-the-fly; only the top-*k* chunks (plus the
current working chunk) are held in memory.  The bounded binary heap in
`Crab_TopK` replaces a batch sort-then-output model.

**Chunk mode flow:**
1. Parse args Ã¢ÂÂ `Config` record
2. Load query as compression dictionary into persistent stream objects
3. For each file: read Ã¢ÂÂ (fold if `-i`) Ã¢ÂÂ chunk Ã¢ÂÂ score Ã¢ÂÂ insert into TopK heap
4. Drain heap in sorted order, print headers + chunk bytes

**File mode flow:**
1. Parse args Ã¢ÂÂ `Config` record (with `File_Mode = True`)
2. Read query file, load as dictionary
3. For each target file: read Ã¢ÂÂ (fold if `-i`) Ã¢ÂÂ score whole file Ã¢ÂÂ insert into TopK heap
4. Drain heap, print `filename score` per line

### Key design decisions

| Decision | Rationale |
|---|---|
| **Per-file processing, no concatenation** | Avoids loading all files into memory |
| **Bounded binary heap for top-k** | O(log k) insertion vs O(N log N) full sort |
| **Chunker as streaming iterator** | No intermediate vector; chunk data is a substring slice Ã¢ÂÂ zero-copy |
| **Scorer stateful with dictionary-preloaded stream** | Query loaded as dictionary once; streams reused across all scoring calls |
| **Variant-record `State` discriminated by Algorithm** | Stream types stored directly as typed components; no `System.Address` type-erasure, no `Unchecked_Conversion` |
| **Controlled `Byte_Buffer`** | `Finalize` frees storage automatically Ã¢ÂÂ no manual `Unchecked_Deallocation` |
| **`System.Address` for C buffer passing** | Avoids intermediate copies when passing String data to C functions |

### Compression backends

| Algorithm | Backend | Window size | Dictionary limit | Level range | Default |
|---|---|---|---|---|---|
| `deflate` | libz (C binding) | 32 KB | 32 KB | Ã¢ÂÂ1..9 | 6 |
| `lz4` | liblz4 (C binding) | 64 KB | 64 KB | 1..65537 | 1 |
| `lzw` | Pure Ada | 10M codes (~290 MB; 0 = unbounded) | 10M codes (~290 MB; 0 = unbounded) | 0 (ignored) | 0 |
| `lzma` | liblzma (C binding) | user-specified (default 8 MB) | user-specified | 0..9 | 6 |

### MI approximation formula

```
MI-approx(Q, C) = (|compress(C, dict=Ã¢ÂÂ)| Ã¢ÂÂ |compress(C, dict=Q)|
                  + |compress(Q, dict=Ã¢ÂÂ)| Ã¢ÂÂ |compress(Q, dict=C)|) / 2
```

Scores are signed `Integer` Ã¢ÂÂ negative scores are retained and ranked correctly.

### LZW scoring (three-phase, single-stream)

LZW uses a single stream allocated at `Init` and reused across `Score` calls:
1. **Phase 1** Ã¢ÂÂ compress C against empty dict Ã¢ÂÂ produces `Bare_CS` while building C's string table
2. **Phase 2** Ã¢ÂÂ compress Q reusing C's string table Ã¢ÂÂ produces `|Q|C|`
3. `Reset_Stream` clears the table
4. **Phase 3** Ã¢ÂÂ re-prime with Q, compress C Ã¢ÂÂ produces `|C|Q|`

### LZMA scoring (per-pass streams)

LZMA has unbounded dictionaries; streams are created and freed per-pass within
each `Score` call to avoid simultaneous memory usage from multiple large
dictionaries.

---

## Build & Test

### Build

```sh
# Build the application
alr build

# The binary lands at bin/crab
```

System dependencies (must be installed):
- `libz` (zlib1g-dev)
- `liblz4` (liblz4-dev)
- `liblzma` (liblzma-dev)

The GPR project file (`crab.gpr`) links `-lz`, `-llz4`, `-llzma`.  Compiler
switches are defined in `config/crab_config.gpr` (optimisation `-O3`, inlining
`-gnatn`, function/data sections, UTF-8 wide chars `-gnatW8`).  A profiling
scenario (`-XCRAB_PROFILING=true`) adds `-pg` for gprof.

### Test

```sh
# Build and run tests
cd tests/
alr build
alr run
```

Tests live in a **nested Alire crate** at `tests/` with its own `alire.toml`
depending on `crab` (via `path = ".."`) and `aunit` (^26.0.0).  The test
harness (`tests/src/crab_tests.adb`) registers AUnit test suites for all
algorithmic packages and runs them.

**Test coverage:**

| Package under test | Test package | Type |
|---|---|---|
| `Crab_Chunker` | `Crab_Chunker_Tests` | Unit |
| `Crab_Compression` | `Crab_Compression_Tests` | Unit (includes `Window_Size`) |
| `Crab_Fold` | `Crab_Fold_Tests` | Unit |
| `Crab_Glob` | `Crab_Glob_Tests` | Unit |
| `Crab_LZW` | `Crab_LZW_Tests` | Unit |
| `Crab_Scorer` | `Crab_Scorer_Tests` | Unit |
| `Crab_TopK` | `Crab_TopK_Tests` | Unit (includes file-mode heap) |
| `Crab_Scanner` | `Crab_Scanner_Tests` | Integration |
| `Crab_Zlib` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_LZ4` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_LZMA` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_Fnmatch` | (exercised via `Crab_Glob_Tests`) | Integration |

---

## Coding Conventions

- **Ada 2012** Ã¢ÂÂ the application language.  C headers are permitted only for
  binding declarations (no C compilation required Ã¢ÂÂ `Import` + linker flags).
- **One Ada package per file**, named after the package.
- **All subprograms explicitly scoped** Ã¢ÂÂ no use clauses that would create
  ambiguity.
- **No `Unchecked_Conversion` or `System.Address` arithmetic** unless required
  by C bindings and confined to binding package bodies.
- **GNAT style switches** (`-gnaty*` per `crab_config.gpr`) enforce layout,
  casing, and formatting.  All code must compile cleanly with these switches.
- **Error handling** Ã¢ÂÂ use exceptions (`Compression_Error`, `Zlib_Error`,
  `LZ4_Error`, `LZMA_Error`, `LZW_Error`) for backend failures.  `crab.adb`
  catches all exceptions at the top level and maps them to exit codes 1Ã¢ÂÂ4.
- **Memory** Ã¢ÂÂ `Crab_Buffers.Byte_Buffer` is a `Limited_Controlled` type;
  `Finalize` frees storage automatically.  Do not introduce manual
  `Unchecked_Deallocation`.
- **No shared global state** between packages.  The `Config` record is the
  single point of configuration flow Ã¢ÂÂ constructed in `crab.adb` and passed
  as parameters to subprograms in other packages.

### Ada standard library dependencies

| Standard package | Used by |
|---|---|
| `Ada.Command_Line` | `crab.adb` Ã¢ÂÂ argument parsing |
| `Ada.Text_IO` | `crab.adb` Ã¢ÂÂ stderr; `Crab_TopK` Ã¢ÂÂ stdout |
| `Ada.Strings.Unbounded` | Multiple Ã¢ÂÂ dynamic string storage |
| `Ada.Containers.Indefinite_Vectors` | `Crab_Scanner`, `crab.adb` |
| `Ada.Containers.Indefinite_Hashed_Sets` | `Crab_Scanner` Ã¢ÂÂ cycle detection |
| `Ada.Containers.Generic_Array_Sort` | `Crab_Scanner`, `Crab_TopK` |
| `Ada.Directories` | `Crab_Scanner` Ã¢ÂÂ directory traversal |
| `Ada.Streams.Stream_IO` | `crab.adb` Ã¢ÂÂ file I/O; `Crab_TopK` Ã¢ÂÂ stdout |
| `Ada.Streams` | `Crab_Buffers` Ã¢ÂÂ `Stream_Element` type |
| `Ada.Finalization` | `Crab_Buffers` Ã¢ÂÂ `Limited_Controlled` base |
| `System.Address` | Binding packages Ã¢ÂÂ C buffer passing (FFI overlays) |
| `GNAT.OS_Lib` | `Crab_Scanner` Ã¢ÂÂ `Normalize_Pathname` for cycle detection |
| `System.Address` | Binding packages Ã¢ÂÂ C buffer passing (FFI overlays) |
| `Ada.Exceptions` | `crab.adb`, `Crab_Scanner` Ã¢ÂÂ exception messages |

---

## Key Types Crossing Package Boundaries

| Type | Defined in | Used by |
|---|---|---|
| `Crab_Compression.Algorithm` | `Crab_Compression` | `crab.adb`, `Crab_Scorer` |
| `Crab_Glob.Pattern_List` | `Crab_Glob` | `crab.adb`, `Crab_Scanner` |
| `Crab_Chunker.State` | `Crab_Chunker` | `crab.adb` |
| `Crab_Chunker.Line_State` | `Crab_Chunker` | `crab.adb` |
| `Crab_Scorer.State` | `Crab_Scorer` | `crab.adb` |
| `Crab_TopK.Heap` | `Crab_TopK` | `crab.adb` |
| `Crab_Buffers.Byte_Buffer` | `Crab_Buffers` | All compression modules, `Crab_Scorer` |

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Argument parsing error (invalid flag, missing value, value out of range) |
| 2 | File I/O error (missing/unreadable file, or no readable files found) |
| 3 | Compression error (library returned an error code) |
| 4 | Empty input (no chunks formed, or no target files processed) |

All diagnostics go to **stderr**.  Only result output goes to **stdout**.
On fatal error, a stack trace is printed to stderr identifying the source
location of the exception.

---

## Common Tasks

### Adding a new compression backend

1. Create `crab_newalgo.ads` and `crab_newalgo.adb` in `src/`.
2. Implement the binding following the pattern of `Crab_Zlib` / `Crab_LZ4` /
   `Crab_LZMA` (if C library) or `Crab_LZW` (if pure Ada).
3. Required interface: `Compress_Bound`, `Init_Stream`, `Load_Dict`,
   `Compress_Stream`, `Free_Stream`, `Compress_Bare`.  Use
   `Crab_Buffers.Byte_Buffer` for all byte buffers.
4. Add the new algorithm to `Crab_Compression.Algorithm` enumeration.
5. Add dispatch cases in `Crab_Compression` body for `Compress_Bound`,
   `Compress_Bare`, `Level_Default`, `Level_Min`, `Level_Max`, `Window_Size`.
6. Add stream handle cases in `Crab_Scorer` body (Init, Score, Finalize).
7. Add the algorithm name to `Parse_Args` in `crab.adb`.
8. Add tests in `tests/src/crab_compression_tests.adb`.
9. Update `design/design-description.md` ÃÂ§4.1, ÃÂ§5, ÃÂ§6.
10. Update `requirements/requirements-spec.md` if new flags are added.
11. Update `share/man/man1/crab.1`.
12. Update this file.

### Adding a new CLI flag

1. Add the field to the `Config` record in `crab.adb`.
2. Add parsing logic in `Parse_Args`.
3. Add validation (mutual exclusivity, range checks).
4. Wire the flag through to the appropriate package.
5. Add test cases.
6. Update the man page and requirements spec.

### Adding a new test

1. Create `tests/src/crab_foo_tests.ads` and `tests/src/crab_foo_tests.adb`
   following the existing pattern (AUnit test case + suite registration).
2. Register the suite in `tests/src/crab_tests.adb`.
3. Build and run: `cd tests && alr build && alr run`.

---

## Documentation

The project uses a MIL-STD-498-based governance structure adapted for a
single-developer project.  Key documents:

| Document | Path | Purpose |
|---|---|---|
| Project Plan | `plan/project-plan.md` | Governing plan: schedule, resources, risks, process |
| Requirements Spec | `requirements/requirements-spec.md` | All functional + non-functional requirements (REQ-001Ã¢ÂÂREQ-071) |
| Design Description | `design/design-description.md` | Architectural decomposition, unit design, traceability |
| Man page | `share/man/man1/crab.1` | User-facing documentation |
| Agent skill | `share/agents/skills/crab/SKILL.md` | Agent skill for semantic search with crab |

Requirements-to-unit traceability is maintained in
`design/design-description.md` ÃÂ§6.

---

## What NOT to Do

- **Do not introduce GNATCOLL or AWS** Ã¢ÂÂ the project uses only the GNAT
  standard library plus thin C bindings.  No external Ada crates beyond
  `aunit` (test-only).
- **Do not add `Unchecked_Deallocation`** Ã¢ÂÂ use `Crab_Buffers.Byte_Buffer`
  (controlled type) for all heap-allocated byte storage.
- **Do not share mutable state between packages** Ã¢ÂÂ the `Config` record is the
  only cross-package data flow mechanism.
- **Do not add circular dependencies** Ã¢ÂÂ the dependency graph must remain a
  DAG rooted at `crab.adb`.
- **Do not use `Unchecked_Conversion` outside C binding packages** Ã¢ÂÂ
  `System.Address` is only acceptable for FFI buffer passing.
- **Do not add C compilation to the build** Ã¢ÂÂ all C library interaction is
  via `Import` pragmas and linker flags.  No `.c` files in `src/`.
- **Do not change the MI formula** without updating the requirements spec,
  design description, man page, and tests.
