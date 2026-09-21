# Migration specification: `<JOBNAME>`

> The **specify** artefact. Devin produces one of these per JCL job before
> writing any target code, commits it as `docs/specs/<JOBNAME>-spec.md`, and
> links it from the PR and the Jira ticket. Every statement must be traceable
> to a line in the JCL, the COBOL source, a copybook or the DDL - quote the
> paragraph / line so a reviewer can check it. Do not describe *intended*
> behaviour; describe *actual* behaviour, including defects (flag them in
> section 9 and preserve them unless the ticket says otherwise).

| Field | Value |
|-------|-------|
| Job | `<JOBNAME>` (`jcl/<JOBNAME>.jcl`) |
| Programs | `<MAIN>.cbl` (`<n>` lines), called: `<SUB>.cbl` |
| Copybooks | `<list>` |
| DB2 tables | `<schema.table>` (R/U/I/D) |
| Schedule | `<time>`, predecessors `<jobs>`, successors `<jobs>` (`schedules/nightly.txt`) |
| Return codes | `0 = ...`, `4 = ...`, `8 = ...` |
| Ticket | `MFM-<n>` |
| Author / date | Devin session `<link>`, `<yyyy-mm-dd>` |

## 1. Purpose (3 sentences max)

What the job does for the business, when it runs, and who consumes its output.

## 2. Job structure

| Step | PGM | COND | Inputs (DD) | Outputs (DD) | Local equivalent |
|------|-----|------|-------------|--------------|------------------|
| STEP010 | | | | | |
| STEP020 | | | | | |
| STEP030 | | | | | |

Include the sort keys (positions, order) and any `COND` / `IF` logic that
decides whether a step runs.

## 3. I/O contract (one row per DD name)

| DD name | Direction | Dataset / file | Record layout (copybook) | LRECL | Encoding | Sorted by | Notes |
|---------|-----------|----------------|--------------------------|-------|----------|-----------|-------|
| `SYSIN` | in | control cards | `RUNDATE=YYYYMMDD` | 80 | ASCII | - | mandatory, RC 8 if missing |
| | | | | | | | |

For each **fixed-width** layout, list the fields with offset, length, PIC and
meaning (copy from the copybook, add the meaning). For each **CSV** stand-in,
list the header row and the column formats (e.g. `DECIMAL(7,2)` printed as
`149.00`, dates as `YYYY-MM-DD`, blank for NULL).

## 4. Business rules table

One row per rule. The id must appear in the source comment; if the source has
no id, assign one here and reference the paragraph.

| Id | Paragraph(s) | Rule (precise, with arithmetic) | Inputs | Result / side effect | Example from sample data | Test assertion |
|----|--------------|----------------------------------|--------|----------------------|--------------------------|----------------|
| BR-V1 | `2200-VALIDATE-PROMO` | promo type must be P, F or B, else REJECT | `PR-PROMO-TYPE` | exception line, RC 4 | `PRM2026129` type X | `tests/run_tests.sh` BR-V1 |
| | | | | | | |

Rules to look for in pricing-style jobs: validation, target resolution,
base computation, overrides from called programs, floors/caps, rounding
(direction! truncation vs rounding, COBOL `COMPUTE` truncates unless
`ROUNDED`), ordering of the above, date windows (inclusive/exclusive), what
"unchanged" means, and what is counted in each total.

## 5. Called programs

| Program | Interface (copybook) | When called | Inputs | Outputs | Rules inside |
|---------|----------------------|-------------|--------|---------|--------------|
| | | | | | |

## 6. DB2 touchpoints

| Table | Operation | Paragraph | SQL (as in comments / precompiler source) | Host variables | Stand-in file | Commit scope |
|-------|-----------|-----------|-------------------------------------------|----------------|---------------|--------------|
| `PRCDB.ITEM_PRICE` | SELECT ... FOR UPDATE / UPDATE | | | `DCLITMPR` | `data/db2/...` | |
| | | | | | | |

State explicitly: which tables are updated in place, which are insert-only,
how surrogate keys/sequences are allocated, what happens on `SQLCODE +100`,
and the unit of work (single commit at end vs. per-record).

## 7. Processing narrative

Numbered walk-through of one run in execution order (initialise, phase 1,
phase 2 per record, phase 3, terminate). Mention every place where the
**order of operations** matters for the result.

## 8. Report / output layout

Column-by-column layout of every printed line type (header, detail, totals),
the paging rule, and which counters feed which totals. The migrated
implementation must produce this byte-for-byte.

## 9. Edge cases and observed defects

| # | Scenario | Current behaviour (with evidence) | Preserve or fix? | Ticket |
|---|----------|-----------------------------------|------------------|--------|
| 1 | | | preserve | - |
| 2 | | | fix | MFM-<n> |

Typical items: empty input files, header-only CSV, duplicate keys, record
matching no table row, prices that collapse to 0.09, dates of `00000000`,
table overflow limits (`OCCURS` sizes), truncation in `COMPUTE`, behaviour
when the called program returns a bad RC.

## 10. Equivalence verification plan

- Inputs: exact files and control cards used for both implementations.
- Outputs compared: list (report, each after-state table).
- Comparison method: `scripts/compare.sh <dir>` byte compare; tolerance = none.
- Additional generated cases (if any) and how their expected values were derived (from the COBOL run, never hand-computed).
- Exit-code mapping between the JCL MAXCC and the target runtime.

## 11. Target design notes (filled in during *plan*)

Mapping of steps to target constructs (e.g. Spring Batch `Step`, `ItemReader`,
`ItemProcessor`, `ItemWriter`, tasklets), where each business rule lives in
the target, and what is intentionally kept ugly to stay byte-identical.

## 12. Open questions for the business / SMEs

Numbered list. Each with the decision needed, the default assumed for the
migration, and the evidence gap.
