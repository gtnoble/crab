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
   Help and version flags short-circuit exit.
2. **Query preparation.** If `-i`, the query is case-folded. The (possibly folded)
   query is compressed once; its compressed size is cached in the Scorer.
3. **File loop.** For each input file (from the Scanner if `-r`, from explicit
   arguments, or stdin as a single pseudo-file):
   a. Read the file's bytes into a buffer.
   b. If `-i`, produce a folded copy of the buffer for scoring; keep the original
      for output.
   c. Feed the scoring buffer into the Chunker — a streaming iterator that yields
      one fixed-size overlapping chunk at a time.
   d. For each chunk, pass its folded data to the Scorer to compute the MI‑approx
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
| **Score heap** | Binary heap of at most *k* elements. O(*k* log *k*) insertion and O(*k* log *k*) final extraction. |
| **Compression buffers** | Two persistent buffers allocated once at `Scorer.Init` time and reused for every chunk compression across all files: `Chunk_Buf` (size = `compressBound(chunk_size)`) and `Joint_Buf` (size = `compressBound(query_size + chunk_size)`). No per-call allocation or deallocation occurs on the hot path. The query compression buffer is allocated once in `Init` and freed immediately after use. |
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
|---|---|---|
| `crab` | Main procedure | Argument parsing, streaming orchestration, top-level error handling |
| `Crab_Zlib` | Package (binding) | Thin Ada binding to libz `compress2()` and `compressBound()` |
| `Crab_LZ4` | Package (binding) | Thin Ada binding to liblz4 `LZ4_compress_default()` and `LZ4_compressBound()` |
| `Crab_Fnmatch` | Package (binding) | Thin Ada binding to libc `fnmatch()` for shell glob matching |
| `Crab_Compression` | Package (abstraction) | Uniform compression interface dispatching to DEFLATE/LZ4 backends |
| `Crab_Fold` | Package (utility) | ASCII case folding for `--ignore-case` |
| `Crab_Glob` | Package (utility) | Multi-pattern include/exclude matching using `fnmatch` |
| `Crab_Scanner` | Package (I/O) | Directory traversal with glob filtering, depth limiting, symlink-cycle detection |
| `Crab_Chunker` | Package (algorithm) | Streaming iterator over fixed-size overlapping chunks of a byte buffer |
| `Crab_Scorer` | Package (algorithm) | Stateful MI‑approx scorer: caches query compression, scores individual chunks |
| `Crab_TopK` | Package (algorithm) | Bounded binary heap maintaining the top-*k* (or bottom-*k*) scored chunks |

### 4.2 Static Relationships — Dependency Graph

```
crab.adb
 ├── Crab_Compression ──────┬── Crab_Zlib
 │                           └── Crab_LZ4
 ├── Crab_Fold
 ├── Crab_Scanner ──────────┬── Crab_Glob ─── Crab_Fnmatch
 │                           └── GNAT.OS_Lib
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
  ├─[3] Validate query, chunk-size, etc    → exit 1 (if invalid)
  │
  ├─[4] Prepare query:
  │       Scoring_Query := (if -i then Fold(Query) else Query)
  │       Scorer.Init (Scoring_Query, Chunk_Size, Algo, Level)
  │            → caches |compress(Scoring_Query)|
  │
  ├─[5] TopK.Init (K, Invert)
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
  │       ├─[7c] Chunker.Start (Scoring_Buf, Chunk_Size, Overlap)
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
| **Scorer stateful with cached query CS** | Crab_Scorer | Query compressed once across all chunks. `Scorer.Init` caches; `Scorer.Score` only compresses chunk + joint. |
| **Original bytes preserved for output** | crab.adb | When `-i`, the file buffer (original) and folded buffer both exist. The chunk's offset into the folded buffer is identical to its offset into the original buffer (fold is byte-for-byte). |
| **`System.Address` for C buffer passing** | Crab_Zlib, Crab_LZ4, Crab_Fnmatch | Avoids intermediate copies when passing String data to C functions. Ada `String` is a contiguous byte array on GNAT/x86_64 — its `'Address` is a valid `const char*`. |
| **GNAT.OS_Lib for canonical paths** | Crab_Scanner | `Normalize_Pathname` with `Resolve_Links => True` resolves symlinks and provides canonical paths for cycle detection without an additional C binding. |
| **`Ada.Directories` for file system ops** | Crab_Scanner | Portable, already in GNAT runtime. Follows symlinks by default (matches REQ-044). |
| **`String` slice for chunk data** | Crab_Chunker, crab.adb | `Next` returns a slice of the scoring buffer — no allocation. The caller (crab.adb) copies the corresponding original-buffer slice into the Top‑K heap when the chunk succeeds. |
| **Persistent compression buffers** | Crab_Zlib, Crab_LZ4, Crab_Compression, Crab_Scorer | Two buffers (`Chunk_Buf`, `Joint_Buf`) allocated once in `Scorer.Init` and reused for every chunk compression across all files. Eliminates ~2N allocations on the scoring hot path. |

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
| `Crab_Chunker` | REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014 |
| `Crab_Scorer` | REQ-021, REQ-022, REQ-023, REQ-024, REQ-025 |
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
   --   -o, --overlap    → next arg: 0–99 integer
   --   -k, --top        → next arg: positive integer
   --   -r, --recursive  → set flag
   --   -i, --ignore-case→ set flag
   --   -v, --invert     → set flag
   --   --include        → next arg: add to Cfg.Include_Pats
   --   --exclude        → next arg: add to Cfg.Exclude_Pats
   --   --max-depth      → next arg: non-negative integer
   -- Validates: query non-empty, chunk-size set, level in range per algo.
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
     Crab_Chunker.Start (Scoring_Buf, Cfg.Chunk_Size, Cfg.Overlap);
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
`Ada.Text_IO` for stderr diagnostic output. Application packages do not perform I/O
except `Crab_Scanner` (stderr warnings) and `Crab_TopK` (stdout printing).

---

### 5.2 `Crab_Zlib` — zlib Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Zlib` |
| **Type** | Package (C binding) |
| **Purpose** | Provide `Compress_Into`, `Compress`, and `Compress_Bound` subprograms backed by libz. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Zlib_Error` | Exception | Raised when `compress2` returns non-zero |
| `Compress_Bound (Source_Len)` | Function → Natural | Maximum possible compressed size (for buffer pre-allocation) |
| `Compress (Source, Level)` | Function → Natural | One-shot: auto-allocates, compresses, returns compressed size |
| `Compress_Into (Source, Level, Dest)` | Procedure → out `Dest_Len: Natural` | Compresses `Source` into a pre-allocated `Dest` buffer; returns the number of bytes written. `Dest` must be at least `Compress_Bound(Source'Length)` bytes. |

**The `Compress_Into` procedure (hot-path call):**

```
procedure Compress_Into
  (Source   : String;
   Level    : Integer;
   Dest     : in out Byte_Array;
   Dest_Len : out Natural)
is
   Src_Len : constant C.unsigned_long := C.unsigned_long (Source'Length);
   Dst_Tmp : aliased C.unsigned_long := C.unsigned_long (Dest'Length);
   Result  : C.int;
begin
   Result := c_compress2
     (Dest'Address, Dst_Tmp'Access,
      Source'Address, Src_Len,
      C.int (Level));
   if Result /= Z_OK then
      raise Zlib_Error;
   end if;
   Dest_Len := Natural (Dst_Tmp);
end Compress_Into;
```

**The `Compress` function (convenience wrapper):**

```
function Compress (Source : String; Level : Integer) return Natural is
   Dst_Buf : Byte_Array (1 .. Compress_Bound (Source'Length));
   Dst_Len : Natural;
begin
   Compress_Into (Source, Level, Dst_Buf, Dst_Len);
   return Dst_Len;
end Compress;
```

Where `c_compress2` is imported from libz with `External_Name => "compress2"`,
`Z_OK = 0`, and `Byte_Array` is `array (Natural range <>) of
Interfaces.C.unsigned_char`.

**[Rationale]** `Compress_Into` accepts a pre-allocated buffer from the caller —
this avoids heap/stack allocation on every chunk scoring call (hot path).
`Compress` is retained for one-shot cases (e.g., compressing the query once
during `Init`) and for testing.

**Constraints:** Only the `compress2`/`compressBound` API of zlib is used.
Streaming (`deflateInit`/`deflate`/`deflateEnd`) is not needed.

### 5.3 `Crab_LZ4` — LZ4 Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_LZ4` |
| **Type** | Package (C binding) |
| **Purpose** | Provide `Compress_Into`, `Compress`, and `Compress_Bound` subprograms backed by liblz4. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `LZ4_Error` | Exception | Raised when `LZ4_compress_default` returns ≤ 0 |
| `Compress_Bound (Input_Size)` | Function → Natural | Maximum possible compressed size |
| `Compress (Source, Acceleration)` | Function → Natural | One-shot convenience wrapper |
| `Compress_Into (Source, Acceleration, Dest)` | Procedure → out `Dest_Len: Natural` | Compresses into pre-allocated buffer |

**The `Compress_Into` procedure (hot path):**

```
procedure Compress_Into
  (Source       : String;
   Acceleration : Integer;
   Dest         : in out Byte_Array;
   Dest_Len     : out Natural)
is
   Src_Size : constant C.int := C.int (Source'Length);
   Dst_Cap  : constant C.int := C.int (Dest'Length);
   Result   : C.int;
begin
   Result := LZ4_compress_default
     (Source'Address, Dest'Address, Src_Size, Dst_Cap);
   if Result <= 0 then
      raise LZ4_Error;
   end if;
   Dest_Len := Natural (Result);
end Compress_Into;
```

**Convenience wrapper:**

```
function Compress (Source : String; Acceleration : Integer) return Natural is
   Dst_Buf : Byte_Array (1 .. Compress_Bound (Source'Length));
   Dst_Len : Natural;
begin
   Compress_Into (Source, Acceleration, Dst_Buf, Dst_Len);
   return Dst_Len;
end Compress;
```

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
| **Purpose** | Provide a uniform compression interface dispatching to DEFLATE or LZ4. Includes both one-shot (`Compress`) and persistent-buffer (`Compress_Into`) variants. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Algorithm` | Enumeration | `(Deflate, LZ4)` |
| `Compression_Error` | Exception | Propagated from backend errors |
| `Compress_Bound (Algo, Source_Len)` | Function → Natural | Upper bound for buffer pre-allocation |
| `Compress (Algo, Source, Level)` | Function → Natural | One-shot; auto-allocates |
| `Compress_Into (Algo, Source, Level, Dest)` | Procedure → out `Dest_Len: Natural` | Compresses into pre-allocated buffer |
| `Level_Default (Algo)` | Function → Integer | Default compression level |
| `Level_Min (Algo)` | Function → Integer | Minimum valid level |
| `Level_Max (Algo)` | Function → Integer | Maximum valid level |

**`Compress_Into` dispatch:**

```
procedure Compress_Into
  (Algo     : Algorithm;
   Source   : String;
   Level    : Integer;
   Dest     : in out Byte_Array;
   Dest_Len : out Natural)
is
begin
   case Algo is
      when Deflate =>
         Crab_Zlib.Compress_Into (Source, Level, Dest, Dest_Len);
      when LZ4 =>
         Crab_LZ4.Compress_Into (Source, Level, Dest, Dest_Len);
   end case;
end Compress_Into;
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

**[Rationale]** `Compress_Bound` is exposed at this level so callers (notably
`Crab_Scorer`) can pre-compute buffer sizes without depending on the backend
bindings directly.

### 5.6 `Crab_Fold` — Case Folding

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

### 5.7 `Crab_Glob` — Glob Pattern Matching

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

### 5.8 `Crab_Scanner` — Directory Traversal

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

### 5.9 `Crab_Chunker` — Streaming Chunk Iterator

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Chunker` |
| **Type** | Package (algorithm) |
| **Purpose** | Provide a streaming iterator over fixed-size overlapping chunks of a byte buffer. No intermediate vector — one chunk at a time. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `State` | Private type | Iterator state (private record) |
| `Start (Buf, Size, Overlap)` | Function → `State` | Initialise iterator over `Buf` |
| `Has_Next (S)` | Function → Boolean | True if more chunks remain |
| `Next (S)` | Procedure (in out State) → String | Advance; return next chunk as a slice of the buffer |

**Data Elements (in State):**

| Name | Type | Role |
|---|---|---|
| `Buf` | `Not null access constant String` | Reference to the input buffer (no copy) |
| `Size` | `Positive` | Chunk size in bytes |
| `Step` | `Natural` | Bytes to advance per chunk |
| `Cursor` | `Natural` | Current start position in `Buf` |

**Logic:**

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

function Has_Next (S : State) return Boolean is
   (S.Cursor <= S.Buf.all'Last);

procedure Next (S : in out State) return String is
   End_Pos : constant Natural :=
     Natural'Min (S.Cursor + S.Size - 1, S.Buf.all'Last);
   Chunk   : constant String := S.Buf (S.Cursor .. End_Pos);
begin
   S.Cursor := S.Cursor + S.Step;
   return Chunk;
end Next;
```

**Edge cases:**
- `Step` clamped to minimum 1 to prevent infinite loops at very small chunk
  sizes with high overlap (e.g., Size=5, Overlap=99 → Step=0 without clamp).
- Last chunk may be shorter than `Size` (REQ-013).
- `Has_Next` returns False immediately for an empty buffer (caller checks
  before calling `Start`).
- The returned chunk is a substring slice of `Buf` — no allocation.

---

### 5.10 `Crab_Scorer` — Stateful MI Scorer

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Scorer` |
| **Type** | Package (algorithm) |
| **Purpose** | Cache the compressed size of the query; hold persistent compression buffers for reuse across all chunk scoring calls; score individual chunks against the query. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `State` | Private type | Cached scorer state including persistent buffers |
| `Init (Query, Chunk_Size, Algo, Level)` | Function → `State` | Compress query (one-shot); pre-allocate `Chunk_Buf` and `Joint_Buf` |
| `Score (S, Chunk)` | Function → Integer | MI‑approx score for one chunk using persistent buffers |

**Data Elements (in State):**

| Name | Type | Role |
|---|---|---|
| `Algo` | `Crab_Compression.Algorithm` | Compression backend |
| `Level` | `Integer` | Compression level |
| `Query_Str` | `Unbounded_String` | Query text stored for concatenation |
| `Query_CS` | `Natural` | Cached compressed size of the query |
| `Chunk_Buf` | `Byte_Array_Access` | Persistent buffer for chunk compression; size = `Compress_Bound(Chunk_Size)` |
| `Joint_Buf` | `Byte_Array_Access` | Persistent buffer for joint compression; size = `Compress_Bound(Query_Size + Chunk_Size)` |

**Buffer type definition (in package specification):**

```
type Byte_Array_Access is access all
  Interfaces.C.unsigned_char_Array (Natural range <>);
--  Heap-allocated, dynamically sized at Init time, reused for the entire run.
```

**`Init` — allocate persistent buffers:**

```
function Init
  (Query      : String;
   Chunk_Size : Positive;
   Algo       : Crab_Compression.Algorithm;
   Level      : Integer) return State
is
   package UBS renames Ada.Strings.Unbounded;
   Query_CS : Natural;
begin
   --  One-shot compress of the query (buffer freed on return)
   Query_CS := Crab_Compression.Compress (Algo, Query, Level);
   return (Algo      => Algo,
           Level     => Level,
           Query_Str => UBS.To_Unbounded_String (Query),
           Query_CS  => Query_CS,
           Chunk_Buf => new Byte_Array
             (1 .. Crab_Compression.Compress_Bound (Algo, Chunk_Size)),
           Joint_Buf => new Byte_Array
             (1 .. Crab_Compression.Compress_Bound
                    (Algo, Query'Length + Chunk_Size)));
end Init;
```

**`Score` — reuse persistent buffers (hot path, zero allocation):**

```
function Score (S : State; Chunk : String) return Integer is
   Chunk_CS  : Natural;
   Joint_Str : constant String :=
     Ada.Strings.Unbounded.To_String (S.Query_Str) & Chunk;
   Joint_CS  : Natural;
begin
   --  Chunk compression into persistent Chunk_Buf
   Crab_Compression.Compress_Into
     (Algo     => S.Algo,
      Source   => Chunk,
      Level    => S.Level,
      Dest     => S.Chunk_Buf.all,
      Dest_Len => Chunk_CS);

   --  Joint compression into persistent Joint_Buf
   Crab_Compression.Compress_Into
     (Algo     => S.Algo,
      Source   => Joint_Str,
      Level    => S.Level,
      Dest     => S.Joint_Buf.all,
      Dest_Len => Joint_CS);

   return Integer (S.Query_CS) + Integer (Chunk_CS) - Integer (Joint_CS);
end Score;
```

**Constraints:**

- Query text is stored in `State` so that `Score` can construct the joint string
  `Query & Chunk` (REQ-023) without the caller passing the query on every call.
- The query is compressed once in `Init` (REQ-022) using the convenience
  one-shot `Compress` — its temporary buffer is freed on return from `Init`.
- The `Joint_Str` concatenation (`Query_Str & Chunk`) does allocate a new
  `String` on each `Score` call — this is a known cost. A future optimisation
  could pre-allocate a joint string buffer and copy into it, but the allocation
  is at most `|Q| + |C|` bytes and is deallocated before `Score` returns.
- `Chunk_Buf` and `Joint_Buf` are heap-allocated once per invocation. They are
  conservatively sized to the worst case (`compressBound`). In practice the
  compressed output is typically much smaller.
- Scores are signed `Integer` (REQ-025).

**[Rationale]** The two persistent buffers eliminate ~2N stack/heap allocations
per invocation (where N = number of chunks across all files). On a typical run
with moderate chunk size and hundreds of chunks, this avoids thousands of
allocations. The buffer lifetime is the entire invocation — allocated in `Init`,
reused for every `Score` call, and freed when `State` goes out of scope in
`crab.adb`.

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
| REQ-015 | `Crab_Compression`, `crab.adb` | `Algorithm` enum; `Parse_Args` validates |
| REQ-016 | `Crab_Zlib` | `c_compress2` import from libz |
| REQ-017 | `Crab_LZ4` | `LZ4_compress_default` import from liblz4 |
| REQ-018 | `crab.adb`, `Crab_Compression` | `Level` parameter; default from `Level_Default` |
| REQ-019 | `crab.adb` | `Parse_Args` validates range per algorithm |
| REQ-020 | `Crab_Zlib`, `Crab_LZ4` | Return `Natural` compressed byte count |
| REQ-021 | `Crab_Scorer` | `Score = Q_CS + C_CS − Joint_CS` |
| REQ-022 | `Crab_Scorer` | `Init` compresses query once; `Query_CS` cached in `State` |
| REQ-023 | `Crab_Scorer` | `Joint_Str := Query_Str & Chunk` |
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
