# Software Design Description — Crab

**Project:** Crab — Compression-based mutual-information grep
**Date:** 2026-06-18
**Version:** 1.0
**Component:** `crab` (sole component)

---

## 1. Scope

### 1.1 Component Identifier

`crab` — a CLI executable, decompiling into 11 Ada packages plus the main procedure,
that selects and outputs the *k* chunks of text having the greatest (or least)
compression-based mutual information with a user query.

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

`crab` executes in a single pass:

1. **Argument parsing.** Command-line arguments are parsed into a `Config` record.
   Help and version flags short-circuit exit.
2. **Input gathering.** If `-r` or directories are present, the Scanner traverses
   directory trees collecting file paths. Otherwise, named files or stdin are read.
   All file content is concatenated into a single byte buffer (`String`).
3. **Case folding** (if `-i`). Query and the concatenated input are mapped to
   lowercase (ASCII only). The original (unfolded) input is preserved for output.
4. **Chunking.** A sliding window extracts fixed-size, overlapping chunks from the
   folded input. Each chunk records its global byte offset.
5. **Scoring.** The (folded) query is compressed once. Each chunk is compressed
   individually and jointly with the query. The MI‑approx score is:
   `|compress(Q)| + |compress(C)| − |compress(Q∥C)|`.
6. **Output.** Scored chunks are sorted (descending by score, or ascending with
   `-v`). The top *k* are printed with headers containing rank, score, source file
   path, and per-file offset, followed by the original (unfolded) chunk bytes.

The tool is single-threaded. There is no interactive mode, no daemon mode, no
network communication.

### 3.2 Memory and Processing Allocation

| Concern | Strategy |
|---|---|
| **Input buffer** | All input is read into a single `String` (flat heap allocation). Large inputs may stress memory; this is documented as risk R3. |
| **Folded buffer** | When `-i` is active, a second `String` of equal size holds the folded copy. |
| **Chunk storage** | Each chunk's data is stored as an `Unbounded_String`. For *N* chunks, memory is O(*N* × chunk_size) with sharing of the underlying string buffer (no per-chunk copy of input data — chunks reference slices). |
| **Score array** | Scores are stored in a vector of `Scored_Chunk` records — one per chunk, O(*N*) integers + references. |
| **Compression buffers** | Temporary buffers allocated per `Compress` call and freed. Maximum size = `compressBound(input_size)` ≈ input_size + overhead. These are short-lived. |

### 3.3 Error and Exception Handling

| Condition | Mechanism | Exit code |
|---|---|---|
| Bad argument (invalid flag, missing value, out of range) | Print message to stderr, exit | 1 |
| File not found or unreadable (explicitly named) | Print message to stderr, exit | 2 |
| Permission denied during traversal (non-explicit) | Print warning to stderr, continue | 0 if any input read; 2 otherwise |
| Compression library error | `Compression_Error` exception → print message to stderr, exit | 3 |
| Empty input (no chunks) | Print message to stderr, exit | 4 |

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
| `crab` | Main procedure | Argument parsing, orchestration, top-level error handling |
| `Crab_Zlib` | Package (binding) | Thin Ada binding to libz `compress2()` and `compressBound()` |
| `Crab_LZ4` | Package (binding) | Thin Ada binding to liblz4 `LZ4_compress_default()` and `LZ4_compressBound()` |
| `Crab_Fnmatch` | Package (binding) | Thin Ada binding to libc `fnmatch()` for shell glob matching |
| `Crab_Compression` | Package (abstraction) | Uniform compression interface dispatching to DEFLATE/LZ4 backends |
| `Crab_Fold` | Package (utility) | ASCII case folding for `--ignore-case` |
| `Crab_Glob` | Package (utility) | Multi-pattern include/exclude matching using `fnmatch` |
| `Crab_Scanner` | Package (I/O) | Directory traversal with glob filtering, depth limiting, symlink-cycle detection |
| `Crab_Chunker` | Package (algorithm) | Sliding-window chunk extraction from byte buffer |
| `Crab_Scorer` | Package (algorithm) | MI‑approx scoring of query against chunk set |
| `Crab_Output` | Package (I/O) | Sort scored chunks, select top-k, format and print |

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
 └── Crab_Output
```

- `crab.adb` depends on **all** application packages (it is the sole orchestrator).
- `Crab_Compression` depends on `Crab_Zlib` and `Crab_LZ4` (the backends).
- `Crab_Scanner` depends on `Crab_Glob`, which depends on `Crab_Fnmatch`.
- `Crab_Scorer` depends on `Crab_Compression`.
- `Crab_Chunker`, `Crab_Fold`, and `Crab_Output` have no internal dependencies
  (pure computation/I/O packages).
- No circular dependencies. The dependency graph is a DAG rooted at `crab.adb`.

### 4.3 Dynamic Relationships — Execution Sequence

```
crab.adb
  │
  ├─[1] Parse_Args()                    → Config record
  ├─[2] Handle --help / --version       → exit 0 (if applicable)
  ├─[3] Validate query, chunk-size, etc → exit 1 (if invalid)
  │
  ├─[4] IF -r or dirs present:
  │        Scanner.Scan()               → File list
  │     ELSIF files present:
  │        Directly open files          → Input buffer + File_Map
  │     ELSE:
  │        Read stdin                   → Input buffer + File_Map
  │
  ├─[5] IF input empty → exit 4
  │
  ├─[6] IF -i:
  │        Fold_Query  := Fold(Query)
  │        Fold_Input  := Fold(Input)
  │        Keep Original_Input for output
  │     ELSE:
  │        Fold_Query  := Query
  │        Fold_Input  := Input
  │
  ├─[7] Chunker.Chunk_All(Fold_Input)   → Chunk vector
  │
  ├─[8] Scorer.Score_All(Fold_Query,
  │        Chunks, Algo, Level)         → Scored_Chunk vector
  │
  └─[9] Output.Print_Top_K(Scored, K,
           Invert, File_Map)            → stdout output
```

### 4.4 Interfaces Between Units

All interfaces between non-binding packages are defined by Ada package
specifications. The binding packages expose only `Compress` (or `FnMatch`)
subprograms — no types or constants leak across the binding boundary into
application code.

Inter-package data flow uses Ada standard types (`String`, `Integer`, `Natural`)
and Ada standard containers (`Indefinite_Vectors` of standard types). No
application-defined types cross between packages except:

- `Crab_Compression.Algorithm` — enumeration used by `crab.adb` and `Crab_Scorer`
- `Crab_Glob.Pattern_List` — used by `crab.adb` and `Crab_Scanner`
- `Crab_Chunker.Chunk` — produced by `Crab_Chunker`, consumed by `Crab_Scorer`

All cross-package types are defined in the producer package's specification.

### 4.5 Concept of Execution

The component fulfills its requirements through a **pipeline architecture**: each
stage reads data from the previous stage and produces data for the next stage. The
pipeline is sequential — no stage runs concurrently. This maps naturally to the
single-threaded batch processing model:

1. **Config stage** (arg parsing): no data flow, produces configuration.
2. **Input stage** (scanner + file I/O): produces concatenated input buffer and
   file-offset map.
3. **Transform stage** (case folding): produces transformed input, preserving
   original.
4. **Chunking stage**: produces overlapping chunks from the transformed input.
5. **Scoring stage**: produces scored chunks (compression-based MI).
6. **Output stage**: sorts, selects top-k, formats, prints.

Each stage except the config stage can be tested in isolation with fixed inputs.

### 4.6 Design Decisions Affecting Multiple Units

| Decision | Affected units | Rationale |
|---|---|---|
| **All input read into single `String`** | crab.adb, Crab_Scanner, Crab_Chunker | Simplifies chunking — chunks are just offsets into a linear buffer. Trade-off: memory for large files (see R3). |
| **Unbounded_String for chunk data** | Crab_Chunker, Crab_Scorer, Crab_Output | Chunks need not own the data; they reference slices of the input buffer. Using `Unbounded_String` avoids lifetime issues. |
| **`System.Address` for C buffer passing** | Crab_Zlib, Crab_LZ4, Crab_Fnmatch | Avoids intermediate copies when passing String data to C functions. Ada `String` is a contiguous byte array — its `'Address` is a valid `const char*`. |
| **GNAT.OS_Lib for canonical paths** | Crab_Scanner | `Normalize_Pathname` with `Resolve_Links => True` resolves symlinks and provides canonical paths for cycle detection without an additional C binding. |
| **`Ada.Directories` for file system ops** | Crab_Scanner | Portable, already in GNAT runtime. Avoids POSIX-specific bindings for `opendir`/`readdir`. Follows symlinks by default (matches REQ-044). |
| **`Indefinite_Vectors` from Ada standard library** | All packages with dynamic lists | Standard, well-tested, no external dependencies. Vectors of `String`, `Chunk`, `Scored_Chunk`, etc. |

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
| `Crab_Output` | REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-055 |

---

## 5. Detailed Design

### 5.1 `crab.adb` — Main Procedure

| Attribute | Value |
|---|---|
| **Identifier** | `crab` |
| **Type** | Main procedure (executable entry point) |
| **Purpose** | Parse arguments, orchestrate the pipeline, handle top-level errors, control exit codes. |

**Interfaces:**

```
Input:  Command-line arguments (via Ada.Command_Line)
        Standard input stream
        File system (reads input files)
Output: Standard output stream (chunk output)
        Standard error stream (diagnostics)
        Exit code (0–4)
```

**Data Elements:**

| Name | Type | Role |
|---|---|---|
| `Config` | Record (local to `crab.adb`) | Holds all parsed argument values |
| `Input_Buf` | `Unbounded_String` | Concatenated input text (original bytes) |
| `Folded_Input` | `String` | Case-folded input when `-i`; `Input_Buf` unwrapped when not |
| `File_Map` | `File_Span_Vector` | Mapping from global offset to `(file_path, start_offset, length)` |
| `Chunks` | `Chunk_Vectors.Vector` | Extracted chunks |
| `Scored` | `Scored_Chunk_Vectors.Vector` | Scored chunks |

**Config Record Definition:**

```ada
type File_Span is record
   Path         : Unbounded_String;
   Start_Offset : Natural;
   Length       : Natural;
end record;
package File_Span_Vectors is new Indefinite_Vectors (Positive, File_Span);

type Config is record
   Show_Help     : Boolean := False;
   Show_Version  : Boolean := False;
   Query         : Unbounded_String;
   Algorithm     : Crab_Compression.Algorithm := Crab_Compression.Deflate;
   Level         : Integer := Crab_Compression.Level_Default (Crab_Compression.Deflate);
   Chunk_Size    : Natural := 0;   -- 0 = not set; must be provided by user
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

```ada
procedure Parse_Args (Cfg : out Config) is
   -- Iterate Ada.Command_Line.Argument (1 .. Argument_Count).
   -- For each argument:
   --   "-h" | "--help"     → Cfg.Show_Help := True; return
   --   "--version"         → Cfg.Show_Version := True; return
   --   "-a" | "--algorithm" → read next arg, validate against
   --                          ("deflate", "lz4"), set Cfg.Algorithm
   --   "-l" | "--level"     → read next arg, parse integer, set Cfg.Level
   --   "-s" | "--chunk-size"→ read next arg, parse positive integer
   --   "-o" | "--overlap"   → read next arg, parse 0–99 integer
   --   "-k" | "--top"       → read next arg, parse positive integer
   --   "-r" | "--recursive" → Cfg.Recursive := True
   --   "-i" | "--ignore-case" → Cfg.Ignore_Case := True
   --   "-v" | "--invert"    → Cfg.Invert := True
   --   "--include"          → read next arg, add to Cfg.Include_Pats
   --   "--exclude"          → read next arg, add to Cfg.Exclude_Pats
   --   "--max-depth"        → read next arg, parse non-negative integer
   --   anything else        → if starts with '-', error "unknown flag"
   --                          else add to Cfg.Paths
   --
   -- After loop:
   --   First positional arg not matching a flag = Cfg.Query
   --   Remaining positional args = Cfg.Paths
   --   If Cfg.Query is empty after parsing → error
   --   If Cfg.Chunk_Size = 0 → error "--chunk-size is required"
   --   If Cfg.Algorithm = Deflate and Cfg.Level not in -1..9 → error
   --   If Cfg.Algorithm = LZ4 and Cfg.Level not in 1..65537 → error
```

**Logic — Main Orchestration (pseudocode):**

```ada
begin
   Parse_Args (Cfg);

   if Cfg.Show_Help then
      Print_Usage; return;
   end if;
   if Cfg.Show_Version then
      Put_Line (Crab_Config.Crate_Version); return;
   end if;

   -- Gather input
   declare
      Input_Buf : Unbounded_String;
      File_Map  : File_Span_Vectors.Vector;
      Has_Dirs  : Boolean := False;
   begin
      for P of Cfg.Paths loop
         if Is_Directory (P) then Has_Dirs := True; end if;
      end loop;

      if Cfg.Recursive or Has_Dirs then
         if not Cfg.Recursive and Has_Dirs then
            Put_Line (Stderr, "crab: directories require -r"); Exit_Code (1);
         end if;
         Read_From_Scanner (Cfg, Input_Buf, File_Map);
      elsif not Cfg.Paths.Is_Empty then
         Read_From_Files (Cfg.Paths, Input_Buf, File_Map);
      else
         Read_From_Stdin (Input_Buf);
         File_Map.Append ((Path => To_Unbounded ("(stdin)"),
                            Start_Offset => 0,
                            Length => Length (Input_Buf)));
      end if;

      if Length (Input_Buf) = 0 then
         Put_Line (Stderr, "crab: empty input"); Exit_Code (4);
      end if;

      -- Fold if needed
      Orig_Input : constant String := To_String (Input_Buf);
      Query      : constant String :=
        (if Cfg.Ignore_Case then To_String (Cfg.Query) else ...) -- actually Query is already folded or not
        ... hmm
```

Let me reconsider the flow. The Query is already a string — if Ignore_Case we fold it. The input is unfolded (original) saved for output. We fold it for scoring.

```ada
      -- Determine query and input for scoring
      Folded_Query : constant String :=
        (if Cfg.Ignore_Case
         then Crab_Fold.Fold (To_String (Cfg.Query))
         else To_String (Cfg.Query));
      Scoring_Input : constant String :=
        (if Cfg.Ignore_Case
         then Crab_Fold.Fold (To_String (Input_Buf))
         else To_String (Input_Buf));
      Orig_Input : constant String := To_String (Input_Buf);

      -- Chunk
      Chunks : constant Chunk_Vectors.Vector :=
        Crab_Chunker.Chunk_All (Scoring_Input, Cfg.Chunk_Size, Cfg.Overlap);

      -- Score
      Scored : constant Scored_Chunk_Vectors.Vector :=
        Crab_Scorer.Score_All
          (Query   => Folded_Query,
           Chunks  => Chunks,
           Algo    => Cfg.Algorithm,
           Level   => Cfg.Level);

      -- Output (uses Orig_Input for chunk data, not Scoring_Input)
      Crab_Output.Print_Top_K
        (Scored        => Scored,
         K             => Cfg.Top_K,
         Invert        => Cfg.Invert,
         File_Map      => File_Map,
         Original_Input => Orig_Input);

   end;
exception
   when Crab_Compression.Compression_Error =>
      Put_Line (Stderr, "crab: compression error"); Exit_Code (3);
   when E : others =>
      Put_Line (Stderr, "crab: " & Exception_Message (E)); Exit_Code (1);
end Crab;
```

**Constraints:** `crab.adb` is the only unit that calls `Ada.Command_Line` or
`Ada.Text_IO` for stderr diagnostic output. Application packages do not perform I/O
except `Crab_Output` (stdout) and `Crab_Scanner` (stderr warnings).

---

### 5.2 `Crab_Zlib` — zlib Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Zlib` |
| **Type** | Package (C binding) |
| **Purpose** | Provide `Compress` and `Compress_Bound` subprograms backed by libz. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Zlib_Error` | Exception | Raised when `compress2` returns non-zero |
| `Compress (Source, Level)` | Function → Natural | Compressed size in bytes |
| `Compress_Bound (Source_Len)` | Function → Natural | Maximum possible compressed size |

**Data Elements:**

| Name | Type | Role |
|---|---|---|
| `Source` (param) | `String` | Data to compress |
| `Level` (param) | `Integer` | Compression level (−1, 0, 1–9) |
| Return value | `Natural` | Compressed byte count |

**Logic:**

```
function Compress (Source : String; Level : Integer) return Natural is
   Src_Len  : constant C.unsigned_long := C.unsigned_long (Source'Length);
   Dst_Max  : constant C.unsigned_long := Compress_Bound (Source'Length);
   Dst_Buf  : Byte_Array (1 .. Natural (Dst_Max));
   Dst_Len  : aliased C.unsigned_long := Dst_Max;
   Result   : C.int;
begin
   Result := c_compress2
     (Dst_Buf'Address, Dst_Len'Access,
      Source'Address, Src_Len,
      C.int (Level));
   if Result /= Z_OK then
      raise Zlib_Error;
   end if;
   return Natural (Dst_Len);
end Compress;
```

Where:
- `c_compress2` is imported from libz with `External_Name => "compress2"`
- `Z_OK` is the constant `0` (from zlib.h)
- `Byte_Array` is `array (Natural range <>) of Interfaces.C.unsigned_char`
- The `Source'Address` cast relies on Ada `String` being a contiguous byte array
  — this is true for GNAT on x86_64

**Constraints:** Only the `compress2`/`compressBound` API of zlib is used.
Streaming (`deflateInit`/`deflate`/`deflateEnd`) is not needed for our use case.

---

### 5.3 `Crab_LZ4` — LZ4 Binding

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_LZ4` |
| **Type** | Package (C binding) |
| **Purpose** | Provide `Compress` and `Compress_Bound` subprograms backed by liblz4. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `LZ4_Error` | Exception | Raised when `LZ4_compress_default` returns 0 |
| `Compress (Source, Acceleration)` | Function → Natural | Compressed size in bytes |
| `Compress_Bound (Input_Size)` | Function → Natural | Maximum possible compressed size |

**Logic:**

```
function Compress (Source : String; Acceleration : Integer) return Natural is
   Dst_Cap  : constant C.int := C.int (Compress_Bound (Source'Length));
   Dst_Buf  : Byte_Array (1 .. Natural (Dst_Cap));
   Src_Size : constant C.int := C.int (Source'Length);
   Result   : C.int;
begin
   Result := LZ4_compress_default
     (Source'Address, Dst_Buf'Address, Src_Size, Dst_Cap);
   if Result <= 0 then
      raise LZ4_Error;
   end if;
   return Natural (Result);
end Compress;
```

Where `LZ4_compress_default` is imported from liblz4 with the same name.

**Constraints:** The acceleration parameter range is 1–65537 per the LZ4
documentation. Values outside this range may produce undefined behavior; the
argument parser validates the range before passing it here.

---

### 5.4 `Crab_Fnmatch` — POSIX fnmatch Binding

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
| `Match (Pattern, String, Flags)` | Function → Boolean | True if `String` matches `Pattern` per `fnmatch` |

**Logic:**

```ada
function Match (Pattern, Str : String; Flags : C.int := 0) return Boolean is
   Result : constant C.int := c_fnmatch
     (Pattern'Address, Str'Address, Flags);
begin
   return Result = 0;
end Match;
```

Where `c_fnmatch` is imported from libc with `External_Name => "fnmatch"`.

**Constraints:** `FNM_PATHNAME` is not used since matching is against filename
basenames only (no path separators). The `FNM_CASEFOLD` flag is GNU-specific but
available on all Linux targets.

---

### 5.5 `Crab_Compression` — Compression Abstraction

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Compression` |
| **Type** | Package (abstraction) |
| **Purpose** | Provide a uniform compression interface dispatching to DEFLATE or LZ4. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Algorithm` | Enumeration | `(Deflate, LZ4)` |
| `Compression_Error` | Exception | Propagated from backend errors |
| `Compress (Algo, Source, Level)` | Function → Natural | Compressed size |
| `Level_Default (Algo)` | Function → Integer | Default compression level |
| `Level_Min (Algo)` | Function → Integer | Minimum valid level |
| `Level_Max (Algo)` | Function → Integer | Maximum valid level |

**Logic — Dispatch:**

```
function Compress (...) return Natural is
begin
   case Algo is
      when Deflate =>
         return Crab_Zlib.Compress (Source, Level);
      when LZ4 =>
         return Crab_LZ4.Compress (Source, Level);
   end case;
end Compress;
```

**Level defaults:**

| Algorithm | Default | Min | Max |
|---|---|---|---|
| Deflate | 6 | −1 | 9 |
| LZ4 | 1 | 1 | 65537 |

**[Rationale]** The abstraction layer localizes algorithm dispatch so that adding
a new compression backend in the future requires changes to only this package and
the new binding — no changes to `Crab_Scorer` or `crab.adb`.

---

### 5.6 `Crab_Fold` — Case Folding

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
| `Matches_Any (List, Name, Ignore_Case)` | Function → Boolean | True if `Name` matches any pattern in `List` |
| `Is_Empty (List)` | Function → Boolean | True if list contains no patterns |

**Logic — Matches_Any:**

```
function Matches_Any (...) return Boolean is
   Flags : constant C.int :=
     (if Ignore_Case then Crab_Fnmatch.FNM_CASEFOLD else 0);
begin
   for P of List loop
      if Crab_Fnmatch.Match (P, Name, Flags) then
         return True;
      end if;
   end loop;
   return False;
end Matches_Any;
```

**Include/Exclude Logic** (called by `Crab_Scanner`):

```
function Should_Process
  (Name         : String;
   Include_Pats : Pattern_List;
   Exclude_Pats : Pattern_List;
   Ignore_Case  : Boolean) return Boolean
is
begin
   -- Step 1: check excludes (excludes override)
   if not Is_Empty (Exclude_Pats)
     and then Matches_Any (Exclude_Pats, Name, Ignore_Case)
   then
      return False;
   end if;
   -- Step 2: check includes
   if Is_Empty (Include_Pats) then
      return True;  -- no includes = include all
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
| **Purpose** | Walk directory trees, filter by globs and depth, collect file list. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `File_Entry` | Record | `(Path : Unbounded_String; Byte_Size : File_Size)` |
| `File_Lists` | Vector package | `Indefinite_Vectors` of `File_Entry` |
| `Scan (...)` | Function → `File_Lists.Vector` | Traverse and return file list |

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

**Logic — depth-first traversal:**

```
function Scan (...) return File_Lists.Vector is
   Files   : File_Lists.Vector;
   Visited : String_Sets.Set;  -- canonical paths, for cycle detection
   
   procedure Walk (Dir_Path : String; Depth : Natural) is
      Canonical : constant String :=
        GNAT.OS_Lib.Normalize_Pathname
          (Name          => Dir_Path,
           Resolve_Links => True);
   begin
      -- Cycle detection
      if Visited.Contains (Canonical) then
         Warnings.Append
           ("crab: warning: symlink cycle detected at " & Dir_Path);
         return;
      end if;
      Visited.Insert (Canonical);
      
      -- Depth limit
      if Max_Depth /= Natural'Last and then Depth > Max_Depth then
         return;
      end if;
      
      -- List directory
      declare
         Filter : constant Ada.Directories.Filter_Type :=
           (Ordinary_File => True, Directory => True, Special_File => False);
         Search : Ada.Directories.Search_Type;
      begin
         Ada.Directories.Start_Search
           (Search, Directory => Dir_Path, Pattern => "", Filter => Filter);
         
         -- Collect entries, skip "." and ".."
         Entries : String_Vector;
         while More_Entries (Search) loop
            declare
               Entry : constant Directory_Entry_Type := To_Directory_Entry (Search);
               Name  : constant String := Simple_Name (Entry);
            begin
               if Name /= "." and Name /= ".." then
                  Entries.Append (Full_Name (Entry));
               end if;
            end;
         end loop;
         End_Search (Search);
      end;
      
      -- Sort entries lexicographically (byte order)
      Sort (Entries);
      
      -- Process files first
      for E of Entries loop
         if Kind (E) = Ordinary_File then
            if Should_Process (Simple_Name (E), Include_Pats, Exclude_Pats, Ignore_Case) then
               Files.Append ((Path => To_Unbounded (E), Byte_Size => Size (E)));
            end if;
         end if;
      end loop;
      
      -- Then recursively descend into directories
      if Recursive then
         for E of Entries loop
            if Kind (E) = Directory then
               Walk (E, Depth + 1);
            end if;
         end loop;
      end if;
   exception
      when E : others =>
         Warnings.Append
           ("crab: warning: cannot access " & Dir_Path
            & ": " & Exception_Message (E));
   end Walk;
   
begin
   for Root of Root_Paths loop
      declare
         Kind : constant Ada.Directories.File_Kind :=
           --  Resolve symlinks for the root path itself
           Ada.Directories.Kind (Root);
      begin
         if Kind = Ada.Directories.Ordinary_File then
            if Should_Process (Ada.Directories.Simple_Name (Root),
                               Include_Pats, Exclude_Pats, Ignore_Case)
            then
               Files.Append
                 ((Path      => To_Unbounded (Ada.Directories.Full_Name (Root)),
                   Byte_Size => Ada.Directories.Size (Root)));
            end if;
         elsif Kind = Ada.Directories.Directory then
            Walk (Root, 0);
         end if;
      exception
         when E : others =>
            Warnings.Append
              ("crab: warning: cannot access " & Root
               & ": " & Exception_Message (E));
      end;
   end loop;
   
   -- Sort all collected files by path for deterministic order
   Sort_By_Path (Files);
   return Files;
end Scan;
```

**Constraints and Assumptions:**
- Uses `Ada.Directories` which follows symlinks by default (REQ-044).
- `GNAT.OS_Lib.Normalize_Pathname` with `Resolve_Links => True` resolves all
  symlinks in a path. This is GNAT-specific but available on all Linux targets.
- `Sort_By_Path` uses `Ada.Containers.Generic_Array_Sort` or manual insertion
  sort by lexicographic byte comparison of the `Path` field.
- The `String_Sets` package is `Ada.Containers.Indefinite_Hashed_Sets` keyed
  by `String` with `Ada.Strings.Hash`.

**[Rationale]** Tracking canonical paths rather than inode/device pairs is simpler
and requires no additional C bindings. The `Normalize_Pathname` function resolves
all symlinks, making two different symlink paths pointing to the same directory
resolve to the same canonical string.

---

### 5.9 `Crab_Chunker` — Chunk Extraction

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Chunker` |
| **Type** | Package (algorithm) |
| **Purpose** | Extract fixed-size overlapping chunks from a byte buffer. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Chunk` | Record | `(Data : Unbounded_String; Offset : Natural)` |
| `Chunk_Vectors` | Vector package | `Indefinite_Vectors` of `Chunk` |
| `Chunk_All (Input, Size, Overlap)` | Function → `Chunk_Vectors.Vector` | Extract all chunks |

**Logic:**

```
function Chunk_All
  (Input   : String;
   Size    : Positive;
   Overlap : Natural) return Chunk_Vectors.Vector
is
   Step  : constant Natural :=
     Natural'Max (1, (Size * (100 - Overlap)) / 100);
   Start : Natural := Input'First;
   Result : Chunk_Vectors.Vector;
begin
   while Start <= Input'Last loop
      declare
         End_Pos : constant Natural :=
           Natural'Min (Start + Size - 1, Input'Last);
         Chunk_Data : constant String := Input (Start .. End_Pos);
      begin
         Result.Append
           ((Data   => To_Unbounded_String (Chunk_Data),
             Offset => Start - Input'First));
      end;
      exit when Start + Step > Input'Last;  -- avoid infinite loop on last chunk
      Start := Start + Step;
   end loop;
   return Result;
end Chunk_All;
```

**Edge cases:**
- `Step` is clamped to minimum 1 to avoid infinite loops with very small chunk
  sizes and high overlap.
- The last chunk may be shorter than `Size` (REQ-013).
- Returns empty vector if `Input` is empty (REQ-014 — caller checks before
  invoking).
- Overlap = 0 produces adjacent chunks (`Step = Size`).
- Overlap = 80, Size = 100 produces `Step = 20`.

---

### 5.10 `Crab_Scorer` — MI Scoring

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Scorer` |
| **Type** | Package (algorithm) |
| **Purpose** | Compute MI‑approx scores for all chunks against a query. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Scored_Chunk` | Record | `(Offset : Natural; Data : Unbounded_String; Score : Integer)` |
| `Scored_Chunk_Vectors` | Vector package | `Indefinite_Vectors` of `Scored_Chunk` |
| `Score_All (Query, Chunks, Algo, Level)` | Function → `Scored_Chunk_Vectors.Vector` | Score all chunks |

**Logic:**

```
function Score_All
  (Query  : String;
   Chunks : Crab_Chunker.Chunk_Vectors.Vector;
   Algo   : Crab_Compression.Algorithm;
   Level  : Integer) return Scored_Chunk_Vectors.Vector
is
   -- Cache query compressed size (REQ-022)
   Query_CS : constant Natural :=
     Crab_Compression.Compress (Algo, Query, Level);
   Result : Scored_Chunk_Vectors.Vector;
begin
   for C of Chunks loop
      declare
         Chunk_Str : constant String := To_String (C.Data);
         Chunk_CS  : constant Natural :=
           Crab_Compression.Compress (Algo, Chunk_Str, Level);
         -- Concatenate query + chunk for joint compression (REQ-023)
         Joint_Str : constant String := Query & Chunk_Str;
         Joint_CS  : constant Natural :=
           Crab_Compression.Compress (Algo, Joint_Str, Level);
         Score     : constant Integer :=
           Integer (Query_CS) + Integer (Chunk_CS) - Integer (Joint_CS);
      begin
         Result.Append
           ((Offset => C.Offset,
             Data   => C.Data,
             Score  => Score));
      end;
   end loop;
   return Result;
end Score_All;
```

**Note on `&` operator:** Ada's `&` on `String` produces a new heap-allocated
`String`. For large inputs this may be a performance concern. An optimization
for future builds would be to use a stack-allocated buffer and copy into it.

**[Rationale]** Query is compressed once (REQ-022). The concatenation order is
always `Query & Chunk` (REQ-023). Scores are `Integer` to accommodate negative
values (REQ-025). The `Data` field retains the chunk's folded data for output
(in case the caller needs folded content), though `crab.adb` will use the
original input for actual output (REQ-030).

---

### 5.11 `Crab_Output` — Output Formatting

| Attribute | Value |
|---|---|
| **Identifier** | `Crab_Output` |
| **Type** | Package (I/O) |
| **Purpose** | Sort scored chunks, select top-k, format and print. |

**Interfaces:**

| Item | Kind | Description |
|---|---|---|
| `Print_Top_K (...)` | Procedure | Sort, select, print |

**Parameters:**

```
procedure Print_Top_K
  (Scored         : Crab_Scorer.Scored_Chunk_Vectors.Vector;
   K              : Positive;
   Invert         : Boolean;
   File_Map       : File_Span_Vectors.Vector;
   Original_Input : String);
```

**Logic:**

```
procedure Print_Top_K (...) is
   -- Copy scored chunks to an array for sorting
   Arr : Scored_Chunk_Array (1 .. Natural (Scored.Length));
   ...
   -- Sort: descending by Score, ties by Offset (ascending)
   -- If Invert: ascending by Score, ties by Offset (ascending)
   
   -- Take first K (or all if fewer)
   Limit : constant Positive := Positive'Min (K, Scored.Length);
   
   -- Print each selected chunk
   for Rank in 1 .. Limit loop
      Item : Scored_Chunk renames Arr (Rank);
      FS   : constant File_Span := Find_File_Span (File_Map, Item.Offset);
      File_Offset : constant Natural := Item.Offset - FS.Start_Offset;
      Chunk_Data  : constant String :=
        Original_Input
          (Original_Input'First + Item.Offset
           .. Original_Input'First + Item.Offset
              + Length (Item.Data) - 1);
   begin
      -- Header (REQ-029)
      Put_Line ("## chunk=" & Image (Rank)
                & " score=" & Image (Item.Score)
                & " file=" & To_String (FS.Path)
                & " offset=" & Image (File_Offset));
      -- Content (REQ-030) — raw bytes
      Put (Chunk_Data);
      -- Separator (REQ-031) — blank line between chunks
      if Rank < Limit then
         New_Line;
         New_Line;
      end if;
   end loop;
end Print_Top_K;
```

**Sort comparison function:**

```
function Less (A, B : Scored_Chunk) return Boolean is
begin
   if A.Score /= B.Score then
      if Invert then
         return A.Score < B.Score;   -- ascending for inversion
      else
         return A.Score > B.Score;   -- descending for normal
      end if;
   else
      return A.Offset < B.Offset;    -- tie-break by offset (REQ-032)
   end if;
end Less;
```

**`Find_File_Span` helper:**

```
function Find_File_Span
  (Map    : File_Span_Vectors.Vector;
   Offset : Natural) return File_Span
is
begin
   for FS of Map loop
      if Offset >= FS.Start_Offset
        and then Offset < FS.Start_Offset + FS.Length
      then
         return FS;
      end if;
   end loop;
   -- Should never be reached if File_Map is built correctly
   raise Program_Error with "chunk offset not in any file span";
end Find_File_Span;
```

**Constraints:**
- `Original_Input` is the unfolded input string. Chunks reference positions in
  the folded input, but the fold operation is byte-for-byte (only A–Z change),
  so the chunk byte range in the original input is identical.
- The sort uses `Ada.Containers.Generic_Array_Sort` with the `Less` function
  for efficient O(N log N) sorting.
- `Image` converts integers to decimal strings (format: no leading space for
  positive values).

---

## 6. Requirements Traceability

### 6.1 Requirement-to-Unit Map

| Requirement | Implementing Unit(s) | Detail |
|---|---|---|
| REQ-001 | `crab.adb` | `Parse_Args` handles all flags |
| REQ-002 | `crab.adb` | `-h`/`--help` detection in `Parse_Args`; `Print_Usage` |
| REQ-003 | `crab.adb` | `--version` detection; prints `Crab_Config.Crate_Version` |
| REQ-004 | `crab.adb` | Query validation in `Parse_Args` |
| REQ-047 | `Crab_Fold`, `crab.adb` | `Fold` subprogram; applied to Query and Input when `-i` |
| REQ-005 | `crab.adb` | `Read_From_Files` path |
| REQ-006 | `crab.adb` | `Read_From_Stdin` path |
| REQ-007 | `crab.adb` | Byte-oriented reads; no encoding conversion |
| REQ-008 | `crab.adb` | `Read_From_Files` exception handler → exit 2 |
| REQ-041 | `Crab_Scanner`, `crab.adb` | `-r` flag → `Scan` call; directory-without-`-r` → error |
| REQ-042 | `Crab_Scanner` | `Walk` descends all subdirs; skips `.` and `..` |
| REQ-043 | `Crab_Scanner` | `Sort (Entries)` per directory; final `Sort_By_Path` |
| REQ-044 | `Crab_Scanner` | `Ada.Directories` follows symlinks; `Normalize_Pathname` for roots |
| REQ-045 | `Crab_Scanner` | Exception handler in `Walk` → warning, continue |
| REQ-046 | `Crab_Scanner` + `crab.adb` | Empty `Files` vector → exit 4 |
| REQ-049 | `Crab_Glob`, `Crab_Scanner` | `Include_Pats` → `Should_Process` |
| REQ-050 | `Crab_Glob`, `Crab_Scanner` | `Exclude_Pats` → `Should_Process` (excludes override) |
| REQ-051 | `Crab_Fnmatch`, `Crab_Glob` | `fnmatch()` via `Match` |
| REQ-052 | `Crab_Scanner` | Globs only applied in `Scan`; `Read_From_Files` bypasses |
| REQ-053 | `Crab_Scanner` | `Max_Depth` parameter in `Walk` |
| REQ-054 | `crab.adb`, `Crab_Scanner` | `Max_Depth := Natural'Last` default (= unlimited) |
| REQ-009 | `Crab_Chunker` | `Chunk_All` sliding window |
| REQ-010 | `crab.adb`, `Crab_Chunker` | `--chunk-size` validated, passed as `Size` |
| REQ-011 | `Crab_Chunker` | `Step = Size × (100−Overlap) / 100` |
| REQ-012 | `crab.adb` | `Parse_Args` validates [0,99] |
| REQ-013 | `Crab_Chunker` | Last chunk `End_Pos = min(Start+Size-1, Last)` |
| REQ-014 | `crab.adb` | Empty input check before `Chunk_All` |
| REQ-015 | `Crab_Compression`, `crab.adb` | `Algorithm` enum; `Parse_Args` validates |
| REQ-016 | `Crab_Zlib` | `c_compress2` import from libz |
| REQ-017 | `Crab_LZ4` | `LZ4_compress_default` import from liblz4 |
| REQ-018 | `crab.adb`, `Crab_Compression` | `Level` parameter; default from `Level_Default` |
| REQ-019 | `crab.adb` | `Parse_Args` validates range per algorithm |
| REQ-020 | `Crab_Zlib`, `Crab_LZ4` | Return `Natural` compressed byte count |
| REQ-021 | `Crab_Scorer` | `Score = Q_CS + C_CS − Joint_CS` |
| REQ-022 | `Crab_Scorer` | `Query_CS` computed once before loop |
| REQ-023 | `Crab_Scorer` | `Joint_Str := Query & Chunk_Str` |
| REQ-024 | `Crab_Scorer` | Loop over all chunks |
| REQ-025 | `Crab_Scorer`, `Crab_Output` | `Score : Integer` (signed) |
| REQ-026 | `Crab_Output` | `Print_Top_K` selects top/bottom `K` |
| REQ-027 | `crab.adb`, `Crab_Output` | `K := Positive'Min (Top_K, Length)` |
| REQ-028 | `Crab_Output` | Sort order; descending (or ascending with `Invert`) |
| REQ-029 | `Crab_Output` | Header format `## chunk=N score=S file=P offset=O` |
| REQ-030 | `Crab_Output`, `crab.adb` | `Original_Input` slice; raw `Put` |
| REQ-031 | `Crab_Output` | Blank line between chunks |
| REQ-032 | `Crab_Output` | `Less` tie-break by `Offset` |
| REQ-055 | `Crab_Output`, `crab.adb` | `Invert` parameter; sort ascending when true |
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
| `Ada.Text_IO` | `crab.adb` — stderr; `Crab_Output` — stdout |
| `Ada.Strings.Unbounded` | Multiple — dynamic string storage |
| `Ada.Containers.Indefinite_Vectors` | `Crab_Scanner`, `Crab_Chunker`, `Crab_Scorer`, `Crab_Output`, `crab.adb` |
| `Ada.Containers.Indefinite_Hashed_Sets` | `Crab_Scanner` — cycle detection |
| `Ada.Containers.Generic_Array_Sort` | `Crab_Scanner` — entry sorting; `Crab_Output` — score sorting |
| `Ada.Directories` | `Crab_Scanner` — directory traversal |
| `Interfaces.C` | `Crab_Zlib`, `Crab_LZ4`, `Crab_Fnmatch` — C type definitions |
| `GNAT.OS_Lib` | `Crab_Scanner` — `Normalize_Pathname` for cycle detection |
| `System.Address` | Binding packages — C buffer passing |
| `Ada.Exceptions` | `crab.adb`, `Crab_Scanner` — exception messages |

### 7.2 Build Configuration

The GPR project file `crab.gpr` must be updated to:
- Add `-lz` linker switch for libz
- Add `-llz4` linker switch for liblz4
- Add `Source_Dirs` entry for any new source subdirectories (not needed;
  all packages in `src/`)
- Install `share/man/man1/crab.1` via the existing `Install` artifacts rule

### 7.3 Design Decisions Requiring Client Confirmation

| Decision | Rationale | Status |
|---|---|---|
| `--chunk-size` has no default | User must explicitly choose; no universally correct size | Confirmed (client accepted `--chunk-size`) |
| Chunk step minimum = 1 byte | Prevents infinite loop at very small chunk sizes + high overlap | Design decision |
| Gnulib `FNM_CASEFOLD` flag | Available on all Linux targets; avoids hand-rolling case-insensitive glob | Design decision |
| Canonical path cycle detection via `GNAT.OS_Lib.Normalize_Pathname` | Simpler than inode tracking; no additional C binding required | Design decision |

### 7.4 Open for Future Builds

- Streaming/chunked I/O to reduce memory pressure (R3 mitigation)
- Additional compression backends (bzip2, zstd, brotli)
- Unicode case folding (currently ASCII-only)
- Threaded compression for parallelism on multi-chunk scoring
- Output mode: JSON, CSV, or machine-parseable formats
- `--label` for stdin naming (deferred from feature recommendation)
- `-l` (files-with-results), `-c` (count), `-q` (quiet) flags
