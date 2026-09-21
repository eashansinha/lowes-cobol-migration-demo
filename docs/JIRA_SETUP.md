# Jira setup: "Mainframe Modernization" board

This document defines the Jira board and the two tickets used in the demo. The
tickets are written so Devin can pick them up directly from the Jira
integration (or be pasted as a prompt) without further clarification.

## Live sandbox (cog-gtm.atlassian.net)

The board and both tickets exist in a dedicated sandbox project. The ticket
numbers below (`MFM-101` / `MFM-102`) are the demo aliases used throughout the
docs; Jira numbered them from 1.

| Alias | Live key | URL |
|-------|----------|-----|
| Board | `MFM` | https://cog-gtm.atlassian.net/jira/software/projects/MFM/boards/2594 |
| MFM-101 | `MFM-1` | https://cog-gtm.atlassian.net/browse/MFM-1 |
| MFM-102 | `MFM-2` | https://cog-gtm.atlassian.net/browse/MFM-2 |

Both tickets were created in **Ready for Devin**; the Jira integration moves
them to **In Progress** when a session picks them up.

### Board inventory (context for Devin)

The board also carries the project's history and backlog so a session working
MFM-1 or MFM-2 can read what was already decided (goldens freeze current
behaviour, DB2 is CSV, which defects are fixed vs. preserved) instead of
rediscovering it. Tickets without the `devin` label are context only.
Status is the Jira column; "Devin session" says whether the integration has
linked a session (it does not move the ticket by itself).

| Key | Status | Type | Devin session | Summary |
|-----|--------|------|---------------|---------|
| [MFM-3](https://cog-gtm.atlassian.net/browse/MFM-3) | Done | Task | no | Inventory nightly batch: PRCUPD01 -> INVREPL01 dependency chain and DD/dataset map |
| [MFM-4](https://cog-gtm.atlassian.net/browse/MFM-4) | Done | Task | no | Stand up GnuCOBOL build and CI (ASCII, no mainframe needed) |
| [MFM-5](https://cog-gtm.atlassian.net/browse/MFM-5) | Done | Task | no | Capture golden-master outputs: audit report + ITEM_PRICE / PRICE_HIST after-state |
| [MFM-6](https://cog-gtm.atlassian.net/browse/MFM-6) | Done | Task | no | Decision: DB2 tables as CSV before/after dumps |
| [MFM-7](https://cog-gtm.atlassian.net/browse/MFM-7) | Done | Bug | no | REGION OVERRIDE total counted rejected NC BOGO rows (6 -> 5) |
| [MFM-8](https://cog-gtm.atlassian.net/browse/MFM-8) | Done | Bug | no | HIST_SEQ taken from last row instead of max; capacity guards |
| [MFM-9](https://cog-gtm.atlassian.net/browse/MFM-9) | In Review | Task | yes (eashan-dev) | Devin playbooks: `!jcl_migrate` and `!cobol_fix` |
| [MFM-1](https://cog-gtm.atlassian.net/browse/MFM-1) | In Progress | Story | yes (devin-gtm) | Migrate PRCUPD01 to Java (Spring Batch) with equivalence verification (MFM-101) |
| [MFM-2](https://cog-gtm.atlassian.net/browse/MFM-2) | In Progress | Bug | yes (devin-gtm) | Fix clearance price-floor rounding defect (MFM-102) |
| [MFM-10](https://cog-gtm.atlassian.net/browse/MFM-10) | Backlog | Bug | no | WC lumber 15% cap defeated by the .x9 round-down (SKU 10012233 -> 3.59) |
| [MFM-11](https://cog-gtm.atlassian.net/browse/MFM-11) | Backlog | Story | no | Migrate INVREPL01 to Java once PRCUPD01 equivalence is proven |
| [MFM-12](https://cog-gtm.atlassian.net/browse/MFM-12) | Backlog | Task | no | EBCDIC -> ASCII strategy for production feeds (COMP-3, zoned) |
| [MFM-13](https://cog-gtm.atlassian.net/browse/MFM-13) | Backlog | Story | no | Publish price-change events to MQ from the Java implementation |
| [MFM-14](https://cog-gtm.atlassian.net/browse/MFM-14) | Backlog | Task | yes (eashan-dev) | Migration spec for PRCRGN01 region override rules |

MFM-10 is the live "pick up a fresh ticket" candidate for the demo: it is a
real, unfixed defect with a predicted one-row golden change. It has no `devin`
label yet, so no session exists for it; start one from the ticket with the
path B prompt in `JIRA_TO_DEVIN_DEMO_GUIDE.md` using the MFM-10 URL and
`!cobol_fix` (it is a Bug, not a migration), or add the label live.

## Board

| Setting | Value |
|---------|-------|
| Project | **Mainframe Modernization** (key `MFM`, Kanban, team-managed) |
| Issue types | Story (migration work), Bug (in-place fixes), Task |
| Columns | `Backlog` -> `Ready for Devin` -> `In Progress` -> `In Review` -> `Verified` -> `Done` |
| WIP limit | `In Progress` = 3 (one Devin session per ticket) |
| Devin trigger (ask) | Label `!cobol_ask`, or comment `@Devin !cobol_ask <question>`: read-only analysis + scoped plan as a comment, no code, no transition. Also the default playbook, so assigning to the Devin user / label `devin` is ask mode |
| Devin trigger (work) | Label `!jcl_migrate` (Story) or `!cobol_fix` (Bug), or the automation *status = Ready for Devin* (not yet verified on the sandbox; the only verified trigger is the `devin` label at creation): full session with the ticket as the task |
| Board protocol | Repo skill `.agents/skills/mfm-jira-board/SKILL.md` + pinned knowledge note: read ticket first, phase comments `EXPLORE / SPECIFY / PLAN / IMPLEMENT / VERIFY`, evidence on the ticket |
| Devin transitions | Devin moves the ticket `Ready for Devin -> In Progress` when it starts and `In Progress -> In Review` when the PR is open. Humans move `In Review -> Verified -> Done` |
| Required fields | Repository (`eashansinha/lowes-cobol-migration-demo`), Job name, Acceptance criteria |
| Labels | `cobol`, `jcl`, `db2`, `migration`, `maintenance`, `devin`, `!cobol_ask`, `!jcl_migrate`, `!cobol_fix` |

Column semantics:

- **Backlog** - identified job/defect, not yet groomed.
- **Ready for Devin** - acceptance criteria are complete; the ticket names the job, the repo and the proof required.
- **In Progress** - a Devin session is attached (session link in a comment).
- **In Review** - PR opened; ticket comment contains the PR link, the verification summary and the compare output.
- **Verified** - a human re-ran `scripts/compare.sh` (or CI is green) and reviewed the spec.
- **Done** - merged.

## Ticket MFM-101 (Story)

**Summary:** Migrate PRCUPD01 nightly promo price job to Java (Spring Batch) with equivalence verification

**Labels:** `cobol` `jcl` `db2` `migration` `devin`  **Component:** Pricing batch  **Priority:** High

**Description**

```
Repository : eashansinha/lowes-cobol-migration-demo  (branch main)
Job        : jcl/PRCUPD01.jcl  ->  cobol/src/PRCUPD01.cbl + cobol/src/PRCRGN01.cbl
Playbook   : playbooks/cobol-job-migration.md

Context
PRCUPD01 is the nightly promotional price update. It sorts the promo feed,
applies promo pricing rules (percent / fixed / BOGO, region overrides via the
called subprogram PRCRGN01, margin floor, .x9 price endings, effective-date
windows), expires lapsed promos, updates DB2 ITEM_PRICE, inserts PRICE_HIST
and writes an audit / exception report. DB2 is unreachable from the dev
environment, so DB2 state is represented by CSV unloads under data/db2/.
INVREPL01 depends on the ITEM_PRICE after-state (schedules/nightly.txt).

Task
Migrate the job to Java 17 + Spring Batch, keeping behaviour byte-identical.

1. EXPLORE  Read the JCL, both programs, all copybooks, the DDL and the
   scheduler manifest. Identify every DD name, every business rule (BR-*
   ids in the source comments) and every DB2 touchpoint.
2. SPECIFY  Fill docs/MIGRATION_SPEC_TEMPLATE.md for PRCUPD01 and commit it
   as docs/specs/PRCUPD01-spec.md. Include the deliberately-preserved
   current behaviour of BR-P6 (see MFM-102) - the migration must reproduce
   it, not fix it.
3. PLAN     Propose the Spring Batch job layout (steps, readers, processors,
   writers, tasklets for SORT and compare) in the PR description before
   coding.
4. IMPLEMENT Create java/ (Maven, Java 17, Spring Batch 5) with:
     - a sort step equivalent to STEP010,
     - a chunk step equivalent to PRCUPD01 phases 1-3 with PRCRGN01 as a
       plain service class,
     - CSV-backed repositories for ITEM_PRICE / PRICE_HIST / STORE_REGION
       behind an interface that a JDBC implementation could replace,
     - a report writer producing the identical 132-column PRCRPT layout.
   No behaviour changes; no rounding "improvements".
5. VERIFY   Run BOTH implementations on the same inputs and byte-compare
   (scripts/compare.sh <java-output-dir>) the report, ITEM_PRICE after-state
   and PRICE_HIST after-state. Add the Java run to .github/workflows/ci.yml.
```

**Acceptance criteria**

- [ ] `docs/specs/PRCUPD01-spec.md` produced from the template: business-rules table with BR ids, I/O contract per DD, DB2 touchpoints, edge cases, open questions.
- [ ] Java (Spring Batch) implementation under `java/` builds with `mvn -q verify`.
- [ ] Both COBOL and Java are run on the identical inputs (`data/input/*`, `data/db2/before/*`, `RUNDATE=20260921`).
- [ ] `scripts/compare.sh <java-output-dir>` exits 0: report + `ITEM_PRICE` + `PRICE_HIST` after-state byte-identical to the golden files (which equal the COBOL output).
- [ ] Java exit code is 4 on the sample data (matches job MAXCC semantics).
- [ ] CI runs COBOL, Java and the compare on every PR.
- [ ] PR opened against `main` with the plan, the spec link and the compare output in the description.
- [ ] Ticket moved to **In Review** with the PR link and a Devin session link in a comment.

**Out of scope:** real DB2 connectivity, EBCDIC input, MQ output to stores, INVREPL01.

## Ticket MFM-102 (Bug)

**Summary:** PRCUPD01: fix price-floor rounding defect for clearance items and add regression test

**Labels:** `cobol` `maintenance` `devin`  **Component:** Pricing batch  **Priority:** Medium  **Affects:** PRCUPD01 (change MERCH-6875, 2022-08-15)

**Description**

```
Repository : eashansinha/lowes-cobol-migration-demo  (branch main)
Program    : cobol/src/PRCUPD01.cbl  paragraph 2620-CLEARANCE-PRICING
Playbook   : playbooks/cobol-job-maintenance.md

Defect
For clearance items (IM-STATUS = 'C', rule BR-P6) the margin floor is applied
BEFORE the .x9 round-down:

    2620-CLEARANCE-PRICING.
        COMPUTE WS-WORK-PRICE = WS-WORK-PRICE * WS-CLEARANCE-MARKDOWN / 100
        PERFORM 2660-APPLY-MARGIN-FLOOR
        PERFORM 2650-ROUND-DOWN-X9.

When the floor kicks in, the floored price is then rounded DOWN, so the shelf
price lands below the floor. Standard items (2610-STANDARD-PRICING) do it
correctly: round down, apply floor, and if floored round UP to the next .x9.

Reproduction (current golden data, RUNDATE=20260921)
  SKU 10082345 HUSKY 52IN TOOL CHEST, status C, cost 260.00, floor 5% -> floor 273.00
  Promo PRM2026123 P 40% on reg 498.00 -> 298.80 -> x0.90 clearance = 268.92
  Current : floor -> 273.00, round down -> 272.99   (0.01 BELOW floor)  <- wrong
  Expected: round down -> 268.89, floor -> 273.00, round up -> 273.09

Fix
Make 2620-CLEARANCE-PRICING follow the same sequence as 2610: markdown,
round down, floor, round up if floored. Do not change 2610, PRCRGN01 or any
rounding helper.

Expected result changes (only these; all other rows and totals identical)
  data/expected/PRCUPD01.rpt
    PRM2026123 10082345 NE/SE/MW/WC  NEW-PRICE 272.99 -> 273.09  (REASON FLOOR unchanged)
    PRM2026123 10082345 NC           290.39 unchanged (not floored)
  data/db2/expected_after/ITEM_PRICE.csv
    10082345,{NE,SE,MW,WC}  CURR_PRICE 272.99 -> 273.09
  data/db2/expected_after/PRICE_HIST.csv
    HIST_SEQ 1022..1025     NEW_PRICE  272.99 -> 273.09
  Totals: PRICES UPDATED 30, RAISED TO FLOOR 9 - unchanged.
```

**Acceptance criteria**

- [ ] Before touching code, run `tests/run_tests.sh` and attach the output proving the current (defective) behaviour is what the golden files encode.
- [ ] `2620-CLEARANCE-PRICING` fixed; no other paragraph changed.
- [ ] Golden files updated to exactly the expected values above and nothing else (`git diff --stat` on `data/` shows 3 files; the report diff touches 4 detail lines).
- [ ] `tests/run_tests.sh` updated: BR-P6 assertion now expects 273.09, plus a new assertion that no clearance `FLOOR` row on the report has a `NEW-PRICE` below its floor (regression test for the defect class, not just the instance).
- [ ] `scripts/run_job.sh` still ends MAXCC=4 and `compare.sh` passes; CI green.
- [ ] PR opened against `main` with a before/after excerpt of the report and the `ITEM_PRICE` diff; ticket moved to **In Review**.

## Sandbox tickets

The two tickets above were created via the Atlassian MCP in the dedicated
sandbox project `MFM` on cog-gtm.atlassian.net (see "Live sandbox" at the top
of this document). Never create them in a customer's Jira.

| Ticket | Key | URL |
|--------|-----|-----|
| Migrate PRCUPD01 to Java | `MFM-1` (alias MFM-101) | https://cog-gtm.atlassian.net/browse/MFM-1 |
| Fix clearance floor rounding | `MFM-2` (alias MFM-102) | https://cog-gtm.atlassian.net/browse/MFM-2 |

<!-- JIRA-STATUS -->
If you demo against a different Jira site, the definitions above are the
source of truth and can be pasted into any Jira project by hand in under five
minutes (create project -> Kanban -> add the six columns -> create the two
issues).
