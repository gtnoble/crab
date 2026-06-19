# Software Design Description — Crab

**Project:** Crab — Compression-based mutual-information grep
**Date:** 2026-06-18
**Version:** 1.1 — streaming architecture
**Component:** `crab` (sole component)

---

## 1. Scope

### 1.1 Component Identifier

`crab` — a CLI executable, decomposing into 11 Ada packages plus the main procedure,
that selects and outputs the *k* chunks of text having the greatest (or least)
compression-based mutual information with a user query. Processing is streaming:
files are read independently, chunks are scored on-the-fly, and only the top-*k*
(plus the current working chunk) are held in memory.

### 1.2 Document Overview

Section 3 records component-wide design decisions. Section 4 describes the
architectural decomposition. Section 5 provides detailed design for each software
unit. Section 6 traces requirements to implementing units.

---

## 2. Referenced Documents

| Document | Reference |
|---|---|
| Project Plan | `plan/project-plan.md` v1.0-draft |
| Requirements Spec | `requirements/requirements-spec.md` v1.0-draft |
| MIL-STD-498 DID DI-IPSC-81435 (SDD) | Checklist at `documents.md` Part 1 |

---

## 3. Component-Wide Design Decisions

### 3.1 Behavioral Design

`crab` executes as a streaming processor:

1. **Argument parsing.** Command-line arguments are parsed into a `Config` record.
2. **Query preparation.** If `-i`, the query is case-folded. The query is loaded
   as a compression dictionary into the Scorer's persistent stream object once at
   initialisation time. No separate compressed-size cache of the query is needed;
   the dictionary itself is used directly by the compressor during each chunk
   scoring call.
   arguments, or stdin as a single pseudo-file):
   a. Read the file's bytes into a buffer.
   b. If `-i`, produce a folded copy of the buffer for scoring; keep the original
      for output.
   d. For each chunk, pass its folded data to the Scorer to compute the MI‑approx
      score via dictionary-preloaded compression. Extract the corresponding
      original (unfolded) bytes from the original buffer for potential output.
      score. Extract the corresponding original (unfolded) bytes from the original
      buffer for potential output.
   e. Insert the `(score, file, per‑file offset, original chunk bytes)` tuple into
      the Top‑K accumulator. The accumulator is a bounded binary heap of size *k*
      (max‑heap for normal mode, min‑heap for inversion). If the heap is full and
      the new score beats the worst score in the heap, the worst is evicted and the
      new entry inserted.
4. **Output.** After all files are processed, extract the top‑*k* entries from the
   heap in sorted order (best first) and print headers followed by chunk bytes.

The tool is single-threaded. There is no interactive mode, no daemon mode, no
network communication.

### 3.2 Memory and Processing Allocation

| Concern | Strategy |
|---|---|
| **Input buffer** | One file at a time. Max memory = largest single file. No concatenated global buffer. |
| **Folded buffer** | When `-i`, a second buffer of equal size to the current file. Released after the file is processed. |
| **Chunk storage** | Only *k* + 1 chunks in memory: the current working chunk (whose data is a slice reference into the file buffer) and at most *k* stored in the heap. |
| **Compression buffers** | One persistent output buffer allocated once at `Scorer.Init` time: `Chunk_Buf` (size = `compressBound(chunk_size)`). Additionally, a persistent streaming compressor object (zlib `z_stream` or LZ4 stream) is allocated once, pre-loaded with the query as dictionary, and reused for every chunk compression call. No per-call allocation or deallocation occurs on the hot path. |
| **Query compression** | The query is loaded as a dictionary into the persistent stream object once; no separate compressed-size cache is needed. |
| **Query compression** | Compressed once; cached. |

### 3.3 Error and Exception Handling

| Condition | Mechanism | Exit code |
|---|---|---|
| Bad argument (invalid flag, missing value, out of range) | Print message to stderr, exit | 1 |
| File not found or unreadable (explicitly named) | Print message to stderr, exit | 2 |
| Permission denied during traversal (non-explicit) | Print warning to stderr, continue | 0 if any input read; 2 otherwise |
| Compression library error | `Compression_Error` exception → print message to stderr, exit | 3 |
| Empty input (no chunks from any file) | Print message to stderr, exit | 4 |

All exceptions not explicitly caught propagate to the main procedure's final
exception handler, which prints a generic error and exits with code 1. There is
no silent failure path.

### 3.4 Output Media and Formats

- **stdout:** Chunk output only — headers and raw chunk bytes (REQ-029, REQ-030).
  Must be left clean for piping.
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
| `Crab_Zlib` | Package (binding) | Thin Ada binding to libz streaming API: `deflateInit`, `deflateSetDictionary`, `deflate`, `deflateEnd`, `compressBound` |
| `Crab_LZ4` | Package (binding) | Thin Ada binding to liblz4 streaming dictionary API: `LZ4_createStream`, `LZ4_loadDict`, `LZ4_compress_fast_continue`, `LZ4_freeStream`, `LZ4_compressBound` |
| `Crab_Fnmatch` | Package (binding) | Thin Ada binding to libc `fnmatch()` for shell glob matching |
| `Crab_Compression` | Package (abstraction) | Uniform compression interface dispatching to DEFLATE/LZ4 backends |
| `Crab_Fold` | Package (utility) | ASCII case folding for `--ignore-case` |
| `Crab_Glob` | Package (utility) | Multi-pattern include/exclude matching using `fnmatch` |
| `Crab_Scorer` | Package (algorithm) | Stateful MI‑approx scorer: pre-loads query as dictionary into persistent streaming compressor; scores individual chunks via dictionary-preloaded compression |
| `Crab_TopK` | Package (algorithm) | Bounded binary heap maintaining the top-*k* (or bottom-*k*) scored chunks |

### 4.2 Static Relationships — Dependency Graph

```
```
crab.adb
 ├── Crab_Compression ──────┬── Crab_Zlib
 │                           └── Crab_LZ4
 ├── Crab_Fold
 ├── Crab_Scanner ──────────┬── Crab_Glob ─── Crab_Fnmatch
 │                           └── GNAT.OS_Lib
 ├── Crab_Chunker
 ├── Crab_Scorer ───────────┬── Crab_Compression
 │                           ├── Crab_Zlib
 │                           └── Crab_LZ4
 └── Crab_TopK
```

- `crab.adb` depends on **all** application packages (it is the sole streaming orchestrator).
- `Crab_Compression` depends on `Crab_Zlib` and `Crab_LZ4` (the backends).
- `Crab_Scorer` depends on `Crab_Compression` (buffer sizing, level defaults)
  and directly on `Crab_Zlib` / `Crab_LZ4` (stream object types and Compress_Stream
  procedures).
- `Crab_Scanner` depends on `Crab_Glob`, which depends on `Crab_Fnmatch`.
- `Crab_Chunker`, `Crab_Fold`, and `Crab_TopK` have no internal dependencies
  (pure computation packages).
- No circular dependencies. The dependency graph is a DAG rooted at `crab.adb`.
 ├── Crab_Chunker
 ├── Crab_Scorer ─────────── Crab_Compression
 └── Crab_TopK
```

- `crab.adb` depends on **all** application packages (it is the sole streaming orchestrator).
- `Crab_Compression` depends on `Crab_Zlib` and `Crab_LZ4` (the backends).
- `Crab_Scanner` depends on `Crab_Glob`, which depends on `Crab_Fnmatch`.
- `Crab_Scorer` depends on `Crab_Compression`.
- `Crab_Chunker`, `Crab_Fold`, and `Crab_TopK` have no internal dependencies
  (pure computation packages).
- No circular dependencies. The dependency graph is a DAG rooted at `crab.adb`.

### 4.3 Dynamic Relationships — Execution Sequence

```
crab.adb
  │
  ├─[1] Parse_Args()                       → Config record
  ├─[2] Handle --help / --version          → exit 0 (if applicable)
  ├─[3] Validate query, chunk-size (or chunk-lines), etc    → exit 1 (if invalid)
  │
  ├─[4] Prepare query:
  ├─[4] Prepare query:
  │       Scoring_Query := (if -i then Fold(Query) else Query)
  │       Scorer.Init (Scoring_Query, Chunk_Size, Algo, Level)
  │            → pre-loads Query as dictionary into persistent stream
  │
  │
  ├─[6] Determine file list:
  │       IF -r or dirs present:
  │          Files := Scanner.Scan(...)
  │       ELSIF explicit files:
  │          Files := explicit list
  │       ELSE:
  │          Read stdin → process as single pseudo-file "(stdin)"
  │
  ├─[7] FOR EACH file IN Files:
  │       ┌─[7a] Read file bytes       → File_Buf
  │       ├─[7b] IF -i:
  │       │        Scoring_Buf := Fold (File_Buf)
  │       │     ELSE:
  │       │        Scoring_Buf := File_Buf
  │       ├─[7c] Chunker.Start (Scoring_Buf, Chunk_Size / Chunk_Lines, Overlap)
  │       ├─[7d] WHILE Chunker.Has_Next:
  │       │        (Chunk_Data, Offset) := Chunker.Next
  │       │        Score := Scorer.Score (Chunk_Data)
  │       │        Orig_Chunk := File_Buf (Offset .. Offset + Length(Chunk_Data) - 1)
  │       │        TopK.Insert (Score  => Score,
  │       │                     Offset => Offset,
  │       │                     File   => Current_File_Path,
  │       │                     Data   => Orig_Chunk)
  │       └─ (File_Buf released on next iteration or exit)
  │
  ├─[8] IF TopK.Is_Empty → exit 4 (no chunks from any file)
  │
  └─[9] TopK.Print (to stdout)
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
| `Crab_Scorer.State` | `Crab_Scorer` | `crab.adb` |
| `Crab_TopK.Heap` | `Crab_TopK` | `crab.adb` |

All cross-package types are defined in the producer package's specification. The
binding packages expose only subprograms — no types cross the binding boundary
into application code.

### 4.5 Concept of Execution

The component fulfills its requirements through a **streaming architecture**: each
file is read, chunked, scored, and the best chunks retained — all in a single pass
per file. Only the top-*k* chunks accumulate across files. This maps to the
following processing model:

1. **Config stage** (arg parsing): produces configuration.
2. **Query-init stage**: compresses the query once (cached in Scorer).
3. **File loop** (orchestrated by `crab.adb`):
   - **Read stage**: one file into a buffer.
   - **Fold stage**: if `-i`, produce folded copy for scoring.
   - **Chunk stage**: streaming iterator yields one chunk at a time.
   - **Score stage**: compute MI‑approx for the current chunk.
   - **Accumulate stage**: bounded heap insert-or-discard.
4. **Output stage**: drain heap in sorted order, print.

Each non-orchestration stage can be tested in isolation with fixed inputs.
The heap-bounded nature means memory is O(largest_file + k × chunk_size), not
O(total_input + all_chunks).

### 4.6 Design Decisions Affecting Multiple Units

| Decision | Affected units | Rationale |
|---|---|---|
| **Per-file processing, no concatenation** | crab.adb, Crab_Chunker, Crab_Scorer, Crab_TopK | Avoids loading all files into memory simultaneously. Each file is independent; the Top‑K accumulator crosses file boundaries. |
| **Bounded binary heap for top-k** | Crab_TopK | O(log *k*) insertion vs. O(*N* log *N*) full sort. Only *k* chunk objects stored, not all *N*. |
| **Chunker as streaming iterator** | Crab_Chunker, crab.adb | No intermediate vector of all chunks. Chunk data is a substring slice of the file buffer — zero-copy. |
| **Line-based chunking mode** | Crab_Chunker, crab.adb | `--chunk-lines` (`-L`) partitions input into chunks of N consecutive lines; mutually exclusive with `--chunk-size`. The chunker dispatches to the appropriate internal iterator based on the mode selected. Overlap semantics apply to lines as they do to bytes (REQ-061). |
| **Scorer stateful with cached query CS** | Crab_Scorer | Query compressed once across all chunks. `Scorer.Init` caches; `Scorer.Score` only compresses chunk + joint. |
| **Scorer stateful with dictionary-preloaded stream** | Crab_Scorer | Query loaded as dictionary into persistent streaming compressor once. `Scorer.Init` creates the stream object; `Scorer.Score` compresses each chunk with the dictionary pre-loaded versus with an empty dictionary for the baseline. |
| **`System.Address` for C buffer passing** | Crab_Zlib, Crab_LZ4, Crab_Fnmatch | Avoids intermediate copies when passing String data to C functions. Ada `String` is a contiguous byte array on GNAT/x86_64 — its `'Address` is a valid `const char*`. |
| **GNAT.OS_Lib for canonical paths** | Crab_Scanner | `Normalize_Pathname` with `Resolve_Links => True` resolves symlinks and provides canonical paths for cycle detection without an additional C binding. |
| **`Ada.Directories` for file system ops** | Crab_Scanner | Portable, already in GNAT runtime. Follows symlinks by default (matches REQ-044). |
| **`String` slice for chunk data** | Crab_Chunker, crab.adb | `Next` returns a slice of the scoring buffer — no allocation. The caller (crab.adb) copies the corresponding original-buffer slice into the Top‑K heap when the chunk succeeds. |
| **Persistent compression buffers and stream** | Crab_Zlib, Crab_LZ4, Crab_Compression, Crab_Scorer | One persistent output buffer (`Chunk_Buf`) and one persistent streaming compressor object allocated once in `Scorer.Init` and reused for every chunk compression across all files. Eliminates ~N allocations on the scoring hot path and removes the need for the Q∥C concatenation. |
### 4.7 Unit-to-Requirement Traceability

### 4.7 Unit-to-Requirement Traceability

| Unit | Requirements covered |
|---|---|
| `crab.adb` | REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-008, REQ-033, REQ-034 |
| `Crab_Zlib` | REQ-016 |
| `Crab_LZ4` | REQ-017 |
| `Crab_Fnmatch` | REQ-051 (via `fnmatch`), REQ-056 |
| `Crab_Compression` | REQ-015, REQ-018, REQ-019, REQ-020 |
| `Crab_Fold` | REQ-047 |
| `Crab_Glob` | REQ-049, REQ-050, REQ-051, REQ-052 |
| `Crab_Scanner` | REQ-041, REQ-042, REQ-043, REQ-044, REQ-045, REQ-046, REQ-053, REQ-054 |
| `Crab_Chunker` | REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-059, REQ-060, REQ-061 |
| `Crab_Scorer` | REQ-021, REQ-022, REQ-023, REQ-024, REQ-025 |
| `Crab_TopK` | REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-055 |
| `Crab_TopK` | REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-055 |

---

## 5. Detailed Design

### 5.1 `crab.adb` — Main Procedure

| Attribute | Value |
|---|---|
| **Identifier** | `crab` |
| **Type** | Main procedure (executable entry point) |
| **Purpose** | Parse arguments, orchestrate the streaming pipeline, handle errors, control exit codes. |

**Interfaces:**

```
Input:  Command-line arguments (via Ada.Command_Line)
        Standard input stream
        File system (reads input files)
Output: Standard output stream (chunk output via Crab_TopK.Print)
        Standard error stream (diagnostics)
        Exit code (0–4)
```

**Data Elements (local to `crab.adb`):**

| Name | Type | Role |
|---|---|---|
| `Config` | Record | All parsed argument values |
| `Scoring_Query` | `String` | Query string (folded if `-i`) |
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
   Chunk_Size    : Natural := 0;   -- 0 = not set; must be provided
   Chunk_Lines   : Natural := 0;   -- 0 = not set; mutually exclusive with Chunk_Size
   Overlap       : Natural := 0;
   Top_K         : Positive := 10;
   Recursive     : Boolean := False;
   Ignore_Case   : Boolean := False;
   Invert        : Boolean := False;
   Max_Depth     : Natural := Natural'Last;  -- sentinel for unlimited
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
   --   -a, --algorithm  → next arg: "deflate" | "lz4"
   --   -l, --level      → next arg: integer
   --   -s, --chunk-size → next arg: positive integer
   --   -L, --chunk-lines → next arg: positive integer  (mutually exclusive with -s)
   --   -o, --overlap    → next arg: 0–99 integer
   --   -k, --top        → next arg: positive integer
   --   -r, --recursive  → set flag
   --   -i, --ignore-case→ set flag
   --   -v, --invert     → set flag
   --   --include        → next arg: add to Cfg.Include_Pats
   --   --exclude        → next arg: add to Cfg.Exclude_Pats
   --   --max-depth      → next arg: non-negative integer
   -- Validates: query non-empty; exactly one of --chunk-size or --chunk-lines set; level in range per algo.
end Parse_Args;
```

**Logic — Main Streaming Orchestration:**

```ada
begin
   Parse_Args (Cfg);
   if Cfg.Show_Help    then Print_Usage; return;    end if;
   if Cfg.Show_Version then Put_Line (Crab_Config.Crate_Version); return; end if;

   -- Prepare query
   Scoring_Query : constant String :=
     (if Cfg.Ignore_Case
      then Crab_Fold.Fold (To_String (Cfg.Query))
      else To_String (Cfg.Query));
   Scorer : Crab_Scorer.State :=
     Crab_Scorer.Init (Scoring_Query, Cfg.Chunk_Size, Cfg.Algorithm, Cfg.Level);

   -- Initialize top-k heap
   Top_Heap : Crab_TopK.Heap :=
     Crab_TopK.Create (K => Cfg.Top_K, Invert => Cfg.Invert);

   -- Determine file list
   Has_Dirs : constant Boolean :=
     (for some P of Cfg.Paths => Is_Directory (P));

   if Cfg.Recursive or Has_Dirs then
      if not Cfg.Recursive and Has_Dirs then
         Put_Line (Stderr, "crab: directories require -r");
         Exit_Code (1); return;
      end if;
      Files := Scanner.Scan (Root_Paths   => Cfg.Paths,
                              Recursive    => True,
                              Max_Depth    => Cfg.Max_Depth,
                              Include_Pats => Cfg.Include_Pats,
                              Exclude_Pats => Cfg.Exclude_Pats,
                              Ignore_Case  => Cfg.Ignore_Case,
                              Warnings     => Scanner_Warnings);
      Print_Scanner_Warnings (Scanner_Warnings);
      if Is_Empty (Files) then
         Put_Line (Stderr, "crab: no files found or readable");
         Exit_Code (2); return;
      end if;
   elsif not Cfg.Paths.Is_Empty then
      Files := Build_Explicit_File_List (Cfg.Paths);
   end if;

   Has_Stdin : constant Boolean := Is_Empty (Files);

   -- Process each file
   if Has_Stdin then
      Process_One_File ("(stdin)", Read_Stdin, Top_Heap, Scorer, Cfg);
   else
      for F of Files loop
         begin
            Process_One_File (F.Path, Read_File (F.Path), Top_Heap, Scorer, Cfg);
         exception
            when E : Ada.Text_IO.Name_Error =>
               Put_Line (Stderr, "crab: " & F.Path & ": " & Exception_Message (E));
               Exit_Code (2); return;
         end;
      end loop;
   end if;

   -- Output
   if Crab_TopK.Is_Empty (Top_Heap) then
      Put_Line (Stderr, "crab: empty input — no chunks");
      Exit_Code (4); return;
   end if;
   Crab_TopK.Print (Top_Heap);
exception
   when Crab_Compression.Compression_Error =>
      Put_Line (Stderr, "crab: compression error");
      Exit_Code (3);
   when E : others =>
      Put_Line (Stderr, "crab: " & Exception_Message (E));
      Exit_Code (1);
end Crab;
```

**Logic — `Process_One_File` helper:**

```
procedure Process_One_File
  (Path   : String;
   Data   : String;
   Heap   : in out Crab_TopK.Heap;
   Scorer : in out Crab_Scorer.State;
   Cfg    : Config)
is
   Scoring_Buf : constant String :=
     (if Cfg.Ignore_Case then Crab_Fold.Fold (Data) else Data);
   Chunker     : Crab_Chunker.State :=
     (if Cfg.Chunk_Lines > 0 then Crab_Chunker.Start_Lines (Scoring_Buf, Cfg.Chunk_Lines, Cfg.Overlap) else Crab_Chunker.Start (Scoring_Buf, Cfg.Chunk_Size, Cfg.Overlap));
begin
   while Crab_Chunker.Has_Next (Chunker) loop
      declare
         Chunk_Slice : constant String := Crab_Chunker.Next (Chunker);
         --  Chunk_Slice is a substring of Scoring_Buf; no copy.
         Offset      : constant Natural :=
           Chunk_Slice'First - Scoring_Buf'First;
         Score       : constant Integer :=
           Crab_Scorer.Score (Scorer, Chunk_Slice);
         Orig_Chunk  : constant String :=
           Data (Data'First + Offset ..
                 Data'First + Offset + Chunk_Slice'Length - 1);
      begin
         Crab_TopK.Insert
           (Heap     => Heap,
            Score    => Score,
            File_Path => Path,
            Offset   => Offset,
            Data     => Orig_Chunk);
      end;
   end loop;
end Process_One_File;
```

**Constraints:** `crab.adb` is the only unit that calls `Ada.Command_Line` or
### 5.2 `Crab_Zlib` — zlib Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Zlib` |
| **Type** | Package (C binding) |
| **Purpose** | Provide streaming compression with dictionary pre-loading backed by libz. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Zlib_Error` | Exception | Raised when any zlib function returns an error status |
| `Compress_Bound (Source_Len)` | Function → Natural | Maximum possible compressed size (for buffer pre-allocation) |
| `Init_Stream (Level)` | Function → `ZStream` | Initialise a new `z_stream` in deflate mode with the given compression level |
| `Set_Dict (Stream, Dict)` | Procedure | Load `Dict` into the stream's compression dictionary (`deflateSetDictionary`) |
| `Compress_Stream (Stream, Source, Dest)` | Procedure → out `Dest_Len: Natural` | Compress `Source` using the stream's current state (including dictionary). Calls `deflate` with `Z_FINISH`. Dest must be at least `Compress_Bound(Source'Length)` bytes. Resets stream state afterward via `deflateReset`. |
| `Free_Stream (Stream)` | Procedure | Deallocate the z_stream (`deflateEnd`) |
| `Compress_Bare (Source, Level, Dict)` | Function → Natural | Convenience: init stream, set dict, compress, free, return compressed size. Used for tests and one-shot operations. |

**`ZStream` type (private):**

```ada
type ZStream is limited private;
--  Wraps a z_stream record with heap-allocated internal state.
--  Limited to prevent copying; managed via Init_Stream / Free_Stream.
```

**`Init_Stream`:**

```
function Init_Stream (Level : Integer) return ZStream is
   S : aliased z_stream;
   Result : C.int;
begin
   --  Zero-initialise the z_stream struct
   S.zalloc := Null_Alloc; S.zfree := Null_Free; S.opaque := Null;
   Result := c_deflateInit2
     (S'Access, C.int (Level),
      Z_DEFLATED, MAX_WBITS, MAX_MEM_LEVEL,
      Z_DEFAULT_STRATEGY);
   if Result /= Z_OK then raise Zlib_Error; end if;
   return (Stream => new aliased z_stream'(S));
end Init_Stream;
```

**`Set_Dict`:**

```
procedure Set_Dict (S : in out ZStream; Dict : String) is
   Result : C.int;
begin
   Result := c_deflateSetDictionary
     (S.Stream, Dict'Address, C.unsigned_int (Dict'Length));
   if Result /= Z_OK then raise Zlib_Error; end if;
end Set_Dict;
```

**`Compress_Stream`:**

```
procedure Compress_Stream
  (S        : in out ZStream;
   Source   : String;
   Dest     : in out Byte_Array;
   Dest_Len : out Natural)
is
   Result : C.int;
begin
   --  Set up input
   S.Stream.next_in   := Source'Address;
   S.Stream.avail_in  := C.unsigned_int (Source'Length);
   S.Stream.next_out  := Dest'Address;
   S.Stream.avail_out := C.unsigned_int (Dest'Length);

   Result := c_deflate (S.Stream, Z_FINISH);
   if Result /= Z_STREAM_END then raise Zlib_Error; end if;

   Dest_Len := Natural (S.Stream.total_out);

   --  Reset stream state but keep dictionary
   Result := c_deflateReset (S.Stream);
   if Result /= Z_OK then raise Zlib_Error; end if;
end Compress_Stream;
```

**`Free_Stream`:**

```
procedure Free_Stream (S : in out ZStream) is
   Ignore : C.int;
begin
   Ignore := c_deflateEnd (S.Stream);
   Free (S.Stream);
end Free_Stream;
```

**`Compress_Bare` (convenience wrapper for tests/one-shot):**

```
function Compress_Bare
  (Source : String;
   Level  : Integer;
   Dict   : String) return Natural
is
   S     : ZStream := Init_Stream (Level);
   Buf   : Byte_Array (1 .. Compress_Bound (Source'Length));
   Dlen  : Natural;
begin
   Set_Dict (S, Dict);
   Compress_Stream (S, Source, Buf, Dlen);
   Free_Stream (S);
   return Dlen;
end Compress_Bare;
```

Where `c_deflateInit2`, `c_deflateSetDictionary`, `c_deflate`, `c_deflateReset`,
and `c_deflateEnd` are imported from libz via `External_Name`.

**Constraints:**
- The stream is created once in `Scorer.Init` with the query as dictionary,
  and reused via `Compress_Stream` / `deflateReset` for every chunk.
- `deflateReset` preserves the dictionary, so `Set_Dict` is only called once.
- The dictionary is limited to 32 KB (zlib's sliding window size). If the query
  exceeds this, only the last 32 KB are used — a theoretical limitation unlikely
  to matter for real-world queries.

### 5.3 `Crab_LZ4` — LZ4 Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_LZ4` |
| **Type** | Package (C binding) |
| **Purpose** | Provide streaming compression with dictionary pre-loading backed by liblz4. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `LZ4_Error` | Exception | Raised when any LZ4 function returns an error status |
| `Compress_Bound (Input_Size)` | Function → Natural | Maximum possible compressed size |
| `Init_Stream` | Function → `LZ4_Stream` | Create a new LZ4 stream (`LZ4_createStream`) |
| `Load_Dict (Stream, Dict)` | Procedure | Load dictionary into the stream (`LZ4_loadDict`) |
| `Compress_Stream (Stream, Source, Dest, Acceleration)` | Procedure → out `Dest_Len: Natural` | Compress `Source` using stream state with dictionary pre-loaded (`LZ4_compress_fast_continue`). Dest must be at least `Compress_Bound(Source'Length)` bytes. Resets stream afterward via `LZ4_resetStream_fast`. |
| `Free_Stream (Stream)` | Procedure | Deallocate the stream (`LZ4_freeStream`) |
| `Compress_Bare (Source, Acceleration, Dict)` | Function → Natural | Convenience: create stream, load dict, compress, free. |

**`LZ4_Stream` type (private):**

```ada
type LZ4_Stream is limited private;
--  Wraps a heap-allocated LZ4 stream handle.
--  Limited to prevent copying; managed via Init_Stream / Free_Stream.
```

**`Init_Stream`:**

```
function Init_Stream return LZ4_Stream is
   Handle : constant System.Address := LZ4_createStream;
begin
   if Handle = System.Null_Address then
      raise LZ4_Error;
   end if;
   return (Handle => Handle);
end Init_Stream;
```

**`Load_Dict`:**

```
procedure Load_Dict (S : in out LZ4_Stream; Dict : String) is
   Bytes : C.int;
begin
   Bytes := LZ4_loadDict
     (S.Handle, Dict'Address, C.int (Dict'Length));
   if Bytes < C.int (Dict'Length) then
      raise LZ4_Error;
   end if;
end Load_Dict;
```

**`Compress_Stream`:**

```
procedure Compress_Stream
  (S            : in out LZ4_Stream;
   Source       : String;
   Dest         : in out Byte_Array;
   Acceleration : Integer;
   Dest_Len     : out Natural)
is
   Result : C.int;
begin
   Result := LZ4_compress_fast_continue
     (S.Handle, Source'Address, Dest'Address,
      C.int (Source'Length), C.int (Dest'Length),
      C.int (Acceleration));
   if Result <= 0 then
      raise LZ4_Error;
   end if;
   Dest_Len := Natural (Result);

   --  Reset stream state to reuse the dictionary
   LZ4_resetStream_fast (S.Handle);
end Compress_Stream;
```

**`Free_Stream`:**

```
procedure Free_Stream (S : in out LZ4_Stream) is
   Result : C.int;
begin
   Result := LZ4_freeStream (S.Handle);
   if Result /= 0 then
      raise LZ4_Error;
   end if;
end Free_Stream;
```

**`Compress_Bare` (convenience):**

```
function Compress_Bare
  (Source       : String;
   Acceleration : Integer;
   Dict         : String) return Natural
is
   S    : LZ4_Stream := Init_Stream;
   Buf  : Byte_Array (1 .. Compress_Bound (Source'Length));
   Dlen : Natural;
begin
   Load_Dict (S, Dict);
   Compress_Stream (S, Source, Buf, Acceleration, Dlen);
   Free_Stream (S);
   return Dlen;
end Compress_Bare;
```

Where `LZ4_createStream`, `LZ4_loadDict`, `LZ4_compress_fast_continue`,
`LZ4_resetStream_fast`, and `LZ4_freeStream` are imported from liblz4.

**Constraints:**
- The stream is created once in `Scorer.Init`, loaded with the query as
  dictionary, and reused via `Compress_Stream` / `LZ4_resetStream_fast`.
- `LZ4_resetStream_fast` preserves the dictionary, so `Load_Dict` is only
  called once.
- The LZ4 dictionary is limited to 64 KB. If the query exceeds this, only the
  last 64 KB are used.

### 5.4 `Crab_Fnmatch` — POSIX fnmatch Binding

*(Unchanged from v1.0 design.)*

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Fnmatch` |
| **Type** | Package (C binding) |
| **Purpose** | Provide `Match` subprogram backed by libc `fnmatch()`. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `FNM_NOMATCH` | Constant | Returned by `fnmatch` on non-match (= 1) |
| `FNM_CASEFOLD` | Constant | Flag for case-insensitive matching (= 16 on glibc) |
| `Match (Pattern, String, Flags)` | Function → Boolean | True if `String` matches `Pattern` |

---

### 5.5 `Crab_Compression` — Compression Abstraction

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Compression` |
| **Type** | Package (abstraction) |
| **Purpose** | Provide a uniform compression interface dispatching to DEFLATE or LZ4 backends. Includes dictionary-aware streaming, bare compression, and buffer sizing. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Algorithm` | Enumeration | `(Deflate, LZ4)` |
| `Compression_Error` | Exception | Propagated from backend errors |
| `Compress_Bound (Algo, Source_Len)` | Function → Natural | Upper bound for buffer pre-allocation |
| `Compress_Bare (Algo, Source, Level, Dict)` | Function → Natural | One-shot: init stream, set dict, compress, free. Returns compressed size. |
| `Level_Default (Algo)` | Function → Integer | Default compression level |
| `Level_Min (Algo)` | Function → Integer | Minimum valid level |
| `Level_Max (Algo)` | Function → Integer | Maximum valid level |

**`Compress_Bare` dispatch:**

```
function Compress_Bare
  (Algo   : Algorithm;
   Source : String;
   Level  : Integer;
   Dict   : String) return Natural
is
begin
   case Algo is
      when Deflate =>
         return Crab_Zlib.Compress_Bare (Source, Level, Dict);
      when LZ4 =>
         return Crab_LZ4.Compress_Bare (Source, Level, Dict);
   end case;
end Compress_Bare;
```

**`Compress_Bound` dispatch:**

```
function Compress_Bound
  (Algo : Algorithm; Source_Len : Natural) return Natural
is
begin
   case Algo is
      when Deflate =>
         return Crab_Zlib.Compress_Bound (Source_Len);
      when LZ4 =>
         return Crab_LZ4.Compress_Bound (Source_Len);
   end case;
end Compress_Bound;
```

**Level defaults:**

| Algorithm | Default | Min | Max |
|---|---|---|---|
| Deflate | 6 | −1 | 9 |
| LZ4 | 1 | 1 | 65537 |

**[Rationale]** The streaming objects (`Crab_Zlib.ZStream`, `Crab_LZ4.LZ4_Stream`)
are created, managed, and owned by `Crab_Scorer` directly — `Crab_Compression` does
not own them. `Compress_Into` is removed; the scorer calls backend `Compress_Stream`
directly (via the backend packages, which `Crab_Scorer` depends on). The abstraction
layer provides buffer sizing and bare compression for tests.

### 5.6 `Crab_Scorer` — Stateful MI Scorer

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Scorer` |
| **Type** | Package (algorithm) |
| **Purpose** | Pre-load the query as a compression dictionary; hold persistent stream objects for reuse across all chunk scoring calls; score individual chunks via dictionary-preloaded vs empty-dictionary compression. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `State` | Private type | Cached scorer state including persistent streams and buffer |
| `Init (Query, Chunk_Size, Algo, Level)` | Function → `State` | Create persistent stream objects; load Query as dictionary into one stream; pre-allocate `Chunk_Buf` |
| `Score (S, Chunk)` | Function → Integer | MI‑approx score for one chunk using pre-loaded streams |

**Data Elements (in State):**

| Name | Type | Role |
|---|---|---|
| `Algo` | `Crab_Compression.Algorithm` | Compression backend |
| `Level` | `Integer` | Compression level |
| `Dict_Stream` | `ZStream or LZ4_Stream` | Persistent stream pre-loaded with Query as dictionary |
| `Bare_Stream` | `ZStream or LZ4_Stream` | Persistent stream with empty dictionary for baseline |
| `Chunk_Buf` | `Byte_Array_Access` | Persistent buffer for chunk compression; size = `Compress_Bound(Chunk_Size)` |

**`Init` — create streams, load dictionary, allocate buffer:**

```
function Init
  (Query      : String;
   Chunk_Size : Positive;
   Algo       : Crab_Compression.Algorithm;
   Level      : Integer) return State
is
   Dict_S : Dict_Stream_Holder := Init_Dict_Stream (Algo, Level, Query);
   Bare_S : Bare_Stream_Holder := Init_Dict_Stream (Algo, Level, "");
begin
   return (Algo       => Algo,
           Level      => Level,
           Dict_Stream => Dict_S,
           Bare_Stream => Bare_S,
           Chunk_Buf  => new Byte_Array
             (1 .. Crab_Compression.Compress_Bound (Algo, Chunk_Size)));
end Init;
```

**`Score` — reuse persistent streams (hot path, zero allocation):**

```
function Score (S : State; Chunk : String) return Integer is
   Dict_CS : Natural;
   Bare_CS : Natural;
begin
   --  Compress chunk with empty-dictionary stream → baseline
   Compress_Into_Stream (S.Algo, S.Bare_Stream,
     Chunk, S.Level, S.Chunk_Buf.all, Bare_CS);

   --  Compress chunk with query-dictionary stream → conditional
   Compress_Into_Stream (S.Algo, S.Dict_Stream,
     Chunk, S.Level, S.Chunk_Buf.all, Dict_CS);

   return Integer (Bare_CS) - Integer (Dict_CS);
end Score;
```

**Constraints:**

- Query text is stored only as a dictionary inside `Dict_Stream` — no separate
  `Unbounded_String` or `Query_CS` cache is needed. This removes the
  concatenation allocation that was a known cost in the previous design.
- Both `Dict_Stream` and `Bare_Stream` use the same streaming API and format, so
  any per-format overhead (zlib headers, Adler-32, etc.) is present in both
  measurements and cancels out in the subtraction.
- `deflateReset` / `LZ4_resetStream_fast` preserve the dictionaries, so
  `Set_Dict` / `Load_Dict` are only called once during `Init`.
- Scores are signed `Integer` (REQ-025). Scores are typically non-negative
  for similar Q/C pairs, but can be negative if the dictionary misleads the
  compressor's hash chains — this is accepted and clamped to zero at the
  scorer's discretion per REQ-025.

**[Rationale]** The empty-dictionary baseline ensures that both measurements use
identical format overhead. The two persistent streams eliminate all per-call
allocation. The Q∥C concatenation is entirely removed from the hot path. The
formula |compress(C)| − |compress(C|dict=Q)| is a direct approximation of
I(Q;C) = K(C) − K(C|Q), replacing the previous symmetric joint-compression
heuristic with an asymmetric conditional-compression estimate.

### 5.7 `Crab_Fold` — Case Folding

*(Unchanged from v1.0 design.)*

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Fold` |
| **Type** | Package (utility) |
| **Purpose** | Map ASCII uppercase letters (A–Z) to lowercase (a–z). |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Fold (S)` | Function → String | Returns case-folded copy of `S` |

**Logic:**

```
function Fold (S : String) return String is
   Result : String (1 .. S'Length);
begin
   for I in S'Range loop
      declare
         C : constant Character := S (I);
      begin
         if C in 'A' .. 'Z' then
            Result (I - S'First + 1) :=
              Character'Val (Character'Pos (C) + 32);
         else
            Result (I - S'First + 1) := C;
         end if;
      end;
   end loop;
   return Result;
end Fold;
```

**Constraints:** ASCII only (Unicode case folding is out of scope per REQ-047).
Non-ASCII bytes (values ≥ 128) pass through unchanged.

---

### 5.8 `Crab_Glob` — Glob Pattern Matching

*(Unchanged from v1.0 design.)*

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Glob` |
| **Type** | Package (utility) |
| **Purpose** | Wrap `fnmatch` for multi-pattern include/exclude matching against filenames. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Pattern_List` | Tagged private type | Ordered list of glob patterns |
| `Empty_Pattern_List` | Constant | An empty list |
| `Add (List, Pattern)` | Procedure | Append a pattern |
| `Matches_Any (List, Name, Ignore_Case)` | Function → Boolean | True if `Name` matches any pattern |
| `Is_Empty (List)` | Function → Boolean | True if no patterns |

**Include/Exclude logic (used by Scanner):**

```
function Should_Process
  (Name         : String;
   Include_Pats : Pattern_List;
   Exclude_Pats : Pattern_List;
   Ignore_Case  : Boolean) return Boolean
is
begin
   -- Excludes override
   if not Is_Empty (Exclude_Pats)
     and then Matches_Any (Exclude_Pats, Name, Ignore_Case)
   then
      return False;
   end if;
   -- Includes
   if Is_Empty (Include_Pats) then
      return True;
   else
      return Matches_Any (Include_Pats, Name, Ignore_Case);
   end if;
end Should_Process;
```

---

### 5.9 `Crab_Scanner` — Directory Traversal

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Scanner` |
| **Type** | Package (I/O) |
| **Purpose** | Walk directory trees, filter by globs and depth, collect file-entry list. |

*This unit is substantially unchanged from v1.0. It produces a `File_Lists.Vector`
of `(Path, Byte_Size)` entries consumed by `crab.adb`. The traversal logic
(depth-first, sorted entries, symlink-cycle detection via canonical paths,
permission-error resilience) is identical. See v1.0 design for full pseudocode.*

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `File_Entry` | Record | `(Path : Unbounded_String; Byte_Size : File_Size)` |
| `File_Lists` | Vector package | `Indefinite_Vectors` of `File_Entry` |
| `Scan (...)` | Function → `File_Lists.Vector` | Traverse and return sorted file list |

**Scan parameters:**

```
function Scan
  (Root_Paths     : String_Vector;
   Recursive      : Boolean;
   Max_Depth      : Natural;
   Include_Pats   : Crab_Glob.Pattern_List;
   Exclude_Pats   : Crab_Glob.Pattern_List;
   Ignore_Case    : Boolean;
   Warnings       : out String_Vector) return File_Lists.Vector;
```

**Note for implementation:** The `Valid_Symlinks` and `Dereference` parameters of
`Ada.Directories` search operations are not set, so symlinks are followed by
default (per REQ-044). `GNAT.OS_Lib.Normalize_Pathname` with `Resolve_Links =>
True` provides canonical paths for cycle detection.

---

### 5.10 `Crab_Chunker` — Streaming Chunk Iterator

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Chunker` |
| **Type** | Package (algorithm) |
| **Purpose** | Provide a streaming iterator over fixed-size overlapping chunks of a byte buffer or line count. In byte mode (`--chunk-size`), chunks are *S* consecutive bytes. In line mode (`--chunk-lines`), chunks are *N* consecutive lines (delimited by newline, `\n`). No intermediate vector — one chunk at a time. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `State` | Private type | Iterator state for byte mode |
| `Line_State` | Private type | Iterator state for line mode |
| `Start (Buf, Size, Overlap)` | Function → `State` | Initialise byte-mode iterator over `Buf` |
| `Start_Lines (Buf, Line_Count, Overlap)` | Function → `Line_State` | Initialise line-mode iterator over `Buf`; pre-computes line-start offsets |
| `Has_Next (S)` | Function → Boolean | True if more chunks remain (applies to both `State` and `Line_State`) |
| `Next (S)` | Function (in out) → String | Advance; return next chunk as a slice of the buffer (applies to both state types via overloading or a common interface) |
| `Start_Line (S)` | Function → Natural | Return the 0‑based line index of the current chunk's first line in the buffer (line‑mode only) |

**Data Elements (byte-mode `State`):**

| Name | Type | Role |
|---|---|---|
| `Buf` | `Not null access constant String` | Reference to the input buffer (no copy) |
| `Size` | `Positive` | Chunk size in bytes |
| `Step` | `Natural` | Bytes to advance per chunk |
| `Cursor` | `Natural` | Current start position in `Buf` |

**Data Elements (line-mode `Line_State`):**

| Name | Type | Role |
|---|---|---|
| `Buf` | `Not null access constant String` | Reference to the input buffer |
| `Line_Count` | `Positive` | Lines per chunk |
| `Step` | `Natural` | Lines to advance per chunk |
| `Line_Starts` | `Line_Array_Access` | Pre-computed byte offsets of each line start (index 1..Num_Lines) |
| `Cursor` | `Natural` | Current line index into `Line_Starts` |

`Line_Array_Access` is an access type to `Ada.Containers.Vectors (Positive, Natural)` — the vector stores the byte position of the first character of each line within `Buf`. The vector is populated once by `Start_Lines` in a single scan of the buffer (O(|Buf|)).

**Logic — `Start` (byte mode — unchanged):**

```
function Start
  (Buf     : String;
   Size    : Positive;
   Overlap : Natural) return State
is
   Step : constant Natural :=
     Natural'Max (1, (Size * (100 - Overlap)) / 100);
begin
   return (Buf    => Buf'Unrestricted_Access,
           Size   => Size,
           Step   => Step,
           Cursor => Buf'First);
end Start;
```

**Logic — `Start_Lines` (line mode):**

```
function Start_Lines
  (Buf        : String;
   Line_Count : Positive;
   Overlap    : Natural) return Line_State
is
   Line_Starts : constant Line_Array_Access := new Line_Array;
   Step        : constant Natural :=
     Natural'Max (1, (Line_Count * (100 - Overlap)) / 100);
begin
   --  Record the start of the first line.
   Line_Starts.Append (Buf'First);
   --  Scan for newline characters; the byte after each \n starts the next line.
   for I in Buf'Range loop
      if Buf (I) = ASCII.LF then
         if I < Buf'Last then
            Line_Starts.Append (I + 1);
         end if;
      end if;
   end loop;
   return (Buf        => Buf'Unrestricted_Access,
           Line_Count => Line_Count,
           Step       => Step,
           Line_Starts=> Line_Starts,
           Cursor     => Line_Starts.First_Index);
end Start_Lines;
```

**Logic — `Has_Next` (byte mode):**

```
function Has_Next (S : State) return Boolean is
   (S.Cursor <= S.Buf.all'Last);
```

**Logic — `Has_Next` (line mode):**

```
function Has_Next (S : Line_State) return Boolean is
   (S.Cursor <= S.Line_Starts.Last_Index);
```

**Logic — `Next` (byte mode):**

```
function Next (S : in out State) return String is
   End_Pos : constant Natural :=
     Natural'Min (S.Cursor + S.Size - 1, S.Buf.all'Last);
   Chunk   : constant String := S.Buf (S.Cursor .. End_Pos);
begin
   S.Cursor := S.Cursor + S.Step;
   return Chunk;
end Next;
```

**Logic — `Next` (line mode):**

```
function Next (S : in out Line_State) return String is
   First_Line : constant Positive := S.Cursor;
   Last_Line  : constant Natural :=
     Positive'Min (First_Line + S.Line_Count - 1,
                   S.Line_Starts.Last_Index);
   Start_Pos  : constant Natural := S.Line_Starts (First_Line);
   End_Pos    : constant Natural :=
     (if Last_Line = S.Line_Starts.Last_Index
      then S.Buf.all'Last
      else S.Line_Starts (Last_Line + 1) - 1);
begin
   S.Cursor := S.Cursor + S.Step;
   return S.Buf (Start_Pos .. End_Pos);
end Next;
```

**Edge cases:**
- `Step` clamped to minimum 1 to prevent infinite loops at very small chunk
  sizes with high overlap (e.g., Size=5, Overlap=99 → Step=0 without clamp).
  Applies to both modes.
- Last chunk may be shorter than `Size` / `Line_Count` (REQ-013, REQ-060).
- `Has_Next` returns False immediately for an empty buffer (caller checks
  before calling `Start` / `Start_Lines`).
- The returned chunk is a substring slice of `Buf` — no allocation.
- **Line mode — trailing bytes:** Bytes after the last `\n` are treated as a
  final (possibly empty) line. This matches the POSIX definition of a text
  line (REQ-060).
- **Line mode — no newlines:** An input buffer with zero newline characters
  is treated as a single line. `Line_Starts` contains one entry at `Buf'First`,
  and a single chunk spanning the entire buffer is produced.

---
### 5.11 `Crab_TopK` — Bounded Top-K Heap

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_TopK` |
| **Type** | Package (algorithm) |
| **Purpose** | Maintain the top-*k* (or bottom-*k*) scored chunks using a bounded binary heap. Provide sorted extraction and formatted printing. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Scored_Entry` | Private type | `(Score: Integer; File_Path: Unbounded_String; Offset: Natural; Data: Unbounded_String)` |
| `Heap` | Private type | Bounded binary heap |
| `Create (K, Invert)` | Function → `Heap` | Initialise empty heap |
| `Insert (Heap, Score, File_Path, Offset, Data)` | Procedure | Insert or discard based on score vs. heap minimum (or maximum) |
| `Is_Empty (Heap)` | Function → Boolean | True if no entries inserted |
| `Count (Heap)` | Function → Natural | Number of entries currently held |
| `Print (Heap)` | Procedure | Extract in sorted order and print to stdout |

**Heap strategy:**

- **Normal mode** (`Invert = False`): min-heap on score. The top of the heap is
  the *worst* (smallest) score. A new entry is inserted if its score exceeds
  the minimum in the heap (or if the heap is not yet full). When the heap is full
  and a new entry qualifies, the minimum is evicted. The heap always contains the
  *k* best scores seen so far.
- **Invert mode** (`Invert = True`): max-heap on score. The top of the heap is the
  *best* (largest) score. A new entry is inserted if its score is less than the
  maximum in the heap (or if the heap is not yet full). The heap always contains
  the *k* worst scores seen so far.

**[Rationale]** Using a min-heap for top-*k* means the least-qualifying entry
is always at the root — O(1) to inspect, O(log *k*) to evict and re-heapify.

**Internal Data Elements:**

| Name | Type | Role |
|---|---|---|
| `Entries` | `array (1 .. K) of Scored_Entry` | Heap array |
| `Size` | `Natural` range 0 .. K | Current count |
| `K` | `Positive` | Capacity |
| `Invert` | `Boolean` | Direction of scoring |

**Logic — Insert:**

```
procedure Insert
  (Heap      : in out Heap_Type;
   Score     : Integer;
   File_Path : String;
   Offset    : Natural;
   Data      : String)
is
begin
   if Heap.Size < Heap.K then
      -- Heap not full: always insert
      Heap.Size := Heap.Size + 1;
      Heap.Entries (Heap.Size) :=
        (Score     => Score,
         File_Path => To_Unbounded_String (File_Path),
         Offset    => Offset,
         Data      => To_Unbounded_String (Data));
      Sift_Up (Heap, Heap.Size);
   else
      -- Heap full: check against root (worst entry)
      if Should_Replace (Heap, Score) then
         Heap.Entries (1) :=
           (Score     => Score,
            File_Path => To_Unbounded_String (File_Path),
            Offset    => Offset,
            Data      => To_Unbounded_String (Data));
         Sift_Down (Heap, 1);
      end if;
      -- else: discard (score not good enough)
   end if;
end Insert;
```

Where `Should_Replace` is:
```
function Should_Replace (Heap : Heap_Type; Score : Integer) return Boolean is
begin
   if Heap.Invert then
      return Score < Heap.Entries (1).Score;  -- max-heap: replace if smaller
   else
      return Score > Heap.Entries (1).Score;  -- min-heap: replace if larger
   end if;
end Should_Replace;
```

**Tie-breaking in `Sift_Up` / `Sift_Down`:**
When scores are equal, the entry with the **smaller `Offset`** (earlier in the
file) is considered "better" for both normal and invert modes (REQ-032). Since
files are processed in order, `Offset` values are only compared within the same
file. Between files, the earlier-processed file wins — but since files are
processed deterministically (REQ-043), we don't need an explicit file-order
tie-break; the existing entry was inserted first, and we can treat the newer
entry as "worse" when scores are equal.

```
function Less_Heap (A, B : Scored_Entry; Invert : Boolean) return Boolean is
   --  True if A is "worse" than B and should sink lower in the heap
begin
   if A.Score /= B.Score then
      if Invert then
         return A.Score > B.Score;  -- max-heap: larger is "better" (stays up)
      else
         return A.Score < B.Score;  -- min-heap: smaller is "worse" (sinks)
      end if;
   else
      -- Tie: later offset is "worse" (REQ-032)
      return A.Offset > B.Offset;
   end if;
end Less_Heap;
```

**Logic — Print:**

```
procedure Print (Heap : in out Heap_Type) is
   -- 1. Extract all entries from the heap in sorted order.
   --    Repeatedly pop the root (best entry), sift, and collect.
   --    For normal mode (min-heap), we extract from the root of
   --    the min-heap — but the root is the *worst*, not the *best*.
   --
   --  Revised approach: sort the Entries array in-place, or
   --  better: build a sorted copy.
   --
   --  Simplest correct approach: copy Entries(1..Size) to an array,
   --  sort with a comparison function, print.
begin
   declare
      subtype Index_Range is Positive range 1 .. Heap.Size;
      type Entry_Array is array (Index_Range) of Scored_Entry;
      Arr : Entry_Array;
   begin
      -- Copy heap entries
      for I in Index_Range loop
         Arr (I) := Heap.Entries (I);
      end loop;
      -- Sort: best first
      Sort_Entry_Array (Arr, Heap.Invert);
      -- Print
      for Rank in Index_Range loop
         declare
            E : Scored_Entry renames Arr (Rank);
         begin
            Put_Line ("## chunk=" & Image (Rank)
                      & " score=" & Image (E.Score)
                      & " file=" & To_String (E.File_Path)
                      & " offset=" & Image (E.Offset));
            Put (To_String (E.Data));
            if Rank < Heap.Size then
               New_Line; New_Line;  -- blank line separator
            end if;
         end;
      end loop;
   end;
end Print;
```

**Sort comparison — best first:**

```
function Less_Sort (A, B : Scored_Entry; Invert : Boolean) return Boolean is
begin
   if A.Score /= B.Score then
      if Invert then
         return A.Score < B.Score;   -- ascending for invert
      else
         return A.Score > B.Score;   -- descending for normal
      end if;
   else
      return A.Offset < B.Offset;    -- tie-break by offset (earlier first)
   end if;
end Less_Sort;
```

**Constraints:**
- Heap operations are O(log *k*). With *k* typically small (default 10), this is
  negligible.
- `Scored_Entry.Data` stores a copy of the original (unfolded) chunk bytes.
  Maximum total storage for chunk data = *k* × *chunk_size* bytes.
- The `Offset` stored is the per-file byte offset (0-based).
- `Image` converts integers to decimal strings without leading padding.

---

## 6. Requirements Traceability

### 6.1 Requirement-to-Unit Map

| Requirement | Implementing Unit(s) | Detail |
|---|---|---|
| REQ-001 | `crab.adb` | `Parse_Args` handles all flags |
| REQ-002 | `crab.adb` | `-h`/`--help` detection in `Parse_Args`; `Print_Usage` |
| REQ-003 | `crab.adb` | `--version` detection; prints `Crab_Config.Crate_Version` |
| REQ-004 | `crab.adb` | Query validation in `Parse_Args` |
| REQ-047 | `Crab_Fold`, `crab.adb` | `Fold` applied to Query and each file buffer when `-i` |
| REQ-005 | `crab.adb` | `Process_One_File` per file; files processed independently |
| REQ-006 | `crab.adb` | `Read_Stdin` path when no files/dirs |
| REQ-007 | `crab.adb` | Byte-oriented reads; no encoding conversion |
| REQ-008 | `crab.adb` | `Name_Error` handler in file loop → exit 2 |
| REQ-041 | `Crab_Scanner`, `crab.adb` | `-r` flag → `Scan` call; directory-without-`-r` → error |
| REQ-042 | `Crab_Scanner` | `Walk` descends all subdirs; skips `.` and `..` |
| REQ-043 | `Crab_Scanner` | `Sort` per directory; final `Sort_By_Path` |
| REQ-044 | `Crab_Scanner` | `Ada.Directories` follows symlinks; `Normalize_Pathname` |
| REQ-045 | `Crab_Scanner` | Exception handler in `Walk` → warning, continue |
| REQ-046 | `Crab_Scanner` + `crab.adb` | Empty `Files` vector → exit 2 or 4 |
| REQ-049 | `Crab_Glob`, `Crab_Scanner` | `Include_Pats` → `Should_Process` |
| REQ-050 | `Crab_Glob`, `Crab_Scanner` | `Exclude_Pats` → `Should_Process` (excludes override) |
| REQ-051 | `Crab_Fnmatch`, `Crab_Glob` | `fnmatch()` via `Match` |
| REQ-052 | `Crab_Scanner` | Globs only applied in `Scan`; explicit-file path bypasses |
| REQ-053 | `Crab_Scanner` | `Max_Depth` parameter in `Walk` |
| REQ-054 | `crab.adb`, `Crab_Scanner` | `Max_Depth := Natural'Last` default (= unlimited) |
| REQ-009 | `Crab_Chunker` | `Next` yields fixed-size chunks; last chunk shorter |
| REQ-010 | `crab.adb`, `Crab_Chunker` | `--chunk-size` validated, passed as `Size` |
| REQ-011 | `Crab_Chunker` | `Step = Max(1, Size × (100−Overlap) / 100)` |
| REQ-012 | `crab.adb` | `Parse_Args` validates [0,99] |
| REQ-013 | `Crab_Chunker` | `End_Pos = min (Cursor+Size−1, Last)` |
| REQ-014 | `crab.adb` | Empty input check before file loop; `TopK.Is_Empty` after |
| REQ-059 | `Crab_Chunker`, `crab.adb` | `--chunk-lines` validated; `Start_Lines` initialisation |
| REQ-060 | `Crab_Chunker` | Line-mode `Next` yields chunks of N consecutive lines |
| REQ-061 | `Crab_Chunker` | Line-mode `Step = Max(1, Line_Count × (100−Overlap) / 100)` |
| REQ-015 | `Crab_Compression`, `crab.adb` | `Algorithm` enum; `Parse_Args` validates |
| REQ-018 | `crab.adb`, `Crab_Compression` | `Level` parameter; default from `Level_Default` |
| REQ-019 | `crab.adb` | `Parse_Args` validates range per algorithm |
| REQ-020 | `Crab_Zlib`, `Crab_LZ4` | Return `Natural` compressed byte count |
| REQ-020 | `Crab_Zlib`, `Crab_LZ4` | Return `Natural` compressed byte count from streaming API |
| REQ-021 | `Crab_Scorer` | `Score = Bare_CS − Dict_CS` via dictionary-preloaded streaming compression |
| REQ-022 | `Crab_Scorer` | `Init` creates persistent stream objects; loads Query as dictionary once |
| REQ-023 | `Crab_Scorer` | Dictionary is Query; compressor's window pre-populated with Query; no concatenation |
| REQ-024 | `crab.adb` + `Crab_Scorer` | `Score` called for every chunk from every file |
| REQ-025 | `Crab_Scorer`, `Crab_TopK` | `Score : Integer` (signed); stored in heap |
| REQ-026 | `Crab_TopK` | Bounded heap selects top/bottom *k* |
| REQ-027 | `Crab_TopK`, `crab.adb` | Heap capacity = *k*; fewer if total chunks < *k* |
| REQ-028 | `Crab_TopK` | `Print` sorts descending (or ascending with `Invert`) |
| REQ-029 | `Crab_TopK` | Header format `## chunk=N score=S file=P offset=O` |
| REQ-030 | `Crab_TopK` | `Data` stored as original bytes; `Put` without transformation |
| REQ-031 | `Crab_TopK` | Blank line between chunks in `Print` |
| REQ-032 | `Crab_TopK` | Tie-break: earlier offset ranks higher |
| REQ-055 | `Crab_TopK`, `crab.adb` | `Invert` parameter; max-heap mode; ascending sort |
| REQ-033 | `crab.adb` | Exit codes in exception handlers and conditional branches |
| REQ-034 | `crab.adb`, `Crab_Scanner` | All diagnostics to `Standard_Error` |
| REQ-035 | `alire.toml`, `crab.gpr` | Linker flags for `-lz`, `-llz4` |
| REQ-036 | Build system | GNAT 13, Linux x86_64 |
| REQ-037 | Build system | `alr build` via `crab.gpr` |
| REQ-038 | All units | Ada 2012 |
| REQ-039 | `alire.toml` | License field |
| REQ-040 | `crab_config.gpr` | GNAT style switches |
| REQ-056 | `Crab_Fnmatch` | `fnmatch()` import; no hand-rolled glob |
| REQ-057 | `share/man/man1/crab.1` | Static man page source |

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
| `Crab_Compression` | `Crab_Compression_Tests` | Unit (with stub backends or live zlib/lz4) |
| `Crab_Fold` | `Crab_Fold_Tests` | Unit |
| `Crab_Glob` | `Crab_Glob_Tests` | Unit (mock fnmatch results) |
| `Crab_Scorer` | `Crab_Scorer_Tests` | Unit (with known compressed sizes) |
| `Crab_TopK` | `Crab_TopK_Tests` | Unit |
| `Crab_Scanner` | `Crab_Scanner_Tests` | Integration (uses real filesystem) |
| `Crab_Zlib` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_LZ4` | (exercised via `Crab_Compression_Tests`) | Integration |
| `Crab_Fnmatch` | (exercised via `Crab_Glob_Tests`) | Integration |

**Build and run:**

```
cd tests/
alr build    # compiles crab_tests executable
alr run      # executes all suites, reports pass/fail
```

The test GPR (`tests/crab_tests.gpr`) references the parent crate's source and
object directories to link against the `crab` packages directly.  This avoids
needing `crab` to be a library crate.

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
| `Interfaces.C` | `Crab_Zlib`, `Crab_LZ4`, `Crab_Fnmatch` — C type definitions |
| `GNAT.OS_Lib` | `Crab_Scanner` — `Normalize_Pathname` for cycle detection |
| `System.Address` | Binding packages — C buffer passing |
| `Ada.Exceptions` | `crab.adb`, `Crab_Scanner` — exception messages |

### 7.2 Build Configuration

The GPR project file `crab.gpr` must be updated to:
- Add `-lz` linker switch for libz
- Add `-llz4` linker switch for liblz4
- Install `share/man/man1/crab.1` via the existing `Install` artifacts rule

### 7.3 Key Design Decisions — Client Confirmed

| Decision | Rationale |
|---|---|
| Streaming per-file processing | Client: "more streaming manner ... each file in isolation" |
| Top-K bounded heap | Client: "top-k chunk with the lowest score" displaced; O(k) memory |
| No concatenation of files | Client: "do not want to concatenate the files together" |
| Tie-break by offset within file | Files processed deterministically; file ordering gives cross-file determinism |

### 7.4 Open for Future Builds

- Memory-map files for zero-copy I/O on large files
- Additional compression backends (bzip2, zstd, brotli)
- Unicode case folding (currently ASCII-only)
- Threaded file processing with merge of per-file Top-K heaps
- Output mode: JSON, CSV, or machine-parseable formats
- `--label` for stdin naming
- `-l` (files-with-results), `-c` (count), `-q` (quiet) flags
