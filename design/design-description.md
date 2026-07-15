# Software Design Description — Crab

**Project:** Crab — Compression-based mutual-information grep
**Date:** 2026-07-15
**Version:** 1.7 — Normalised levels, auto-select algorithm, unified --dict-size
**Component:** `crab`, `crelz`

---

## 1. Scope

### 1.1 Component Identifier

`crab` and `crelz` — two CLI executables sharing 14 Ada packages.  `crab` selects and outputs the *k* chunks of text (or whole files, in file mode) having
the greatest (or least) compression-based mutual information with a user query.
Processing is streaming: files are read independently, chunks (or whole files) are
scored on-the-fly, and only the top-*k* (plus the current working chunk) are held in
memory. Two operating modes are supported: **chunk mode** (query string vs chunked
input) and **file mode** (query file vs whole target files).  `crelz` is a
`gzip`-like standalone ELZ file compressor/decompressor producing `.ez` files
with a `CREL`-magic header; it shares the `Crab_ELZ` package with `crab` and
has no other package dependencies.

### 1.2 Document Overview

Section 3 records component-wide design decisions. Section 4 describes the
architectural decomposition. Section 5 provides detailed design for each software
unit. Section 6 traces requirements to implementing units.

---

## 2. Referenced Documents

| Document | Reference |
|---|---|
| Project Plan | `plan/project-plan.md` v1.0-draft |
| Requirements Spec | `requirements/requirements-spec.md` v1.1 |
| MIL-STD-498 DID DI-IPSC-81435 (SDD) | Checklist at `documents.md` Part 1 |

---

## 3. Component-Wide Design Decisions

### 3.1 Behavioral Design

`crab` executes as a streaming processor with two operating modes:

**Chunk mode (default):**

1. **Argument parsing.** Command-line arguments are parsed into a `Config` record.
2. **Query preparation.** If `-i`, the query is case-folded. The query is loaded
   as a compression dictionary into the Scorer's persistent stream object once at
   initialisation time.
3. **File processing.** For each input file (or stdin):
   a. Read the file's bytes into a buffer.
   b. If `--preprocess` is set, call `Crab_Preprocess.Preprocess_Data`
      to spawn `/bin/sh -c CMD`, pipe the raw bytes to the command's
      stdin, capture stdout as the pre-processed data, and replace the
      buffer contents with the pre-processed output.
   c. If `-i`, produce a folded copy of the buffer for scoring; keep the
      pre-processed (or original, if no preprocessor) bytes for output.
   d. Warn if the file exceeds the algorithm's sliding-window or dictionary size.
   e. For each chunk, pass its folded data to the Scorer to compute the MI‑approx
      score via dictionary-preloaded compression. Extract the corresponding
      original bytes from the pre-processed buffer for potential output.
   f. Insert the `(score, file, per‑file offset, original chunk bytes)` tuple into
      the Top‑K accumulator.
4. **Output.** After all files are processed, extract the top‑*k* entries from the
   heap in sorted order (best first) and print headers followed by chunk bytes.

**File mode (`-f` / `--file-mode`):**

1. **Argument parsing.** Same as chunk mode; `File_Mode` flag set.
2. **Query preparation.** The first positional argument is a **query file path**.
   The file's contents are read and loaded as a compression dictionary. If `-i`,
   the query file contents are case-folded. Warn if the query file exceeds the
   algorithm's sliding-window or dictionary size.
3. **Target file processing.** For each target file (or stdin):
   a. Read the file's bytes into a buffer.
   b. Skip the file if it is the query file (matched by path).
   c. If `--preprocess` is set, call `Crab_Preprocess.Preprocess_Data`
      to spawn `/bin/sh -c CMD`, pipe the raw bytes to the command's
      stdin, capture stdout as the pre-processed data, and replace the
      buffer contents with the pre-processed output.
   d. Warn if the file exceeds the algorithm's sliding-window or dictionary size.
   e. Score the entire file as a single unit via dictionary-preloaded compression.
   f. Insert the `(score, file, offset=0, data="")` tuple into the Top‑K accumulator.
4. **Output.** After all files are processed, extract the top‑*k* entries from the
   heap in sorted order and print one line per entry: `filename score`.

The tool is single-threaded. There is no interactive mode, no daemon mode, no
network communication.

### 3.2 Memory and Processing Allocation

| Concern | Strategy |
|---|---|
| **Input buffer** | One file at a time. Max memory = largest single file. No concatenated global buffer. |
| **Folded buffer** | When `-i`, a second buffer of equal size to the current file. Released after the file is processed. |
| **Pre-process buffer** | When `--preprocess` is set, `Crab_Preprocess.Preprocess_Data` spawns `/bin/sh -c CMD` via `GNAT.Expect.Get_Command_Output` which returns the pre-processed output as a new `String`; the raw file buffer is released after the command completes. Peak memory = raw file + pre-processed output (temporary). |
| **Chunk storage** | Chunk mode: only *k* + 1 chunks in memory. File mode: only *k* score entries (no chunk data stored). |
| **Compression buffers** | One persistent output buffer (`Chunk_Buf`) allocated at `Scorer.Init` time and managed as a controlled `Crab_Buffers.Byte_Buffer` — `Finalize` frees it automatically, no manual `Unchecked_Deallocation`.  For ELZ, `Chunk_Buf` is sized for `max(compressBound(chunk), compressBound(query))` so all three phases' outputs fit.  Additionally, persistent streaming compressor objects are allocated once, pre-loaded with the query as dictionary, and reused for every scoring call.  For DEFLATE and LZ4, two streams (dict + bare) are pre-loaded and reused.  For ELZ, a single stream is allocated and reused across Score calls via `Reset_Stream`; phases 1–2 build and reuse the string table, phase 3 resets and re-primes with the query.  The ELZ string table is bounded via the normalised compression level (exponential max-codes scaling) or explicitly via `--dict-size`.  When bounded, the hash table and raw heap node array are limited to O(N) memory, and deterministic random leaf eviction using an LCG reuses code slots when the table is full.  For LZMA (which has unbounded dictionaries), streams are created and freed per-pass within each Score call to avoid simultaneous memory usage from multiple large dictionaries.  `Compress_Bare` convenience functions in each backend use a stack-declared `Byte_Buffer` that auto-frees on scope exit — no leak. |
| **Query compression** | The query is loaded as a dictionary into the persistent stream object once for DEFLATE and LZ4. For ELZ, the query is loaded during phase 3 of each Score call (after `Reset_Stream`) — the string table from phase 1 is preserved for phase 2's `|Q|C|` computation, then cleared and re-primed. For LZMA, the dictionary is loaded per-pass within each Score call. `|compress(Q,∅)|` is computed once at init and cached in `Query_Bare_CS` for the symmetric MI formula. |

### 3.3 Error and Exception Handling

| Condition | Mechanism | Exit code |
|---|---|---|
| Bad argument (invalid flag, missing value, out of range) | Print message to stderr, exit | 1 |
| File not found or unreadable (explicitly named) | Print message to stderr, exit | 2 |
| Pre-process command exits non-zero | Print message to stderr with command and exit status, exit | 2 |
| Permission denied during traversal (non-explicit) | Print warning to stderr, continue | 0 if any input read; 2 otherwise |
| Compression library error | `Compression_Error` exception (with backend-specific message) → print diagnostic to stderr, exit | 3 |
| Empty input (no chunks from any file, or no target files in file mode) | Print message to stderr, exit | 4 |
| File/chunk exceeds sliding-window size | Print warning to stderr, continue | 0 (warning only; processing continues) |

All exceptions not explicitly caught propagate to the main procedure's final
exception handler, which prints a generic error and exits with code 1. There is
no silent failure path.

### 3.4 Output Media and Formats

- **stdout — chunk mode:** Chunk output only — headers and raw chunk bytes
  (REQ-029, REQ-030). Must be left clean for piping.
- **stdout — file mode:** One line per result — `filename score` (REQ-066).
  No headers, no chunk data, no separators.
- **stderr:** All diagnostics, warnings, errors (REQ-034).
- **File output:** Not supported. All output is to standard streams.

### 3.5 Re-use of Shared Data and Shared Services

No shared global state between packages. Each package exports a pure functional
interface (no hidden side effects). The `Config` record is the single point of
configuration flow — it is constructed in `crab.adb` and passed as parameters to
subprograms in other packages.

### 3.6 External Interface Design

External interfaces are C library bindings — there are no network, file-format, or
inter-process interfaces beyond the CLI arguments and standard streams. The binding
packages are described in §5.

---

## 4. Architectural Design

### 4.1 Structural Decomposition — Unit Identification

| Unit | Type | Purpose |
|---|---|---|
| `Crab_Zlib` | Package (binding) | Thin Ada binding to libz streaming API |
| `Crab_LZ4` | Package (binding) | Thin Ada binding to liblz4 streaming dictionary API |
| `Crab_ELZ` | Package (algorithm) | Pure Ada ELZ with bounded/unbounded dictionary; random leaf eviction with deterministic LCG; raw heap node array; `ELZ_Stream` is `Limited_Controlled` for automatic cleanup |
| `Crab_LZMA` | Package (binding) | Thin Ada binding to liblzma streaming API |
| `Crab_Fnmatch` | Package (binding) | Thin Ada binding to libc `fnmatch()` for shell glob matching |
| `Crab_Buffers` | Package (utility) | Controlled heap-allocated byte buffer with automatic cleanup via `Finalize`; shared across all compression modules.  Replaces the bare unconstrained array that previously required manual `Unchecked_Deallocation`. |
| `Crab_Compression` | Package (abstraction) | Uniform compression interface dispatching to DEFLATE/LZ4/ELZ/LZMA backends; window-size query |
| `Crab_Fold` | Package (utility) | ASCII case folding for `--ignore-case` |
| `Crab_Preprocess` | Package (utility) | Spawn /bin/sh -c CMD to pre-process input before scoring |
| `Crab_Glob` | Package (utility) | Multi-pattern include/exclude matching using `fnmatch` |
| `Crab_Scanner` | Package (I/O) | Directory traversal with glob filtering and depth limiting |
| `Crab_Chunker` | Package (algorithm) | Streaming sliding-window chunk iterator (byte and line modes) |
| `Crab_Scorer` | Package (algorithm) | Stateful MI‑approx scorer using variant-record `State` to store typed backend-stream components |
| `Crab_TopK` | Package (algorithm) | Bounded binary heap maintaining the top-*k* (or bottom-*k*) scored entries; two output formats (chunk mode and file mode) |
| `crelz.adb` | Main procedure | gzip-like standalone ELZ file compressor/decompressor; depends on `Crab_ELZ` and `Crab_Buffers`; implements `.ez` file-format header serialisation/deserialisation and gzip-compatible CLI argument parsing |

### 4.2 Static Relationships — Dependency Graph

```
crab.adb
crelz.adb
 └── Crab_ELZ ── Crab_Buffers

 ├── Crab_Compression ──────┬── Crab_Zlib
 │                           ├── Crab_LZ4
 │                           ├── Crab_LZMA
 │                           └── Crab_ELZ
 ├── Crab_Fold
 ├── Crab_Preprocess ───────┬── GNAT.Expect
 │                           └── GNAT.OS_Lib
 ├── Crab_Scanner ──────────┬── Crab_Glob ─── Crab_Fnmatch
 │                           └── GNAT.OS_Lib
 ├── Crab_Chunker
 ├── Crab_Scorer ───────────┬── Crab_Compression
 │                           └── Crab_Buffers
 ├── Crab_TopK
```

- `crab.adb` depends on **all** application packages (it is the sole streaming orchestrator).
- `Crab_Compression` depends on `Crab_Zlib`, `Crab_LZ4`, `Crab_ELZ`, and `Crab_LZMA` (the backends).
- `Crab_Scorer` depends on `Crab_Compression` (buffer sizing, level defaults, window size)
  and `Crab_Buffers` (byte buffer type).  Backend-specific stream types
  (`Crab_Zlib.ZStream`, `Crab_LZ4.LZ4_Stream`, etc.) are held directly as
  typed components of a variant record in `Crab_Scorer.State` (discriminated
  by `Algorithm`) — the scorer spec uses `private with` to import each
  backend package, with no `System.Address` type-erasure and no
  `Unchecked_Conversion`.
- `Crab_Scanner` depends on `Crab_Glob`, which depends on `Crab_Fnmatch`.
- `Crab_Chunker`, `Crab_Fold`, and `Crab_TopK` have no internal dependencies
  (pure computation packages).  `Crab_Buffers` depends only on `Ada.Finalization`
  (for controlled-type cleanup).
- No circular dependencies. The dependency graph is a DAG rooted at `crab.adb`.

### 4.3 Dynamic Relationships — Execution Sequence

```
crab.adb
  │
  ├─[1] Parse_Args()                       → Config record
  ├─[2] Handle --help / --version          → exit 0 (if applicable)
  ├─[3] Validate query, mode-specific flags → exit 1 (if invalid)
  │
  ├─[4] IF File_Mode:
  │       ┌─[4a] Read query file          → Query_Data
  │       ├─[4b] IF -i: Fold(Query_Data)   → Scoring_Query
  │       ├─[4c] Warn if query file > window size
  │       ├─[4d] Scorer.Init (Scoring_Query, Query_Data'Length, Algo, Level)
  │       ├─[4e] Determine target file list (same as chunk mode)
  │       ├─[4f] FOR EACH target file:
  │       │        ┌─ Read file bytes      → File_Data
  │       │        ├─ Skip if path = query path
  │       │        ├─ IF --preprocess: Crab_Preprocess.Preprocess_Data(File_Data) → File_Data
  │       │        ├─ Warn if file > window size
  │       │        ├─ IF -i: Fold(File_Data) → Scoring_Data
  │       │        ├─ Score := Scorer.Score (Scoring_Data)
  │       │        └─ TopK.Insert (Score, Path, 0, "")
  │       └─[4g] TopK.Print_File_Scores → exit 0
  │
  ├─[5] ELSE (chunk mode):
  │       ┌─[5a] Scoring_Query := (if -i then Fold(Query) else Query)
  │       ├─[5b] Scorer.Init (Scoring_Query, Chunk_Size, Level)
  │       ├─[5c] Determine file list
  │       ├─[5d] FOR EACH file:
  │       │        ┌─ Read file bytes      → File_Buf
  │       │        ├─ IF --preprocess: Crab_Preprocess.Preprocess_Data(File_Buf) → File_Buf
  │       │        ├─ IF -i: Scoring_Buf := Fold(File_Buf)
  │       │        ├─ Warn if file > window size
  │       │        ├─ Chunker.Start (Scoring_Buf, Chunk_Size/Lines, Overlap)
  │       │        ├─ WHILE Chunker.Has_Next:
  │       │        │    Score := Scorer.Score (Chunk_Data)
  │       │        │    TopK.Insert (Score, File, Offset, Orig_Chunk)
  │       │        └─ (File_Buf released on next iteration or exit)
  │       └─[5e] TopK.Print → exit 0
  │
  │
  ├─ crelz.adb (separate executable):
  │       ┌─[C1] Parse_Args()               → Config record
  │       ├─[C2] Handle --help / --version   → exit 0
  │       ├─[C3] IF Decompress mode:
  │       │        ┌─ Verify file magic and suffix
  │       │        ├─ Read header (version, Original_Size, Max_Codes)
  │       │        ├─ Decompress(Max_Codes)   → output data
  │       │        └─ Write output (stdout or strip .ez suffix)
  │       ├─[C4] ELSE (compress mode):
  │       │        ┌─ Read file bytes or stdin
  │       │        ├─ Init_Roots, Set_Max_Codes
  │       │        ├─ Load_Dict (empty dict for bare compression)
  │       │        ├─ Compress_Stream → compressed data
  │       │        └─ Write header + compressed data (stdout or name.ez)
  │       ├─[C5] IF --test: decompress quietly, check integrity
  │       ├─[C6] IF --verbose: print ratio to stderr
  │       └─[C7] Replace original file (unless -k or -c)
  └─[6] Exception handlers → exit 1/2/3/4
```

### 4.4 Interfaces Between Units

Inter-package data flow uses Ada standard types (`String`, `Integer`, `Natural`)
and Ada standard containers (`Indefinite_Vectors`). Application-defined types
crossing package boundaries:

| Type | Defined in | Used by |
|---|---|---|
| `Crab_Compression.Algorithm` | `Crab_Compression` | `crab.adb`, `Crab_Scorer` |
| `Crab_Glob.Pattern_List` | `Crab_Glob` | `crab.adb`, `Crab_Scanner` |
| `Crab_Chunker.State` | `Crab_Chunker` | `crab.adb` |
| `Crab_Chunker.Line_State` | `Crab_Chunker` | `crab.adb` |
| `Crab_Scorer.State` | `Crab_Scorer` | `crab.adb` |
| `Crab_TopK.Heap` | `Crab_TopK` | `crab.adb` |

| `Crab_Buffers.Byte_Buffer` | `Crab_Buffers` | All compression modules, `Crab_Scorer` |

All cross-package types are defined in the producer package's specification. The
binding packages expose only subprograms — no types cross the binding boundary
into application code.

### 4.5 Concept of Execution

The component fulfills its requirements through a **streaming architecture**: each
file is read, scored (chunked or whole), and the best results retained — all in a
single pass per file. Only the top-*k* results accumulate across files. This maps
to the following processing model:

1. **Config stage** (arg parsing): produces configuration.
2. **Query-init stage**: loads the query as a compression dictionary once.
3. **File loop** (orchestrated by `crab.adb`):
   - **Read stage**: one file into a buffer.
   - **Fold stage**: if `-i`, produce folded copy for scoring.
   - **Warn stage**: if file exceeds algorithm window size, warn to stderr.
   - **Score stage**: compute MI‑approx for the current chunk (chunk mode) or
     whole file (file mode).
   - **Accumulate stage**: bounded heap insert-or-discard.
4. **Output stage**: drain heap in sorted order, print in mode-appropriate format.

Each non-orchestration stage can be tested in isolation with fixed inputs.
The heap-bounded nature means memory is O(largest_file + k × chunk_size) in chunk
mode, and O(largest_file + k × sizeof(Scored_Entry)) in file mode.

### 4.6 Design Decisions Affecting Multiple Units

| Decision | Affected units | Rationale |
|---|---|---|
| **Per-file processing, no concatenation** | crab.adb, Crab_Chunker, Crab_Scorer, Crab_TopK | Avoids loading all files into memory simultaneously. Each file is independent; the Top‑K accumulator crosses file boundaries. |
| **Bounded binary heap for top-k** | Crab_TopK | O(log *k*) insertion vs. O(*N* log *N*) full sort. Only *k* entries stored, not all *N*. |
| **Chunker as streaming iterator** | Crab_Chunker, crab.adb | No intermediate vector of all chunks. Chunk data is a substring slice of the file buffer — zero-copy. |
| **Line-based chunking mode** | Crab_Chunker, crab.adb | `--chunk-lines` (`-L`) partitions input into chunks of N consecutive lines; mutually exclusive with `--chunk-size`. |
| **File mode — whole-file scoring** | crab.adb, Crab_Scorer, Crab_TopK | `-f`/`--file-mode` compares a query file against target files as single units. No chunking; output is `filename score` per line. Reuses the same Scorer and TopK packages. |
| **Window-size warning** | crab.adb, Crab_Compression | `Crab_Compression.Window_Size` returns the sliding-window or dictionary-size limit for each algorithm. `crab.adb` warns on stderr when a file or chunk exceeds it, for both modes. ELZ is unbounded by default (level 9) — no warning. When a level-derived code limit is active or `--dict-size` is set for ELZ, the effective window size is approximately the code limit, and the warning is emitted when input exceeds it. LZMA's window size is user-specified via --dict-size (see REQ-070). |
| **Scorer stateful with dictionary-preloaded stream** | Crab_Scorer | Query loaded as dictionary into persistent streaming compressor once for DEFLATE and LZ4. For ELZ, a single stream is allocated at `Init` and reused across Score calls; three phases run on one stream — phase 1 builds the string table from C while emitting Bare_CS, phase 2 reuses that table to compress Q producing \|Q\|C\|, then `Reset_Stream` clears the table and phase 3 re-primes with Q for \|C\|Q\|. For LZMA (unbounded dictionary), streams are created and freed per-pass within each Score call. `Scorer.Init` creates the stream objects and caches `|compress(Q,∅)|`. `Scorer.Score` computes the symmetric MI: forward direction (compress C with/without Q as dict) plus reverse direction (compress Q with C as dict), averaged. |
| **`System.Address` for C buffer passing** | Crab_Zlib, Crab_LZ4, Crab_Fnmatch | Avoids intermediate copies when passing String data to C functions. |
| **GNAT.OS_Lib for canonical paths** | Crab_Scanner | `Normalize_Pathname` with `Resolve_Links => True` resolves symlinks and provides canonical paths for cycle detection. |
| **`Ada.Directories` for file system ops** | Crab_Scanner | Portable, already in GNAT runtime. Follows symlinks by default (matches REQ-044). |
| **`String` slice for chunk data** | Crab_Chunker, crab.adb | `Next` returns a slice of the scoring buffer — no allocation. |
| **Controlled byte buffer** | Crab_Buffers, Crab_Zlib, Crab_LZ4, Crab_LZMA, Crab_ELZ, Crab_Scorer | `Crab_Buffers.Byte_Buffer` is a `Limited_Controlled` type wrapping a heap-allocated `Element_Array` of `Ada.Streams.Stream_Element`.  `Finalize` frees the storage automatically — no manual `Unchecked_Deallocation` needed anywhere.  C-wrapping modules (`Crab_Zlib`, `Crab_LZ4`, `Crab_LZMA`) use `Crab_Buffers.Data_Address` to obtain the buffer address for FFI overlays.  `Crab_ELZ` uses `Crab_Buffers.Raw_Data` for direct indexed access in the bit-writer/reader hot path.  `Crab_Scorer` uses a variant record discriminated by `Algorithm`, storing each backend's stream types directly as typed components — the spec uses `private with` on each backend package, with no `System.Address` type-erasure and no `Unchecked_Conversion`. |
| **Persistent compression buffers and stream** | Crab_Zlib, Crab_LZ4, Crab_Compression, Crab_Scorer | One persistent output buffer (`Chunk_Buf`) allocated once in `Scorer.Init` as a controlled `Crab_Buffers.Byte_Buffer` and reused for every scoring call across all files.  `Chunk_Buf` is dynamically resized via `Crab_Buffers.Resize` if a chunk exceeds the current capacity — the old allocation is freed automatically.  Streaming compressor objects are stored directly in the variant-record `State`.  For DEFLATE and LZ4, two streams each are allocated at `Init` (dict + bare) and reused across calls.  For ELZ, `ELZ_Stream` is a `Limited_Controlled` component stored directly in `State`; three phases run on one stream (see §5.7), resetting and re-priming between phases.  For LZMA, streams are created and freed per-pass within each `Score` call using a local access type (arena pattern) for automatic cleanup without `Unchecked_Deallocation`. |
| **Pre-processing via shell command** | crab.adb, Crab_Preprocess | `--preprocess` / `-p CMD` delegates to `Crab_Preprocess.Preprocess_Data`, which spawns `/bin/sh -c CMD` via `GNAT.Expect.Get_Command_Output`, piping raw file bytes to the command's stdin and capturing stdout as pre-processed data.  Applies to all input sources (files, stdin) in both modes; does not apply to the query file in file mode.  Pre-processing occurs before case folding.  Non-zero exit from the command is treated as an I/O error (exit code 2).  `Crab_Preprocess` encapsulates the `GNAT.Expect` dependency; `crab.adb` depends only on `Crab_Preprocess`. |

### 4.7 Unit-to-Requirement Traceability

| Unit | Requirements covered |
|---|---|
| `crab.adb` | REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-008, REQ-033, REQ-034, REQ-063, REQ-064, REQ-065, REQ-067, REQ-074 |
| `Crab_Preprocess` | REQ-074 |
| `Crab_Zlib` | REQ-016 |
| `Crab_LZ4` | REQ-017 |
| `Crab_ELZ` | REQ-015 (elz algorithm) |
| `Crab_LZMA` | REQ-069 |
| `Crab_Fnmatch` | REQ-051 (via `fnmatch`), REQ-056 |
| `Crab_Compression` | REQ-015, REQ-018, REQ-019, REQ-020, REQ-067 (Window_Size) |
| `Crab_Fold` | REQ-047 |
| `Crab_Glob` | REQ-049, REQ-050, REQ-051, REQ-052 |
| `Crab_Scanner` | REQ-041, REQ-042, REQ-043, REQ-044, REQ-045, REQ-046, REQ-053, REQ-054 |
| `Crab_Chunker` | REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-059, REQ-060, REQ-061 |
| `Crab_Scorer` | REQ-021, REQ-022, REQ-023, REQ-024, REQ-025 |
| `Crab_TopK` | REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-055, REQ-066 |

---

## 5. Detailed Design

### 5.1 `crab.adb` — Main Procedure

| Attribute | Value |
|---|---|
| **Identifier** | `crab` |
| **Type** | Main procedure (executable entry point) |
| **Purpose** | Parse arguments, orchestrate the streaming pipeline in both chunk and file modes, handle errors, control exit codes. |

**Interfaces:**

```
Input:  Command-line arguments (via Ada.Command_Line)
        Standard input stream
        File system (reads input files)
Output: Standard output stream (chunk output or file-mode output via Crab_TopK)
        Standard error stream (diagnostics)
        Exit code (0–4)
```

**Data Elements (local to `crab.adb`):**

| Name | Type | Role |
|---|---|---|
| `Config` | Record | All parsed argument values |
| `Scoring_Query` | `String` | Query string or query file contents (folded if `-i`) |
| `Top_Heap` | `Crab_TopK.Heap` | Bounded heap maintaining top/bottom *k* |

**Config Record Definition:**

```ada
type Config is record
   Show_Help     : Boolean := False;
   Show_Version  : Boolean := False;
   Query         : Unbounded_String;
   Algorithm     : Crab_Compression.Algorithm := Crab_Compression.Deflate;
   Level         : Integer := Crab_Compression.Level_Default
                             (Crab_Compression.Deflate);
   Chunk_Size    : Natural := 0;   -- 0 = not set
   Chunk_Lines   : Natural := 0;   -- 0 = not set; mutually exclusive with Chunk_Size
   Overlap       : Natural := 0;
   Top_K         : Positive := 10;
   Recursive     : Boolean := False;
   Ignore_Case   : Boolean := False;
   Invert        : Boolean := False;
   File_Mode     : Boolean := False;
   Dict_Size              : Natural := 0;
   Has_Explicit_Algorithm : Boolean := False;
   Has_Explicit_Level     : Boolean := False;
   Has_Explicit_Dict_Size : Boolean := False;

   Preprocess_Cmd : Unbounded_String;
   Max_Depth     : Natural := Natural'Last;
   Include_Pats  : Crab_Glob.Pattern_List;
   Exclude_Pats  : Crab_Glob.Pattern_List;
   Paths         : String_Vector;
end record;
```

**Logic — Argument Parsing:**

```
procedure Parse_Args (Cfg : out Config) is
   -- Iterate Ada.Command_Line.Argument (1 .. Argument_Count).
   -- Position 1 is the query if not a recognized flag; remaining
   -- non-flag args go to Cfg.Paths.
   -- Flags:
   --   -h, --help       → Cfg.Show_Help
   --   --version        → Cfg.Show_Version
   --   -a, --algorithm  → next arg: "deflate" | "lz4" | "elz" | "lzma"
   --   -l, --level      → next arg: integer
   --   -s, --chunk-size → next arg: positive integer
   --   -L, --chunk-lines → next arg: positive integer
   --   -o, --overlap    → next arg: 0–99 integer
   --   -k, --top        → next arg: positive integer
   --   -r, --recursive  → set flag
   --   -i, --ignore-case→ set flag
   --   -v, --invert     → set flag
   --   -f, --file-mode  → set flag
   --   --include        → next arg: add to Cfg.Include_Pats
   --   --exclude        → next arg: add to Cfg.Exclude_Pats
   --   --max-depth      → next arg: non-negative integer
   --   -p, --preprocess → next arg: shell command string
   -- Validates: query non-empty; in chunk mode, exactly one of
   --   --chunk-size or --chunk-lines set and overlap in [0,99];
   --   in file mode, chunk flags are not required.
   --   Level in range per algo.
end Parse_Args;
```

**Logic — File Mode Orchestration:**

```
if Cfg.File_Mode then
   Query_Path := To_String (Cfg.Query);
   Query_Data := Read_File (Query_Path);
   Scoring_Query := (if -i then Fold(Query_Data) else Query_Data);
   Scorer.Init (Scoring_Query, Query_Data'Length, Algo, Level);
   Win_Size := Crab_Compression.Window_Size (Algo);

   -- Warn if query file exceeds window size
   if Win_Size < Natural'Last and Query_Data'Length > Win_Size then
      Put_Line (Stderr, "crab: warning: query file ... exceeds ... window size");
   end if;

   -- Determine target file list (same Scanner/explicit/stdin logic as chunk mode)
   -- FOR EACH target file:
   --    Skip if path = Query_Path
   --    Read file, warn if > Win_Size
   --    Score := Scorer.Score (folded data)
   --    TopK.Insert (Score, Path, 0, "")

   TopK.Print_File_Scores;
   return;
end if;
```

**Logic — Chunk Mode Orchestration (unchanged from v1.1):**

```
Scoring_Query := (if -i then Fold(Query) else Query);
Scorer.Init (Scoring_Query, Chunk_Size, Level);
-- Determine file list, process each file via Process_One_File
TopK.Print;
```

**Logic — `Process_One_File` helper (chunk mode):**

```
procedure Process_One_File (Path, Data, Heap, Scorer, Cfg) is
   Scoring_Buf := (if -i then Fold(Data) else Data);
   Win_Size := Crab_Compression.Window_Size (Cfg.Algorithm);

   -- Warn if file exceeds window size
   if Win_Size < Natural'Last and Data'Length > Win_Size then
      Put_Line (Stderr, "crab: warning: 'path' (size bytes) exceeds ... window size");
   end if;

   -- Chunk and score as before
   Chunker := (if Chunk_Lines > 0 then Start_Lines else Start);
   while Has_Next loop
      Chunk_Slice := Next;
      Score := Scorer.Score (Chunk_Slice);
      TopK.Insert (Score, Path, Offset, Orig_Chunk);
   end loop;
end Process_One_File;
```

### 5.1b `Crab_Preprocess` — Shell-Command Pre-Processing

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Preprocess` |
| **Type** | Package (utility) |
| **Purpose** | Spawn `/bin/sh -c CMD`, pipe raw input bytes to the command's stdin via `GNAT.Expect.Get_Command_Output`, capture stdout, and return the result.  Non-zero exit raises `Program_Error`. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Preprocess_Data (Raw_Data, Command)` | Function → `Unbounded_String` | Spawn `/bin/sh -c Command`, pipe `Raw_Data` through it, return stdout.  Raises `Program_Error` on non-zero exit. |

**Logic:**

```
function Preprocess_Data
  (Raw_Data : String;
   Command  : String) return Unbounded_String
is
   Status : aliased Integer;
   Result : constant String :=
     GNAT.Expect.Get_Command_Output
       (Command    => "/bin/sh",
        Arguments  => (1 => new String'("-c"),
                       2 => new String'(Command)),
        Input      => Raw_Data,
        Status     => Status'Access,
        Err_To_Out => True);
begin
   if Status /= 0 then
      Put_Line (Stderr, "crab: preprocess command '" & Command
                & "' exited with status" & Integer'Image (Status));
      Ada.Command_Line.Set_Exit_Status (2);
      raise Program_Error;
   end if;
   return To_Unbounded_String (Result);
end Preprocess_Data;
```

**Constraints:**
- Encapsulates the `GNAT.Expect` and `GNAT.OS_Lib` dependencies; `crab.adb` depends only on `Crab_Preprocess`.
- stderr from the spawned command is merged into stdout (`Err_To_Out => True`).
- The caller is responsible for handling the `Program_Error` exception; `crab.adb` catches it at the top level and maps it to exit code 2 (I/O error).

**Constraints:** `crab.adb` is the only unit that calls `Ada.Command_Line` or
`Ada.Directories` directly. It is the sole orchestrator — no other unit makes
decisions about file ordering, mode dispatch, or output format selection.


### 5.1a `Crab_Buffers` — Controlled Byte Buffer

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Buffers` |
| **Type** | Package (utility) |
| **Purpose** | Provide a heap-allocated byte buffer with automatic cleanup via `Ada.Finalization.Limited_Controlled`.  Replaces the bare unconstrained array that previously required manual `Unchecked_Deallocation` at every allocation site. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Byte_Buffer` | Controlled type | Wraps a heap-allocated `Element_Array` of `Ada.Streams.Stream_Element`.  `Finalize` frees the storage automatically. |
| `Resize (B, Size)` | Procedure | Reallocate to hold at least `Size` bytes.  Old contents are discarded.  If `Size = 0` the buffer is deallocated. |
| `Length (B)` | Function → Natural | Current allocated size in bytes.  Returns 0 if unallocated. |
| `Data_Address (B)` | Function → System.Address | Address of the first byte, for C FFI overlays.  Returns `System.Null_Address` if `Length = 0`. |
| `Element (B, Index)` | Function → Stream_Element | Indexed access (1-based).  For non-performance-critical use. |
| `Set_Element (B, Index, Value)` | Procedure | Indexed write (1-based). |
| `Raw_Data (B)` | Function → Element_Array_Access | Direct pointer to the underlying array for performance-sensitive code (ELZ bit-writer/reader).  Caller must not free.  Returns null if `Length = 0`. |

**Constraints:**
- Not `Pure` — depends on `Ada.Finalization` for controlled-type cleanup.
- `Resize` always frees the old allocation before creating a new one; old contents are not preserved.
- `Raw_Data` exposes the internal pointer for direct indexing in hot paths; the caller must respect the bounds `1 .. Length`.

### 5.2 `Crab_Zlib` — zlib Binding

*(Unchanged from v1.1 design.)*

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Zlib` |
| **Type** | Package (C binding) |
| **Purpose** | Provide streaming compression with dictionary pre-loading backed by libz.  Public API uses pure-Ada `Crab_Buffers.Byte_Buffer`; C types (`Interfaces.C`) are confined to the body. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Zlib_Error` | Exception | Raised when any zlib function returns an error status |
| `Compress_Bound (Source_Len)` | Function → Natural | Maximum possible compressed size |
| `Init_Stream (Level)` | Function → `ZStream` | Initialise a new `z_stream` in deflate mode |
| `Set_Dict (Stream, Dict)` | Procedure | Load `Dict` into the stream's compression dictionary |
| `Compress_Stream (Stream, Source, Dest)` | Procedure → out `Dest_Len: Natural` | Compress `Source` using the stream's current state |
| `Free_Stream (Stream)` | Procedure | Deallocate the z_stream |
| `Compress_Bare (Source, Level, Dict)` | Function → Natural | Convenience: init, set dict, compress, free |

**Constraints:**
- The stream is created once in `Scorer.Init` with the query as dictionary,
  and reused via `Compress_Stream` / `deflateReset` for every chunk.
- `deflateReset` preserves the dictionary, so `Set_Dict` is only called once.
- The dictionary is limited to 32 KB (zlib's sliding window size).

### 5.3 `Crab_LZ4` — LZ4 Binding

*(Unchanged from v1.1 design.)*

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_LZ4` |
| **Type** | Package (C binding) |
| **Purpose** | Provide streaming compression with dictionary pre-loading backed by liblz4.  Public API uses pure-Ada `Crab_Buffers.Byte_Buffer`; C types are confined to the body. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `LZ4_Error` | Exception | Raised when any LZ4 function returns an error status |
| `Compress_Bound (Input_Size)` | Function → Natural | Maximum possible compressed size |
| `Init_Stream` | Function → `LZ4_Stream` | Create a new LZ4 stream |
| `Load_Dict (Stream, Dict)` | Procedure | Load dictionary into the stream |
| `Compress_Stream (Stream, Source, Dest, Acceleration)` | Procedure → out `Dest_Len: Natural` | Compress `Source` using stream state |


| `Compress_Bare (Source, Acceleration, Dict)` | Function → Natural | Convenience: create, load dict, compress, free |

**Constraints:**
- The LZ4 dictionary is limited to 64 KB.

### 5.4 `Crab_ELZ` — ELZ Compression

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_ELZ` |
| **Type** | Package (algorithm) |
| **Purpose** | Pure Ada ELZ (Explicit-LZ) compression — an LZ78 variant that emits explicit suffix bytes after each prefix code.  Unlike standard LZW (which omits the suffix and requires the decoder to infer it via a KwKwK special case), ELZ encodes each dictionary entry as a `(prefix_code, suffix_byte)` pair.  This eliminates the KwKwK edge case entirely, simplifies the decoder, and makes bounded-mode eviction more robust since the decoder never needs to extract a first character by walking potentially-evicted prefix chains.  Uses only pure-Ada types (`Character`, modular types `Word64`/`Word32`); no `Interfaces.C` dependency.  Public API uses `Crab_Buffers.Byte_Buffer`. |

**Encoding:** When the inner matching loop finds a prefix that cannot be extended by byte *C*, the encoder emits `(Old_Prefix, C)` as a pair — the prefix code at the current code width, followed by the suffix byte as an 8-bit raw value — then starts the next string from the following input byte (skipping *C*).  A final trailing prefix code (without a suffix) terminates the stream when input is exhausted after a match.  The inner matching loop, dictionary data structure (hash table + `ELZ_Node` array), and bounded-mode eviction are identical to standard LZW; only the output emission and the decoder restart logic differ.

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `ELZ_Error` | Exception | Raised on compression failure |
| `Compress_Bound (Input_Size)` | Function → Natural | Conservative upper bound for compressed size: `ceil(Input_Size × (max_code_width + 8) / 8) + 1`.  The +8 accounts for the explicit suffix byte's 8 bits per emitted pair |
| `Init_Roots (S)` | Procedure | Initialise string table with 256 single-byte root nodes and an empty hash table.  Must be called before first use and after `Reset_Stream` when reusing a stream |
| `Load_Dict (S, Dict)` | Procedure | Prime the string table by compressing Dict through it (no output produced).  After a miss during priming, the encoder skips the failing byte and starts a fresh string — matching the same restart logic used in `Compress_Stream` |
| `Compress_Stream (S, Source, Dest, Level, Dest_Len)` | Procedure | Compress Source using the primed string table.  Emits `(prefix_code, suffix_byte)` pairs on dictionary misses; the final unmatched prefix is emitted alone.  `Level` is accepted for interface compatibility but ignored |
| `Reset_Stream (S)` | Procedure | Reset to initial state (256 single-byte roots, empty string table). Preserves `Max_Codes` setting and allocation; faster than Free + Init |
| `Set_Max_Codes (S, N)` | Procedure | Set the maximum number of active codes. 0 = unbounded (default). When the table reaches the limit, deterministic random leaf eviction using an LCG reuses code slots |
| `Compress_Bare (Source, Dict)` | Function → Natural | Convenience: `Init_Roots` → `Load_Dict` → `Compress_Stream`.  Returns compressed byte count |
| `Decompress (Source, Source_Len, Max_Codes)` | Function → String | Decompress ELZ data.  Reads `(prefix_code, suffix_byte)` pairs; when a suffix read fails (source exhausted), the final prefix code is emitted alone as a standalone final code.  No KwKwK special case.  `Max_Codes` = 0 means unbounded; >0 activates deterministic leaf eviction mirror for bounded-mode roundtrip (REQ-093).  Raises `ELZ_Error` on malformed input |

**Constraints:**
- By default (level 6), the ELZ string table is bounded to 1,000,000 active codes
  (codes 256 and above; ~38 MB).  The code limit is derived from the normalised
  level via exponential scaling (see §5.6) and can be overridden with `--dict-size`.
  When the limit is 0, the table grows without bound.  When a positive limit is
  set, the table is bounded to at most that many active codes.
- When the table reaches the limit, the compressor selects a random leaf code (a code with no children in the
  prefix trie) via a deterministic LCG and reuses the freed code slot for the
  new entry.  The decompressor mirrors the same LCG deterministically,
  requiring no additional bits in the compressed stream.  Because the decoder
  never walks prefix chains to extract a first character (no KwKwK), evicted
  intermediate nodes cannot cause decoder failures — only the decoder's own
  `De_Evict_One` mirror must remain synchronised.
- The effective window size for the window-size warning (REQ-067) is
  approximately *N* bytes when the code limit is set.
- `Reset_Stream` calls `Init_Roots` internally; it clears the string table
  and hash map while preserving the heap allocation.  After `Reset_Stream`,
  the stream is equivalent to a freshly `Init_Roots`'d instance.
- `Compress_Stream` does not leave a residual prefix — after it returns,
  `Have_Prefix = False`, so the string table is a pure dictionary ready
  for lookups without artificial prefix carry-over.
- Compressed output is approximately 50% larger per dictionary entry than
  standard LZW (8 extra bits per emitted pair), but the decoder is simpler
  and bounded-mode eviction is robust against chain-walk failures.

### 5.4a `Crab_LZMA` — LZMA Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_LZMA` |
| **Type** | Package (C binding) |
| **Purpose** | Provide streaming compression with dictionary pre-loading backed by liblzma.  Public API uses pure-Ada `Crab_Buffers.Byte_Buffer`; C types are confined to the body. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `LZMA_Error` | Exception | Raised when any liblzma function returns an error status |
| `Compress_Bound (Input_Size)` | Function → Natural | Maximum possible compressed size |
| `Init_Stream (Level, Dict_Size)` | Function → `LZMA_Stream` | Initialise a new `lzma_stream` with explicit dictionary size |
| `Load_Dict (Stream, Dict)` | Procedure | Prime the encoder by compressing Dict through it |
| `Compress_Stream (Stream, Source, Dest, Dest_Len)` | Procedure | Compress Source using the primed encoder state |
| `Free_Stream (Stream)` | Procedure | Deallocate the lzma_stream |
| `Compress_Bare (Source, Level, Dict_Size, Dict)` | Function → Natural | Convenience: init, load dict, compress, free |

**Constraints:**
- The LZMA dictionary size is set independently via the `--dict-size` flag
  (see REQ-070).  The default is 8 MB.  The dictionary size is passed to
  `lzma_stream_encoder` via `lzma_options_lzma.dict_size`.
- The stream is created once in `Scorer.Init` with the query as dictionary,
  and reused via `Compress_Stream` for every chunk.  The encoder must be
  re-primed with the dictionary before each compression call because
  `lzma_code` with `LZMA_FINISH` consumes the encoder state.
- The dictionary is loaded by compressing the query through the encoder
  (`lzma_code` with `LZMA_RUN`), which populates the internal LZMA
  dictionary structures.

### 5.5 `Crab_Fnmatch` — POSIX fnmatch Binding

*(Unchanged from v1.0 design.)*

### 5.6 `Crab_Compression` — Compression Abstraction

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Compression` |
| **Type** | Package (abstraction) |
| **Purpose** | Provide a uniform compression interface dispatching to DEFLATE/LZ4/ELZ/LZMA backends. Includes dictionary-aware streaming, bare compression, buffer sizing, and window-size query. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Algorithm` | Enumeration | `(Deflate, LZ4, ELZ, LZMA)` |
| `Compression_Error` | Exception | Propagated from backend errors |
| `Compress_Bound (Algo, Source_Len)` | Function → Natural | Upper bound for buffer pre-allocation |
| `Compress_Bare (Algo, Source, Level, Dict)` | Function → Natural | One-shot: init stream, set dict, compress, free |
| `Level_Default (Algo)` | Function → Integer | Default compression level |
| `Level_Min (Algo)` | Function → Integer | Minimum valid level |
| `Level_Max (Algo)` | Function → Integer | Maximum valid level |
| `Window_Size (Algo)` | Function → Natural | Sliding-window/dictionary size limit in bytes |

**`Window_Size` dispatch:**

```
function Window_Size (Algo : Algorithm) return Natural is
begin
   case Algo is
      when Deflate => return 32_768;   -- 32 KB (MAX_WBITS = 15)
      when LZ4     => return 65_536;   -- 64 KB
      when ELZ     => return Natural'Last;  -- unbounded (use level/dict)
      when LZMA    => return 8_388_608;  -- 8 MB (default)
   end case;
end Window_Size;

Note: LZMA window size is user-specified via the `--dict-size` flag
(see REQ-070).  ELZ effective window size is derived from the normalised
level or the `--dict-size` override.  The warning logic in `crab.adb` uses
`Effective_Window_Size(Cfg)` which accounts for explicit dict-size
overrides and level-derived ELZ max-codes.
```

**Normalised level mapping (0..9 for all algorithms):**

| Algorithm | Default | Min | Max | Level Interpretation | Window |
|---|---|---|---|---|---|
| Deflate | 6 | 0 | 9 | Passed directly to zlib | 32,768 |
| LZ4 | 6 | 0 | 9 | Mapped to acceleration 2^(9−level) | 65,536 |
| ELZ | 6 | 0 | 9 | Exponential max-codes (table below) | level-derived |
| LZMA | 6 | 0 | 9 | Passed directly to liblzma | user-specified (default 8,388,608) |

**ELZ exponential max-codes scaling:**

| Level | Max Codes | Approx. Memory |
|---|---|---|
| 0 | 1,000 | ~40 KiB |
| 1 | 3,162 | ~120 KiB |
| 2 | 10,000 | ~400 KiB |
| 3 | 31,623 | ~1.2 MiB |
| 4 | 100,000 | ~3.8 MiB |
| 5 | 316,228 | ~12 MiB |
| 6 | 1,000,000 | ~38 MiB |
| 7 | 3,162,278 | ~120 MiB |
| 8 | 10,000,000 | ~380 MiB |
| 9 | 0 (unbounded) | ∞ |

Implemented as a compile-time constant lookup table in `Crab_Compression.ELZ_Max_Codes_For_Level`.  The `--dict-size` flag overrides the level-derived value when set.

**Default algorithm selection (when no `--algorithm` given):**

```
function Auto_Select_Algorithm (Cfg : Config) return Algorithm is
   Query_Len : constant Natural := Length (Cfg.Query);
   Estimated_Chunk_Bytes : Natural;
begin
   if Cfg.File_Mode then
      return ELZ;
   end if;
   if Cfg.Chunk_Lines > 0 then
      Estimated_Chunk_Bytes :=
        Query_Len + Cfg.Chunk_Lines * 120;  -- 120 bytes/line heuristic
   else
      Estimated_Chunk_Bytes := Query_Len + Cfg.Chunk_Size;
   end if;
   if Estimated_Chunk_Bytes < 65_536 then
      return LZ4;
   else
      return ELZ;
   end if;
end Auto_Select_Algorithm;
```

**Config post-processing:** If `Has_Explicit_Algorithm` is false after parsing, `Auto_Select_Algorithm` runs.  If `Has_Explicit_Level` is false, `Cfg.Level := 6` (the normalised default).  If `Has_Explicit_Dict_Size` is false, `Cfg.Dict_Size` is set to `Crab_Compression.Default_Dict_Size (Cfg.Algorithm)`.

**LZ4 `Load_Dict` fix:** liblz4 ≥ 1.9 returns 0 (not `Dict.Length`) for dictionaries smaller than `HASH_UNIT` (8 bytes).  The `Load_Dict` binding was changed from checking `Bytes < Dict.Length` to `Bytes < 0`.  Additionally, `LZ4_loadDict` stores a pointer to the dict data, not a copy — the dictionary strings in `Crab_Scorer.Score` must remain alive across `Load_Dict` and `Compress_Stream` calls, so they are declared as local constants in a declare block spanning the LZ4 scoring operations.

### 5.7 `Crab_Scorer` — Stateful MI Scorer


*(Updated for LZMA. The same `Init` and `Score` subprograms serve both
chunk mode and file mode — in file mode, the "chunk" passed to `Score` is the
entire target file content.  LZMA streams are added alongside the existing
DEFLATE, LZ4, and ELZ streams.)*
| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Scorer` |
| **Type** | Package (algorithm) |
| **Purpose** | Pre-load the query as a compression dictionary; cache `|compress(Q,∅)|`; hold persistent stream objects; score individual chunks or whole files via symmetric MI: forward (C with/without Q) plus reverse (Q with C as dict), averaged.  For DEFLATE and LZ4, streams are pre-loaded with the query dictionary and reused across all scoring calls.  For ELZ, a single stream is allocated at Init and reused across Score calls: phase 1 compresses C against an empty dict (producing Bare_CS while building C's string table), phase 2 compresses Q reusing C's string table for lookups (producing \|Q\|C\|), then `Reset_Stream` clears the table and phase 3 re-primes with Q to compress C against Q's string table (producing \|C\|Q\|).  For LZMA (unbounded dictionary), streams are created and freed per-pass within each Score call.  Backend-specific stream types are stored directly as typed components of the variant record — `private with` clauses import each backend's private type definition.  No `System.Address` type-erasure, no `Unchecked_Conversion`. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `State` | Variant record type discriminated by `Algorithm` | Cached scorer state including persistent streams and buffer.  Components: `Level`, `Dict_Size`, `Dict_Explicit`, `Chunk_Buf`, `Query_Str`, `Query_Bare_CS`, plus backend-specific variant components. |
| `Init (S, Query, Chunk_Size, Level, Dict_Size, Dict_Explicit)` | Procedure | Create persistent stream objects; pre-allocate `Chunk_Buf` via `Crab_Buffers.Resize`.  The `Algorithm` discriminant is set at `State` declaration time.  For DEFLATE and LZ4, two streams each (dict + bare) are created and the Query is loaded as a dictionary.  For ELZ, `Init_Roots` initialises the stream component; `Set_Max_Codes` sets the code limit from `Dict_Size` (when `Dict_Explicit`) or from `ELZ_Max_Codes_For_Level (Level)`.  For LZMA, `Dict_Size` controls the dictionary size; no persistent streams. |
| `Score (S, Chunk)` | Function → Integer | MI‑approx score for one chunk/file using pre-loaded streams |

**Constraints:**
- `Chunk_Buf` is a controlled `Crab_Buffers.Byte_Buffer` — `Finalize` frees it
  automatically, no manual `Unchecked_Deallocation`.  It is dynamically resized
  via `Crab_Buffers.Resize` if the input exceeds the initial allocation.  For
  ELZ, the buffer is sized for `max(compressBound(chunk), compressBound(query))`
  because phases 2 and 3 write both chunk-sized and query-sized outputs to the
  same buffer.
- Scores are signed `Integer` (REQ-025).
- LZ4 dictionary lifetime: `LZ4_loadDict` stores a pointer (not a copy) to the
  dictionary data.  In `Score`, the dictionary strings are declared as local
  constants in a declare block that spans both `Load_Dict` and `Compress_Stream`
  calls, ensuring they remain alive during compression.
- For DEFLATE and LZ4, two `State` slots (`Dict_Stream`, `Bare_Stream`) hold
  distinct stream handles.  For ELZ, only `Bare_Stream` holds the single stream;
  `Dict_Stream` is `Null_Handle`.  Finalize frees whichever handle is non-null.

### 5.8 `Crab_Fold` — Case Folding

*(Unchanged from v1.0 design.)*

### 5.9 `Crab_Glob` — Glob Pattern Matching

*(Unchanged from v1.0 design.)*

### 5.10 `Crab_Scanner` — Directory Traversal

*(Unchanged from v1.0 design.)*

### 5.11 `Crab_Chunker` — Streaming Chunk Iterator

*(Unchanged from v1.1 design. Used only in chunk mode.)*

### 5.12 `Crab_TopK` — Bounded Top-K Heap

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_TopK` |
| **Type** | Package (algorithm) |
| **Purpose** | Maintain the top-*k* (or bottom-*k*) scored entries using a bounded binary heap. Provide sorted extraction and formatted printing in two output formats: chunk mode (headers + data) and file mode (filename + score). |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Scored_Entry` | Private type | `(Score: Integer; File_Path: Unbounded_String; Offset: Natural; Data: Unbounded_String)` |
| `Heap` | Private type | Bounded binary heap |
| `Create (K, Invert)` | Function → `Heap` | Initialise empty heap |
| `Insert (Heap, Score, File_Path, Offset, Data)` | Procedure | Insert or discard based on score vs. heap minimum (or maximum) |
| `Is_Empty (Heap)` | Function → Boolean | True if no entries inserted |
| `Count (Heap)` | Function → Natural | Number of entries currently held |
| `Print (Heap)` | Procedure | Chunk-mode output: headers + chunk data to stdout |
| `Print_File_Scores (Heap)` | Procedure | File-mode output: one line per entry, `filename score` |

**Heap strategy (unchanged):**

- **Normal mode** (`Invert = False`): min-heap on score.
- **Invert mode** (`Invert = True`): max-heap on score.

**Logic — `Print_File_Scores`:**

```
procedure Print_File_Scores (Heap : in out Heap) is
   -- Copy entries to array, sort (best first), print one line per entry:
   --   "filepath score\n"
   -- No headers, no chunk data, no separators.
begin
   Copy Entries(1..Size) to array;
   Sort (best first, respecting Invert);
   for each entry:
      Write_Str (File_Path & " " & Image (Score) & LF);
end Print_File_Scores;
```

**Constraints:**
- `Scored_Entry.Data` may be empty in file mode (no chunk data stored).
- Heap operations are O(log *k*). With *k* typically small (default 10), this is
  negligible.

### 5.13 `crelz.adb` — Standalone ELZ Compressor/Decompressor

| Attribute | Value |
|---|---|
| **Identifier** | `crelz` |
| **Type** | Main procedure (executable entry point) |
| **Purpose** | Provide a `gzip`-like standalone ELZ file compressor/decompressor sharing the `Crab_ELZ` package with `crab`.  Reads files or stdin, compresses/decompresses to `.ez` format, handles all CLI flags. |

**Interfaces:**

```
Input:  Command-line arguments (via Ada.Command_Line)
        Standard input stream
        File system (reads input files, writes/deletes output files)
Output: Standard output stream (compressed or decompressed data)
        Standard error stream (diagnostics, verbose ratio, test results)
        Exit code (0–4)
```

**Data Elements (local to `crelz.adb`):**

| Name | Type | Role |
|---|---|---|
| `Config` | Record | All parsed argument values |
| `Header` | Record | `.ez` file-format header (magic, version, original_size, max_codes) |

**Config Record Definition:**

```ada
type Config is record
   Show_Help     : Boolean := False;
   Show_Version  : Boolean := False;
   Decompress    : Boolean := False;
   Stdout_Mode   : Boolean := False;
   Keep          : Boolean := False;
   Force         : Boolean := False;
   Verbose       : Boolean := False;
   Test_Integrity : Boolean := False;
   Quiet         : Boolean := False;
   Recursive     : Boolean := False;
   Level         : Natural := 6;     -- 1..9 (preset), or overridden by Max_Codes
   Max_Codes     : Natural := 1_000_000;  -- 0 = unbounded; preset by Level
   Max_Set       : Boolean := False; -- True when --max-codes explicitly given
   Suffix        : Unbounded_String; -- default ".ez"
   Paths         : String_Vector;
end record;
```

**Logic — Argument Parsing:**

```
procedure Parse_Args (Cfg : out Config) is
   -- Iterate Ada.Command_Line.Argument (1 .. Argument_Count).
   -- Flags:
   --   -h, --help       → Cfg.Show_Help
   --   --version        → Cfg.Show_Version
   --   -d, --decompress  → Cfg.Decompress
   --   -c, --stdout     → Cfg.Stdout_Mode
   --   -k, --keep       → Cfg.Keep
   --   -f, --force      → Cfg.Force
   --   -v, --verbose    → Cfg.Verbose
   --   -t, --test       → Cfg.Test_Integrity
   --   -q, --quiet      → Cfg.Quiet
   --   -r, --recursive  → Cfg.Recursive
   --   -S, --suffix     → next arg: set Cfg.Suffix
   --   -1..-9, --fast, --best → map to Cfg.Level; set Cfg.Max_Codes preset
   --   --max-codes      → next arg: set Cfg.Max_Codes; set Cfg.Max_Set
   --   Remaining args   → Cfg.Paths (or stdin if empty)
end Parse_Args;
```

**Logic — Compression Path:**

```
procedure Compress_File (Path, Data, Cfg) is
   Stream : ELZ_Stream;
   Buf    : Crab_Buffers.Byte_Buffer;
begin
   Init_Roots (Stream);
   Set_Max_Codes (Stream, Cfg.Max_Codes);
   -- Compress bare (empty dictionary):
   Compress_Stream (Stream, Data, Buf, 0, Dest_Len);
   -- Write header (magic "CREL", version=1, Original_Size, Max_Codes)
   -- Write compressed bitstream
   -- IF --verbose: print ratio to stderr
   -- Delete original unless --keep or --stdout
end Compress_File;
```

**Logic — Decompression Path:**

```
procedure Decompress_File (Path, Data, Cfg) is
   Header : read from Data;
   -- Verify magic "CREL", check version
   Output : String := Crab_ELZ.Decompress (
     Compressed_Data, Compressed_Len, Header.Max_Codes);
begin
   -- Check Output'Length = Header.Original_Size (or warn)
   -- IF --test: print "OK" to stderr; return
   -- Write Output to stdout or stripped-path file
   -- IF --verbose: print ratio to stderr
   -- Delete compressed file unless --keep or --stdout
end Decompress_File;
```

**Constraints:**
- Depends on `Crab_ELZ` and `Crab_Buffers` only — no other crab packages.
- No dependency on `Crab_Compression`, `Crab_Scorer`, `Crab_Chunker`, or other packages.
- The `.ez` header is fixed 17 bytes (4 magic + 1 version + 8 original_size + 4 max_codes).
- `--test` mode decompresses entirely into memory; for very large files this may stress the system.
- Recursive mode (`-r`) uses `Ada.Directories` for traversal; reuses the same pattern as `Crab_Scanner` (deterministic depth-first, lexicographic sort, symlink-following).
- Bounded-mode decompression activates the `De_Evict_One` mirror already present (but disabled) in `Crab_ELZ.Decompress`; the `Max_Codes` parameter from the file header is passed through.


---

## 6. Requirements Traceability

### 6.1 Requirement-to-Unit Map

| Requirement | Implementing Unit(s) | Detail |
|---|---|---|
| REQ-001 | `crab.adb` | `Parse_Args` handles all flags including `-f` |
| REQ-002 | `crab.adb` | `-h`/`--help` detection; `Print_Usage` |
| REQ-003 | `crab.adb` | `--version` detection |
| REQ-004 | `crab.adb` | Query validation; file path in file mode |
| REQ-063 | `crab.adb` | `-f`/`--file-mode` flag; whole-file scoring path |
| REQ-064 | `crab.adb`, `Crab_Scorer` | Query file read; dictionary pre-loading |
| REQ-065 | `crab.adb`, `Crab_Scorer` | Whole-file scoring via `Scorer.Score` |
| REQ-066 | `Crab_TopK` | `Print_File_Scores` — `filename score` output |
| REQ-067 | `crab.adb`, `Crab_Compression` | `Window_Size` query; stderr warning in both modes |
| REQ-047 | `Crab_Fold`, `crab.adb` | `Fold` applied to Query and each file buffer when `-i` |
| REQ-005 | `crab.adb` | `Process_One_File` per file; files processed independently |
| REQ-006 | `crab.adb` | `Read_Stdin` path when no files/dirs |
| REQ-007 | `crab.adb` | Byte-oriented reads; no encoding conversion |
| REQ-008 | `crab.adb` | `Name_Error` handler in file loop → exit 2 |
| REQ-041 | `Crab_Scanner`, `crab.adb` | `-r` flag → `Scan` call |
| REQ-042 | `Crab_Scanner` | `Walk` descends all subdirs |
| REQ-043 | `Crab_Scanner` | Deterministic sort order |
| REQ-044 | `Crab_Scanner` | Symlink following |
| REQ-045 | `Crab_Scanner` | Traversal error → warning, continue |
| REQ-046 | `Crab_Scanner` + `crab.adb` | Empty `Files` vector → exit 2 or 4 |
| REQ-049 | `Crab_Glob`, `Crab_Scanner` | `Include_Pats` → `Should_Process` |
| REQ-050 | `Crab_Glob`, `Crab_Scanner` | `Exclude_Pats` → `Should_Process` |
| REQ-051 | `Crab_Fnmatch`, `Crab_Glob` | `fnmatch()` via `Match` |
| REQ-052 | `Crab_Scanner` | Globs only applied in `Scan` |
| REQ-053 | `Crab_Scanner` | `Max_Depth` parameter in `Walk` |
| REQ-054 | `crab.adb`, `Crab_Scanner` | `Max_Depth := Natural'Last` default |
| REQ-009 | `Crab_Chunker` | Fixed-size chunks |
| REQ-010 | `crab.adb`, `Crab_Chunker` | `--chunk-size` validated |
| REQ-011 | `Crab_Chunker` | Overlap step calculation |
| REQ-012 | `crab.adb` | `Parse_Args` validates [0,99] |
| REQ-013 | `Crab_Chunker` | Last chunk shorter |
| REQ-014 | `crab.adb` | Empty input check |
| REQ-059 | `Crab_Chunker`, `crab.adb` | `--chunk-lines` validated |
| REQ-060 | `Crab_Chunker` | Line-mode chunking |
| REQ-061 | `Crab_Chunker` | Line-mode overlap |
| REQ-062 | `Crab_Chunker`, `Crab_TopK` | Line-mode offset semantics |
| REQ-015 | `Crab_Compression`, `crab.adb` | `Algorithm` enum; `Parse_Args` validates |
| REQ-016 | `Crab_Zlib` | DEFLATE streaming API |
| REQ-017 | `Crab_LZ4` | LZ4 streaming dictionary API |
| REQ-069 | `Crab_LZMA` | LZMA streaming API |
| REQ-018 | `crab.adb`, `Crab_Compression` | `Level` parameter; defaults |
| REQ-019 | `crab.adb` | `Parse_Args` validates range per algorithm |
| REQ-020 | `Crab_Zlib`, `Crab_LZ4`, `Crab_ELZ`, `Crab_LZMA` | Return `Natural` compressed byte count |
| REQ-021 | `Crab_Scorer` | `Score = (Bare_CS − Dict_CS + Query_Bare_CS − Query_Dict_CS) / 2` |
| REQ-022 | `Crab_Scorer` | `Init` creates persistent stream objects |
| REQ-023 | `Crab_Scorer` | Dictionary is Query; no concatenation |
| REQ-024 | `crab.adb` + `Crab_Scorer` | `Score` called for every chunk/file |
| REQ-025 | `Crab_Scorer`, `Crab_TopK` | `Score : Integer` (signed) |
| REQ-026 | `Crab_TopK` | Bounded heap selects top/bottom *k* |
| REQ-027 | `Crab_TopK`, `crab.adb` | Heap capacity = *k* |
| REQ-028 | `Crab_TopK` | `Print` / `Print_File_Scores` sort descending (or ascending with `Invert`) |
| REQ-029 | `Crab_TopK` | Chunk-mode header format |
| REQ-030 | `Crab_TopK` | Chunk-mode data output |
| REQ-031 | `Crab_TopK` | Blank line separator (chunk mode) |
| REQ-032 | `Crab_TopK` | Tie-break: earlier offset ranks higher |
| REQ-055 | `Crab_TopK`, `crab.adb` | `Invert` parameter; max-heap mode |
| REQ-033 | `crab.adb` | Exit codes |
| REQ-034 | `crab.adb`, `Crab_Scanner` | All diagnostics to `Standard_Error` |
| REQ-035 | `alire.toml`, `crab.gpr` | Linker flags for `-lz`, `-llz4`, `-llzma` |
| REQ-036 | Build system | GNAT 13, Linux x86_64 |
| REQ-037 | Build system | `alr build` via `crab.gpr` |
| REQ-038 | All units | Ada 2012 |
| REQ-039 | `alire.toml` | License field |
| REQ-040 | `crab_config.gpr` | GNAT style switches |
| REQ-056 | `Crab_Fnmatch` | `fnmatch()` import |
| REQ-057 | `share/man/man1/crab.1` | Static man page source |
| REQ-071 | `share/agents/skills/crab/SKILL.md` | Agent skill for semantic search |
| REQ-073 | `README.md` | Project overview, installation, usage, documentation links |
| REQ-072 | `Crab_Compression`, `Crab_ELZ`, `crab.adb` | `ELZ_Max_Codes_For_Level` (exponential); `--dict-size` override; `Set_Max_Codes`; `Evict_One`; bounded mode |
| REQ-074 | `crab.adb`, `Crab_Preprocess` | `--preprocess` / `-p` flag; `Crab_Preprocess.Preprocess_Data` spawns `/bin/sh -c CMD` via `GNAT.Expect.Get_Command_Output` |
| REQ-075 | `crab.gpr`, `crelz.adb` | Second executable; `for Main use ("crab.adb", "crelz.adb")` |
| REQ-076 | `crelz.adb`, `Crab_ELZ` | Default compression: `Compress_Stream` → `.ez` file with header |
| REQ-077 | `crelz.adb`, `Crab_ELZ` | `-d` flag: `Decompress(Max_Codes)` → strip `.ez` suffix |
| REQ-078 | `crelz.adb` | `-c` flag: write to stdout, keep originals |
| REQ-079 | `crelz.adb` | `-k` flag: retain input files |
| REQ-080 | `crelz.adb` | `-f` flag: force overwrite; prompt/error without it |
| REQ-081 | `crelz.adb` | `-v` flag: verbose ratio to stderr |
| REQ-082 | `crelz.adb`, `Crab_ELZ` | `-t` flag: decompress + check integrity |
| REQ-083 | `crelz.adb` | `-q` flag: suppress warnings |
| REQ-084 | `crelz.adb` | `-r` flag: recursive directory traversal |
| REQ-085 | `crelz.adb` | `-S` flag: custom suffix |
| REQ-086 | `crelz.adb`, `Crab_ELZ` | `-1`..`-9` presets → `Set_Max_Codes` |
| REQ-087 | `crelz.adb`, `Crab_ELZ` | `--max-codes` flag → `Set_Max_Codes` |
| REQ-088 | `crelz.adb` | `-h`, `--help`, `--version` |
| REQ-089 | `crelz.adb` | Stdin/`-` handling |
| REQ-090 | `crelz.adb` | Exit codes 0–4 |
| REQ-091 | `crelz.adb` | `.ez` file-format header: magic `CREL` + version + original_size + max_codes + bitstream |
| REQ-092 | `crelz.adb` | Decompress suffix detection / magic-number verification |
| REQ-093 | `Crab_ELZ` | `Decompress(Max_Codes)` bounded-mode roundtrip via `De_Evict_One` |
| REQ-094 | `share/man/man1/crelz.1` | Static man page source |
| REQ-095 | `tests/src/crab_elz_crelz_tests.*` | AUnit tests for crelz roundtrip, format, CLI parsing |

---

## 7. Notes

### 7.0 Test Architecture

Unit testing uses the **AUnit** framework (Alire crate `aunit` v26.0.0).  The
tests reside in a **nested Alire crate** at `tests/` with its own `alire.toml`:

```toml
name = "crab_tests"
description = "Unit and integration tests for crab"
version = "0.1.0-dev"
[[depends-on]]
crab = { path = ".." }
aunit = "^26.0.0"
```

The test harness (`tests/src/crab_tests.adb`) registers AUnit test suites for
all algorithmic packages and runs them.  Test packages follow the naming
convention `Crab_Foo_Tests` with corresponding `.ads` and `.adb` files.

**Test coverage by package:**

| Package under test | Test package | Type |
|---|---|---|
| `Crab_Chunker` | `Crab_Chunker_Tests` | Unit |
| `Crab_Compression` | `Crab_Compression_Tests` | Unit (includes `Window_Size` test) |
| `Crab_Fold` | `Crab_Fold_Tests` | Unit |
| `Crab_Preprocess` | `Crab_Preprocess_Tests` | Unit |
| `Crab_Glob` | `Crab_Glob_Tests` | Unit |
| `Crab_ELZ` | `Crab_ELZ_Tests` | Unit |
| `Crab_Scorer` | `Crab_Scorer_Tests` | Unit |
| `Crab_TopK` | `Crab_TopK_Tests` | Unit (includes file-mode heap test) |
| `Crab_Scanner` | `Crab_Scanner_Tests` | Integration |
| `Crab_Zlib` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_LZ4` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_LZMA` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_Fnmatch` | (exercised via `Crab_Glob_Tests`) | Integration |
| `crelz.adb` | `Crab_ELZ_Crelz_Tests` | Unit (roundtrip, file format, CLI) |

**Build and run:**

```
cd tests/
alr build    # compiles crab_tests executable
alr run      # executes all suites, reports pass/fail
```

### 7.1 Ada Standard Library Dependencies

| Standard package | Used by |
|---|---|
| `Ada.Command_Line` | `crab.adb` — argument parsing |
| `Ada.Text_IO` | `crab.adb` — stderr; `Crab_TopK` — stdout |
| `Ada.Strings.Unbounded` | Multiple — dynamic string storage |
| `Ada.Containers.Indefinite_Vectors` | `Crab_Scanner`, `crab.adb` |
| `Ada.Containers.Indefinite_Hashed_Sets` | `Crab_Scanner` — cycle detection |
| `Ada.Containers.Generic_Array_Sort` | `Crab_Scanner` — entry sorting; `Crab_TopK` — score sorting |
| `Ada.Directories` | `Crab_Scanner` — directory traversal |
| `Ada.Streams.Stream_IO` | `crab.adb` — file I/O; `Crab_TopK` — stdout writing |
| `Ada.Streams` | `Crab_Buffers` — `Stream_Element` type for `Byte_Buffer` |
| `Ada.Finalization` | `Crab_Buffers` — `Limited_Controlled` base for automatic cleanup |
| `Interfaces.C` | `Crab_Zlib`, `Crab_LZ4`, `Crab_LZMA`, `Crab_Fnmatch` — C type definitions (bodies only) |
| `GNAT.OS_Lib` | `Crab_Scanner` — `Normalize_Pathname`; `Crab_Preprocess` — `Argument_List` type |
| `GNAT.Expect` | `Crab_Preprocess` — `Get_Command_Output` for shell pre-processing |
| `System.Address` | Binding packages — C buffer passing; Binding packages — C buffer passing (FFI overlays) |
| `Ada.Exceptions` | `crab.adb`, `Crab_Scanner` — exception messages |

### 7.2 Build Configuration

The GPR project file `crab.gpr` links against `-lz`, `-llz4`, and `-llzma`. ELZ is pure
Ada with no external library dependency.  The project lists both `crab.adb` and `crelz.adb` as
mains via `for Main use ("crab.adb", "crelz.adb")`; both executables
are built by `alr build` and land in `bin/`.

### 7.3 Key Design Decisions — Client Confirmed

| Decision | Rationale |
|---|---|
| Streaming per-file processing | Client: "more streaming manner ... each file in isolation" |
| Top-K bounded heap | Client: "top-k chunk with the lowest score" displaced; O(k) memory |
| No concatenation of files | Client: "do not want to concatenate the files together" |
| Tie-break by offset within file | Files processed deterministically; file ordering gives cross-file determinism |
| File mode — whole-file scoring | Client: compare query file against target files; one score per file |
| File mode output format | Client: "filename score" on one line, descending order |
| Window-size warning | Client: warn when file/chunk exceeds LZ77/LZMA sliding window |
| crelz standalone tool | Client: gzip-like ELZ compressor/decompressor using shared `Crab_ELZ` package |
| crelz file format | Client: `.ez` extension with `CREL`-magic header; 17-byte fixed header |
| crelz CLI flags | Client: match gzip interface (`-d`, `-c`, `-k`, `-f`, `-v`, `-t`, `-q`, `-r`, `-S`, `-1`..`-9`) |

### 7.4 Open for Future Builds

- Memory-map files for zero-copy I/O on large files
- Additional compression backends (bzip2, zstd, brotli)
- Unicode case folding (currently ASCII-only)
- Threaded file processing with merge of per-file Top-K heaps
- Output mode: JSON, CSV, or machine-parseable formats
- `--label` for stdin naming
- `-l` (files-with-results), `-c` (count), `-q` (quiet) flags
