# Playbook: COBOL ask mode (read-only scoping from a Jira ticket)

Installed in the Devin org as macro `!cobol_ask` (usable as a Jira playbook
label, and the recommended **default playbook** so that assigning a ticket to
Devin or adding the `devin` label is always safe).

Use when a ticket or a `@Devin` comment asks a question about a job, or when a
ticket should be scoped before anyone commits to a full session. The
deliverable is one Jira comment. Nothing else changes.

## Hard limits

- No file edits, no build, no `scripts/run_job.sh`, no branch, no PR.
- No Jira transitions, no edits to the ticket description, no new tickets.
- One comment on the ticket; follow-up `@Devin` questions get one comment each.

## Procedure

1. Read the ticket and all comments (`mfm-jira-board`, step 1, without the
   transition). Restate the question in one line at the top of your answer.
2. Follow the repo skill `.agents/skills/cobol-ask/SKILL.md`: start at
   `jcl/<JOB>.jcl`, walk to `cobol/src`, `cobol/copybooks`, `cobol/sql/ddl`,
   `data/`, `schedules/`. Cite `file:line` or paragraph for every statement.
3. List **findings**: suspected defects, implicit numeric semantics
   (truncation vs `ROUNDED`, `COMP-3` widths, sign handling), sort-order
   assumptions, unknowns. Mark each "observed - preserve unless a ticket says
   fix".
4. If the ticket is work (not just a question), add a **scoped plan** of at
   most 10 steps on the repo's loop (baseline compare -> explore -> spec ->
   plan -> implement -> same-input compare -> CI gate -> PR), name the golden
   files that would change, and give a confidence estimate
   (high / medium / low + one sentence).
5. Post the comment. End with:
   *"To implement, add the `!jcl_migrate` (migration) or `!cobol_fix`
   (in-place change) label to this ticket, or start a session from this
   comment."*
6. Stop. Do not start the implementation session yourself.
