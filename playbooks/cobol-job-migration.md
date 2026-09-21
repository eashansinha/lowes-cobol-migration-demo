# Playbook: migrate a JCL batch job to Java (Spring Batch) with equivalence verification

Use for tickets of the form *"Migrate <JOB> to Java with equivalence
verification"*. One job per ticket. The deliverable is a PR whose description
proves, with a byte-compare, that the Java job produces the same report and
the same database after-state as the COBOL job on identical inputs.

## Procedure

1. **Claim the ticket.** Move the Jira ticket to *In Progress* and comment with
   this session's link. Read the ticket's acceptance criteria; if the repo,
   job name or required proof is missing, ask once, then proceed with the
   defaults below.

2. **Explore - build the job's dependency picture before reading logic.**
   Start from `jcl/<JOB>.jcl`, not the COBOL. Record, in your notes:
   - every step, `PGM=`, `COND`/`IF`, sort keys;
   - every DD name -> dataset -> the `SELECT ... ASSIGN TO` it satisfies;
   - every `COPY` and every `CALL` (follow into the subprogram);
   - every `EXEC SQL` (or its stand-in paragraph) -> table -> DDL -> DCLGEN copybook;
   - predecessors / successors from `schedules/` and what they consume.
   Build and run the job as-is first (`scripts/build.sh && scripts/run_job.sh`);
   note the MAXCC and confirm `compare.sh` passes on `main`. You are not
   allowed to migrate a job you cannot run.

3. **Specify - fill `docs/MIGRATION_SPEC_TEMPLATE.md`** into
   `docs/specs/<JOB>-spec.md`. Rules:
   - every business rule gets an id and a paragraph reference (evidence);
   - describe **actual** behaviour, including anything that looks wrong -
     list it under "observed defects: preserve" unless the ticket says to fix it;
   - pay special attention to arithmetic order (round/floor/cap), COBOL
     truncation vs `ROUNDED`, date-window inclusivity, and what each report
     total counts;
   - list edge cases you can see in the sample data and any you cannot.
   Commit the spec on its own; it is reviewable independent of code.

4. **Plan - post the target layout in the PR description and pause.** Map
   each JCL step to Spring Batch constructs (tasklet for SORT, chunk step for
   the program, tasklet for compare), each rule to a class/method, each table
   to a repository interface with a CSV implementation now and a JDBC one
   later. State what you will keep deliberately "ugly" to remain
   byte-identical (report formatting, sequence allocation, truncation). Wait
   for an OK if the ticket asks for one; otherwise continue.

5. **Implement** under `java/` (Maven, Java 17, Spring Batch 5):
   - fixed-width readers generated from the copybooks, not hand-guessed;
   - one class per called subprogram, same inputs/outputs as the COMMAREA;
   - `BigDecimal` with explicit scale and `RoundingMode.DOWN` where COBOL
     truncates; never `double`;
   - report writer produces the identical 132-column lines including
     trailing-space behaviour of the COBOL runtime;
   - exit code = the COBOL RETURN-CODE semantics.
   No functional "improvements". If you believe something is a defect, it is
   already in the spec; leave it.

6. **Verify - equivalence is a diff.**
   ```bash
   scripts/run_job.sh --no-compare                       # COBOL -> work/
   (cd java && mvn -q verify && java -jar target/<job>.jar --out ../work-java)
   scripts/compare.sh work-java                          # must exit 0
   ```
   Iterate until `compare.sh` exits 0 for the report and every after-state
   table. Then add the Java build + run + compare to `.github/workflows/ci.yml`
   so both implementations are verified on every PR. Run the repo test suite
   (`tests/run_tests.sh`) and add tests for anything new (e.g. a Java-side
   test that pins the exit code).

7. **Deliver.** Open the PR against `main`: summary, link to the spec, the
   plan, the compare output pasted verbatim, and a short "kept deliberately"
   list. Move the ticket to *In Review* with the PR link. Do not merge.

## Done when

- `docs/specs/<JOB>-spec.md` committed with evidence per rule.
- `scripts/compare.sh <java-out>` exits 0 on the sample data.
- CI runs COBOL, Java and the compare and is green.
- Ticket in *In Review* with PR + session links.

## Verification of the deliverable

This repository is a batch estate with no web frontend; verification is the
golden-master compare plus the test harness, not a browser walkthrough. Paste
the compare output and the `tests/run_tests.sh` summary line in the PR so a
reviewer can see the proof without re-running it.
