---
name: mfm-jira-board
description: Working protocol for the "Mainframe Modernization" (MFM) Jira board. Use in every session that touches a COBOL/JCL job in this repo - migration (!jcl_migrate), in-place fix (!cobol_fix) or read-only analysis (!cobol_ask) - to read the ticket, report at each phase and move the ticket only through the transitions Devin owns.
---

# MFM Jira board protocol

Board: https://cog-gtm.atlassian.net/jira/software/projects/MFM/boards/2594
(project key `MFM`, cog-gtm.atlassian.net). Docs use aliases: MFM-101 = `MFM-1`
(migrate `PRCUPD01` to Java), MFM-102 = `MFM-2` (clearance price-floor fix).

The ticket is the source of truth for scope and acceptance criteria; the repo is
the source of truth for behaviour. When they disagree, write the disagreement
on the ticket - do not pick one silently.

## 1. Before touching code

1. Read the ticket and **all** comments with the Jira tool (`get_issue`,
   `list_comments`). Extract: job/program, paragraph, required proof, rows or
   values the ticket says will change, and anything marked "preserve".
2. If the session was started with a question rather than a ticket (a `@Devin`
   comment or `!cobol_ask`), find the ticket key in the comment or in the
   issue the comment was posted on; if there is none, answer the question as
   asked from the repo and say that no ticket was in scope. Never pick a
   ticket off the board on the asker's behalf.
3. Post one comment: session link + one-line plan + the phases you will report
   on. Move `Ready for Devin -> In Progress` (`list_transitions` then apply).
   For `!cobol_ask` / read-only work: do **not** transition; comment only.

## 2. During the work - one comment per phase

Post a short comment (5-15 lines, no prose padding) at the end of each phase.
Use the phase word as the first line so the board reads like a log:

```
EXPLORE  - JCL steps, DD->file->copybook map, downstream jobs, DB2 tables touched
SPECIFY  - link/path to docs/specs/<JOB>.md; count of rules; list of observed
           defects and whether each is "preserve" (default) or "fix" (ticket says so)
PLAN     - target layout in <=10 lines; STOP here and wait for a human "go"
           on MFM-1 (migration). MFM-2 (fix) may continue.
IMPLEMENT- files changed, commit SHA, build result
VERIFY   - paste the tail of scripts/compare.sh, MAXCC, tests passed/failed,
           and the exact golden-file diff the ticket allowed
```

Rules:
- Every value you claim on the ticket must come from a command you ran in this
  session (compare output, MAXCC, test count). Never type an expected number.
- Quote `file:line` or paragraph names for every business rule you mention.
- A new defect you find is a **finding**, recorded on the ticket under SPECIFY
  as "observed defect: preserve" - it is not fixed unless the ticket says so
  and it is not silently corrected in the migration. Offer a follow-up ticket.
- Questions for humans go on the ticket as a comment starting `QUESTION -`
  and you keep working on everything that does not depend on the answer.

## 3. Finishing

1. Open the PR. Its body carries the VERIFY evidence (compare output, MAXCC,
   before/after diff of any golden file the ticket allowed to change).
2. Comment on the ticket: PR URL, head SHA, CI status, and the one-line
   verification verdict. Move `In Progress -> In Review`.
3. Never move a ticket to `Verified` or `Done`; never reopen or edit the
   ticket description; never create tickets in projects other than `MFM`.
4. If blocked (no parity, missing input, ambiguous rule): leave the ticket in
   `In Progress`, comment `BLOCKED -` with the diff or question, and stop.

## 4. Follow-ups

`@Devin` comments on a ticket with an existing session are forwarded to that
session. Treat them as new instructions scoped to that ticket; re-run VERIFY
and post a fresh VERIFY comment after any code change.
