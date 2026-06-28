# Project Plan â Crab

**Project:** Crab â Compression-based mutual-information grep  
**Date:** 2026-06-18  
**Version:** 1.0-draft  
**System type:** Software-only  

---

## 1. Overview

### 1.1 Purpose

Crab is a grep-like CLI tool that selects the *k* most-similar text chunks from files or
stdin, compared against an input query string. Similarity is measured by **mutual
information** approximated via a compression-based distance (the information-distance /
Normalized Compression Distance family).

### 1.2 Scope

- A single CLI executable (`crab`) installable via Alire.
- Accepts a query string, search files, directory trees with glob filtering (or stdin), compression algorithm choice, compression
  level, chunk overlap percentage, the number of chunks, case insensitivity, inversion, and file-filtering globs to return (*k*).
- Outputs the *k* chunks with the highest mutual information to the query, in descending
  order.

### 1.3 Relationship to other plans or agreements

This is a new, standalone project with no external dependencies beyond system libraries
(zlib, liblz4, liblzma) and the GNAT Ada toolchain.

---

## 2. Referenced Documents

- MIL-STD-498 (5 December 1994) â process framework reference.
- `requirements/requirements-spec.md` â Software Requirements Specification.
- `design/design-description.md` â Software Design Description.
- `tests/test-plan.md` â Test Plan.

---

## 3. Overview of Required Work

One software component will be developed:

| Component | Description |
|---|---|
| `crab` | CLI executable. Thin Ada bindings to `libz`, `liblz4`, and `liblzma`; directory traversal; chunking engine; MI scoring engine; result output. All integrated into a single executable. |

The bindings are internal (not published as separate crates) but are designed as distinct
Ada packages for clarity and testability.

---

## 4. Plans for Each Active Activity

### 4.1 Development Process

**Lifecycle model:** Waterfall-with-iteration â requirements and design are completed and
reviewed before implementation, but any phase may loop back if deficiencies are found during
evaluation.

**Build strategy:** Single build. All requirements are implemented in one cycle.

**Build objectives:**
1. Correct mutual-information scoring for DEFLATE (zlib), LZ4, LZW, and LZMA backends.
2. Correct chunk selection and output for the top-*k* criterion.
3. Correct sliding-window chunking (byte and line modes) with configurable overlap.
4. Compression-level tunability.
5. Recursive directory traversal with grep-like semantics.
6. File filtering with --include/--exclude globs.
7. Max-depth limiting for traversal.
8. Case-insensitive search with -i.
9. Inversion mode (-v) for least-similar chunk output.
10. Unit testing with AUnit in nested Alire crate.
11. Man page installation.
12. Alire-crate packaging (`alr install` works).
13. LZMA dictionary-size tunability via --dict-size / -D flag.

### 4.2 General Requirements

**Development methods:** Structured analysis and design. Requirements documented in
`requirements/`, design in `design/`. Source code comments reference requirement identifiers
for traceability.

**Standards:**
- Requirements: structured prose with unique identifiers (REQ-xxx).
- Design: component decomposition with Ada package/unit mapping.
- Code: Ada 2012 with GNAT style switches (`-gnaty*` per `crab_config.gpr`).
- Test cases: specified in `tests/test-description.md`, results in `tests/test-report.md`.

**Reusable software:** None (no pre-existing components).

**Critical requirements:** None designated by the client beyond basic correctness.

**Rationale recording:** Key design decisions recorded inline in `design/design-description.md`
with the `[Rationale]` tag.

### 4.3 Planning & Oversight

**Planning approach:** This document is the governing plan. Updates proposed by the developer
after each phase review; accepted by the client.

**Review intervals:** Reviews proposed at end of requirements analysis, design, and testing
phases. At minimum, one joint review after implementation completes.

**Update procedures:** Plan changes are committed to version control with a log entry. Changes
that alter scope, schedule, or resource needs are flagged to the client before adoption.

### 4.4 Development Environment

**Languages:** Ada 2012/2022 (GNAT 13.3.0). C headers for binding declarations only (no C
compilation required â `Import` + linker flags).

**Build toolchain:** Alire (`alr build` invokes `gprbuild`). GPR project file `crab.gpr`.

**Test tools:** AUnit (Alire crate `aunit`) for unit testing. Shell scripts for integration
and acceptance testing.

**Project library:** Git repository at `~/Projects/crab`. Commits at logical checkpoints.

**Supported platforms:** Linux x86_64 (primary). Ubuntu 24.04 development host.

### 4.5 System Requirements Analysis â NOT ACTIVE

Software-only system: system-level requirements are identical to component requirements.
No separate system-level activity.

### 4.6 System Design â NOT ACTIVE

Same rationale as Â§4.5.

### 4.7 Software Requirements Analysis

**Approach:** Requirements derived from the project brief (user's initial description).
Documented in `requirements/requirements-spec.md`. Each requirement receives a unique
identifier and a verification method.

**Methods:** Interview-style elicitation (the user provides the brief; the developer
formalises and seeks confirmation).

**Traceability strategy:** Requirements-map in the Requirements Spec (Â§5) traces each
requirement to its source (project brief objective). The Design Description traces
requirements to implementation units.

### 4.8 Software Design

**Approach:** Top-down decomposition. The component is decomposed into Ada packages.
Design documented in `design/design-description.md`.

**Design methods:** Functional decomposition. Module interfaces defined via Ada package
specifications. Data flow described in terms of package dependencies.

**Standards for design representation:** Ada package specifications serve as the canonical
interface design. Architectural text descriptions explain the decomposition rationale.

### 4.9 Implementation & Unit Testing

**Coding standards:** GNAT style switches enforce layout, casing, and formatting (see
`crab_config.gpr`). Additional conventions:
- One Ada package per file, named after the package.
- All subprograms explicitly scoped.
- No use of `Unchecked_Conversion` or `System.Address` arithmetic unless required by C
  bindings and confined to binding package bodies.  `Crab_Scorer` uses
  `Unchecked_Conversion` in its body to cast opaque `Stream_Handle` values to
  backend-specific stream access types â this is the sole exception and is
  confined to the body.

**Unit test approach:** AUnit test harness. Each Ada package with algorithmic logic gets a
corresponding test package. C-binding packages are tested via integration tests (they are
thin wrappers with no logic).

**Test crate structure:** The tests reside in a nested Alire crate at `tests/` with
its own `alire.toml` depending on `crab` (via `path = ".."`) and `aunit`.  The test
harness is a separate executable built from `tests/src/`; `alr build` in the `tests/`
directory compiles it.  Each application package `Crab_Foo` has a corresponding test
package `Crab_Foo_Tests` in `tests/src/`.

### 4.10 Integration & Testing

**Integration sequence:** Bottom-up. Bindings â compression abstraction â chunking engine â
MI scorer â CLI main â end-to-end.

**Integration test approach:** Incremental: after each new package integrates, run the full
test suite to detect regressions. Final integration test exercises the complete CLI.

### 4.11 Acceptance Testing

**Test approach:** The Test Description specifies test cases that verify every requirement.
Tests are executed and results recorded in the Test Report.

**Test environment:** Same as development environment. No special hardware.

**Independence approach:** Testing performed by the developer. The Independence Limitation
(Mandatory Constraints Â§MC-1) is noted. The client reviews test results.

### 4.12 System Acceptance Testing â NOT ACTIVE

Software-only system; see Â§4.11.

### 4.13 Prepare for Use

**Deployment approach:** Alire crate publication. Users run `alr get crab && cd crab && alr build`.
A man page (`crab.1`) is included in `share/man/man1/` and an
agent skill (`share/agents/skills/crab/SKILL.md`) provides AI assistants
with semantic-search guidance; both are installed by the Alire build process via the GPR
`Install` package.
System dependencies (libz, liblz4, liblzma) must be installed on the target system. An `alire.toml`
external dependency declaration will make this discoverable.

**Training plan:** None. The tool is a CLI; `crab --help` provides usage information.

### 4.14 Prepare for Handover â NOT ACTIVE

Sole maintainer (client). No transition to a separate team.

### 4.15 Configuration Management

**Levels of control:**
- Author control: working files not yet committed.
- Project-level control: committed to git.
- Client control: artifacts reviewed and accepted by the client (tagged in git).

**Identification scheme:** Semantic versioning (`major.minor.patch`). Git tags for releases.

**Change procedures:** Changes to client-controlled artifacts require a problem/change report
and client agreement.

**Version control tooling:** Git.

**Status accounting:** Git log. Problem/change log in `plan/problem-log.md`.

**Audit support:** Configuration audits not required by the client. Standard problem/change
log suffices.

### 4.16 Product Evaluation

**Products to be evaluated:** Requirements Spec, Design Description, source code, Test
Description, Test Report, executable.

**Criteria:** From `documents.md` Part 2 (Universal Criteria + per-product-type criteria).

**Evaluation timing:** At completion of each phase; final evaluation before presenting to
the client.

### 4.17 Quality Assurance

**QA activities:** Product evaluation applied to every work product before client review.

**Records:** Evaluation results recorded inline in each document or in the component
development log.

**Independence approach:** Developer performs QA. Independence Limitation noted.

### 4.18 Corrective Action

**Problem tracking:** `plan/problem-log.md` â a running log of problems discovered during
development and evaluation.

**Category/priority scheme:** Per `documents.md` Part 3.

**Trend analysis:** Reviewed at each joint review.

### 4.19 Joint Reviews

**Planned reviews:**
1. Requirements review â after Requirements Spec is complete.
2. Design review â after Design Description is complete.
3. Test results review â after acceptance testing.

**Preparation:** Developer distributes the artifact(s) ahead of each review. Client provides
feedback, captured as action items or problem reports.

### 4.20 Risk Management

**Risk identification:** Ongoing. Initial risks in the Risk Register (Â§7).

**Risk register structure:** Risk ID, description, likelihood, impact, mitigation, owner.

**Update cadence:** Reviewed at each joint review.

### 4.21 Management Indicators

| Indicator | Data source |
|---|---|
| Requirements volatility | Git diff of `requirements/` |
| Component progress | Component development log (`sdfs/crab-sdf.md`) |
| Open problems | `plan/problem-log.md` |
| Milestone status | This plan's schedules (Â§5) |
| Scope changes | Git log of `plan/project-plan.md` changes |
| Test results trend | `tests/test-report.md` |

**Reporting mechanism:** Summary at each joint review.

### 4.22 Security & Privacy â NOT ACTIVE

No security or privacy requirements identified by the client.

### 4.23 Process Improvement

**Retrospective cadence:** After the single build completes, a brief retrospective notes
lessons learned.

**Improvement proposal process:** Proposed changes to the Project Plan presented to client.

---

## 5. Schedules

| Milestone | Planned completion | Dependencies |
|---|---|---|
| Project Plan acknowledged | 2026-06-18 | â |
| Requirements Spec complete | 2026-06-19 | Project Plan |
| Design Description complete | 2026-06-20 | Requirements Spec |
| Implementation & unit test | 2026-06-21 | Design Description |
| Integration & acceptance test | 2026-06-22 | Implementation |
| Client review & handover | 2026-06-23 | Testing |

*Note: These are internal planning estimates for a compact tool. Dates will be adjusted
as work progresses.*

### Activity Dependencies

```
Project Plan â Requirements Spec â Design Description â Implementation
                                                              â
                                              Unit Test âââââ
                                                              â
                                              Integration Test
                                                              â
                                              Acceptance Test â Test Report â Client Review
```

---

## 6. Resources

| Resource | Details |
|---|---|
| Development host | Linux x86_64 (Ubuntu 24.04) |
| Ada compiler | GNAT 13.3.0 (via `gnat-13` package) |
| Build system | Alire + gprbuild |
| System libraries | `libz` (zlib1g-dev), `liblz4` (liblz4-dev), `liblzma` (liblzma-dev) |
| Test framework | AUnit (Alire crate `aunit`) |
| Version control | Git |

---

## 7. Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | LZ4 C binding has ABI mismatch (e.g., `int` size on different platforms) | Low | Moderate | Use `Interfaces.C.int` for C `int` parameters; test on target platform |
| R2 | Compression-level tuning may produce counterintuitive results at extremes | Low | Minor | Document level range; test boundary values |
| R3 | Large input files consume excessive memory | Medium | Moderate | Implement streaming/chunked I/O; document memory expectations |
| R4 | Large directory trees with many files cause slow glob matching | Low | Minor | fnmatch() is a system call and fast; risk is residual â document expected file counts for `-r` usage |
| R5 | Overlap percentage produces degenerate chunks (e.g., 100% overlap = infinite loop) | Low | Minor | Validate parameter range; reject nonsensical values |
| R6 | Symlink cycle during recursive traversal causes infinite loop | Low | Serious | Detect symlink cycles (track visited inodes); set a maximum traversal depth as safety limit |

---

## 8. Notes

### 8.1 Tailoring Decisions

| Activity | Default | Decision | Rationale |
|---|---|---|---|
| System requirements analysis (Â§5.3) | Conditional | NOT ACTIVE | Software-only system |
| System design (Â§5.4) | Conditional | NOT ACTIVE | Software-only system |
| HW/SW integration testing (Â§5.10) | Off | NOT ACTIVE | No hardware |
| System acceptance testing (Â§5.11) | Conditional | NOT ACTIVE | Software-only; covered by component acceptance |
| Prepare for use (Â§5.12) | Conditional | ACTIVE â limited | Alire crate publication; no user training |
| Prepare for handover (Â§5.13) | Conditional | NOT ACTIVE | Sole maintainer |
| Security & privacy (Â§5.19.3) | Conditional | NOT ACTIVE | No security requirements |
| Witnessed acceptance testing | N/A | NOT REQUESTED | Test report sufficient |
| Configuration audits | N/A | NOT REQUESTED | Standard problem/change log suffices |

### 8.2 Shell Requirements Resolution

| # | Question | Answer |
|---|---|---|
| a | Critical requirements? | None beyond correctness |
| b | Hardware resource constraints? | None imposed; memory for large inputs is a noted risk (R3) |
| c | Permitted languages? | Ada for application; C headers for bindings |
| d | Installation at user sites? | Alire crate; no on-site installation |
| e | Maintenance transition? | Sole maintainer (client); no handover |
| f | Witnessed testing? | No; test report sufficient |
| g | Configuration audits? | No; standard problem/change log |
| h | Process security? | None required |

### 8.3 Combined Document Decisions

Requirements Spec and Interface Requirements Spec are combined into a single
`requirements/requirements-spec.md` â there are no external interfaces beyond the CLI
argument signature, which is naturally described alongside functional requirements.

Test Plan and Test Description are combined into `tests/test-description.md` â the plan
content (environment, identification, schedule) is brief enough to co-locate with the test
cases.


### 8.4 Architecture Preview (for Design Phase)

```
src/
âââ crab.adb                     -- CLI main (argument parsing, streaming
â                                --   orchestrator)
âââ crab_buffers.ads             -- Pure-Ada byte buffer type shared across
â                                --   all compression modules
âââ crab_zlib.ads                -- Streaming binding to libz (deflateInit,
â                                --   deflateSetDictionary, deflate,
â                                --   deflateReset, deflateEnd, compressBound)
âââ crab_lz4.ads                 -- Streaming binding to liblz4
â                                --   (LZ4_createStream, LZ4_loadDict,
â                                --    LZ4_compress_fast_continue,
â                                --    LZ4_resetStream_fast, LZ4_freeStream,
â                                --    LZ4_compressBound)
âââ crab_lzma.ads                -- Streaming binding to liblzma
â                                --   (lzma_easy_encoder, lzma_code,
â                                --    lzma_end)
âââ crab_lzw.ads                 -- Pure Ada LZW compression (no C types)
âââ crab_fnmatch.ads             -- Thin binding to POSIX fnmatch() via libc
âââ crab_compression.ads         -- Abstraction: backend dispatch (DEFLATE / LZ4 / LZW / LZMA)
âââ crab_fold.ads                -- ASCII case folding for --ignore-case
âââ crab_glob.ads                -- Multi-pattern include/exclude matching
âââ crab_scanner.ads             -- Directory-traversal file discovery with glob
â                                --   filtering and depth limiting
âââ crab_chunker.ads             -- Streaming sliding-window chunk iterator
âââ crab_scorer.ads              -- Stateful MI scorer (caches query
â                                --   compression; opaque backend handles)
âââ crab_topk.ads                -- Bounded binary heap: top-k chunk
                                 --   accumulation and formatted output
```

```

### Test Crate Structure (nested in `tests/`)

```
tests/
âââ alire.toml                   -- depends on crab (path = "..") + aunit
âââ crab_tests.gpr               -- GPR project for test harness
âââ src/
    âââ crab_tests.adb           -- main test harness (register all suites)
    âââ crab_chunker_tests.ads   -- tests for Crab_Chunker
    âââ crab_chunker_tests.adb
    âââ crab_compression_tests.ads  -- tests for Crab_Compression
    âââ crab_compression_tests.adb
    âââ crab_fold_tests.ads      -- tests for Crab_Fold
    âââ crab_fold_tests.adb
    âââ crab_glob_tests.ads      -- tests for Crab_Glob
    âââ crab_glob_tests.adb
    âââ crab_scorer_tests.ads    -- tests for Crab_Scorer
    âââ crab_scorer_tests.adb
    âââ crab_topk_tests.ads      -- tests for Crab_TopK
    âââ crab_topk_tests.adb
    âââ crab_scanner_tests.ads   -- integration tests for Crab_Scanner
    âââ crab_scanner_tests.adb
```
Design note: the architecture is **streaming**. Files are processed one at a
time; chunks are scored on-the-fly; only the top-*k* chunks (plus the current
working chunk) are held in memory. The bounded heap replaces the batch
sort-then-output model.
