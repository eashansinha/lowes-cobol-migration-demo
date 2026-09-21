       IDENTIFICATION DIVISION.
       PROGRAM-ID.    GLPOST01.
       AUTHOR.        GENERAL LEDGER SYSTEMS - FINANCE IT.
      *================================================================*
      * GLPOST01 - DAILY GENERAL LEDGER POSTING                        *
      *                                                                *
      * JCL      : jcl/GLPOST01.jcl  (step GLPOST, PROC GLPOST01)      *
      * Schedule : DAILY 02:00 after the sub-ledger extracts,          *
      *            predecessor of GLBAL01 (trial balance) - see        *
      *            schedules/nightly.txt                               *
      *                                                                *
      * FUNCTION                                                       *
      *  Read the SORTED daily journal feed (one record per journal    *
      *  line), validate every line against the chart of accounts,    *
      *  post the valid lines to the posted-ledger file with a signed  *
      *  amount, write every rejected line to the exceptions file and  *
      *  produce the batch-control / run-totals report that the        *
      *  accounting team signs off before GLBAL01 runs.               *
      *                                                                *
      *  A file in, files out job: no DB2, no VSAM updates. The only   *
      *  state is the three output data sets.                          *
      *                                                                *
      * DD NAMES                                                       *
      *  SYSIN     control cards        RUNDATE=YYYYMMDD               *
      *  GLTRANS   sorted journal feed  GLTRNREC (100)                 *
      *  ACCTMAST  chart of accounts    ACCTMAST (60) sorted ACCT-NO   *
      *  GLPOSTED  posted ledger        GLPSTREC (120)                 *
      *  GLEXCEPT  posting exceptions   GLEXCREC (80)                  *
      *  GLRPT     control report       (132)                          *
      *                                                                *
      * BUSINESS RULES (see docs/tasks/GLPOST01.md for the full spec)  *
      *  BR-V1 DR-CR must be D or C                        else E004   *
      *  BR-V2 AMOUNT must be greater than zero            else E005   *
      *  BR-V3 CURRENCY must be USD (others suspended)     else E006   *
      *  BR-V4 ACCT-NO must exist on ACCTMAST              else E001   *
      *  BR-V5 account must not be closed                  else E002   *
      *  BR-V6 account must not be frozen                  else E003   *
      *  BR-V7 POST-DATE in RUNDATE period and <= RUNDATE  else E007   *
      *        Validation stops at the FIRST failing rule; one         *
      *        exception record per rejected line.                     *
      *  BR-P1 SIGNED-AMT = +AMOUNT when DR-CR = account NORMAL-BAL,   *
      *        -AMOUNT otherwise (amount that increases the account    *
      *        is positive).                                           *
      *  BR-P2 POST-SEQ restarts at 0000001 every run.                 *
      *  BR-P3 Blank DESCRIPTION is posted as 'NO DESCRIPTION'.        *
      *  BR-B1 A batch is BALANCED when the DEBIT and CREDIT totals of *
      *        ALL its submitted lines (posted or rejected) are equal; *
      *        otherwise OUT OF BALANCE and the job ends with RC 4.    *
      *  BR-B2 Any rejected line also ends the job with RC 4.          *
      *                                                                *
      * RETURN CODES  0 clean   4 exceptions / out of balance          *
      *               8 empty feed or bad control card   16 abend      *
      *                                                                *
      * CHANGE LOG                                                     *
      *  2009-02-16  FIN-0412   initial                                *
      *  2012-07-30  FIN-1877   E006 non-USD suspense (multi-currency  *
      *                         deferred to GLFX01, never delivered)   *
      *  2015-10-05  FIN-2903   frozen account status (E003)           *
      *  2019-04-22  FIN-4410   batch control section on GLRPT         *
      *  2021-01-11  FIN-5122   period check E007 after close issues   *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SYSIN-FILE   ASSIGN TO SYSIN
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-SYSIN.
           SELECT TRAN-FILE    ASSIGN TO GLTRANS
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-TRAN.
           SELECT ACCT-FILE    ASSIGN TO ACCTMAST
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-ACCT.
           SELECT POSTED-FILE  ASSIGN TO GLPOSTED
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-POSTED.
           SELECT EXCEPT-FILE  ASSIGN TO GLEXCEPT
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-EXCEPT.
           SELECT REPORT-FILE  ASSIGN TO GLRPT
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-RPT.

       DATA DIVISION.
       FILE SECTION.
       FD  SYSIN-FILE.
       01  SYSIN-REC                   PIC X(80).

       FD  TRAN-FILE.
           COPY GLTRNREC.

       FD  ACCT-FILE.
           COPY ACCTMAST.

       FD  POSTED-FILE.
           COPY GLPSTREC.

       FD  EXCEPT-FILE.
           COPY GLEXCREC.

       FD  REPORT-FILE.
       01  REPORT-REC                  PIC X(132).

       WORKING-STORAGE SECTION.
       01  WS-FILE-STATUS.
           05  WS-FS-SYSIN             PIC X(02).
           05  WS-FS-TRAN              PIC X(02).
           05  WS-FS-ACCT              PIC X(02).
           05  WS-FS-POSTED            PIC X(02).
           05  WS-FS-EXCEPT            PIC X(02).
           05  WS-FS-RPT               PIC X(02).

       01  WS-FLAGS.
           05  WS-TRAN-EOF             PIC X(01) VALUE 'N'.
               88  TRAN-EOF            VALUE 'Y'.
           05  WS-ACCT-EOF             PIC X(01) VALUE 'N'.
               88  ACCT-EOF            VALUE 'Y'.
           05  WS-ACCT-FOUND           PIC X(01) VALUE 'N'.
               88  ACCT-FOUND          VALUE 'Y'.
           05  WS-LINE-VALID           PIC X(01) VALUE 'Y'.
               88  LINE-VALID          VALUE 'Y'.
           05  WS-FIRST-BATCH          PIC X(01) VALUE 'Y'.
               88  FIRST-BATCH         VALUE 'Y'.

       01  WS-CONTROL.
           05  WS-RUNDATE              PIC 9(08) VALUE ZERO.
           05  WS-RUNDATE-X REDEFINES WS-RUNDATE.
               10  WS-RUN-YYYY         PIC X(04).
               10  WS-RUN-MM           PIC X(02).
               10  WS-RUN-DD           PIC X(02).
           05  WS-RUN-PERIOD           PIC X(06).
           05  WS-RETURN-CODE          PIC 9(02) VALUE ZERO.

      *----------------------------------------------------------------*
      * Chart of accounts table - linear SEARCH, 300 max (FIN-0412).   *
      * Overflow is an abend: the CoA has never exceeded 220 accounts. *
      *----------------------------------------------------------------*
       01  WS-ACCT-TABLE.
           05  WS-ACCT-COUNT           PIC 9(04) COMP VALUE ZERO.
           05  WS-ACCT-MAX             PIC 9(04) COMP VALUE 300.
           05  WS-ACCT-ENTRY OCCURS 300 TIMES
                                       INDEXED BY ACCT-IDX.
               10  WS-ACM-ACCT-NO      PIC X(10).
               10  WS-ACM-ACCT-TYPE    PIC X(01).
               10  WS-ACM-STATUS       PIC X(01).
               10  WS-ACM-NORMAL-BAL   PIC X(01).
               10  WS-ACM-ACCT-NAME    PIC X(30).

       01  WS-CURRENT-ACCT.
           05  WS-CUR-ACCT-TYPE        PIC X(01).
           05  WS-CUR-STATUS           PIC X(01).
           05  WS-CUR-NORMAL-BAL       PIC X(01).

       01  WS-EXCEPTION.
           05  WS-REASON-CD            PIC X(04).
           05  WS-REASON-TX            PIC X(30).

       01  WS-AMOUNTS.
           05  WS-SIGNED-AMT           PIC S9(11)V99 COMP-3.
           05  WS-TRAN-PERIOD          PIC X(06).

      *----------------------------------------------------------------*
      * Batch control (control break on GLT-BATCH-ID)                  *
      *----------------------------------------------------------------*
       01  WS-BATCH.
           05  WS-BAT-ID               PIC X(08).
           05  WS-BAT-PREV-ID          PIC X(08) VALUE SPACES.
           05  WS-BAT-LINES            PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-BAT-POSTED           PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-BAT-REJECTED         PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-BAT-DR-TOTAL         PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-BAT-CR-TOTAL         PIC S9(13)V99 COMP-3 VALUE ZERO.

      *----------------------------------------------------------------*
      * Run totals                                                     *
      *----------------------------------------------------------------*
       01  WS-TOTALS.
           05  WS-TOT-READ             PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-TOT-POSTED           PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-TOT-REJECTED         PIC 9(07) COMP-3 VALUE ZERO.
           05  WS-TOT-BATCHES          PIC 9(05) COMP-3 VALUE ZERO.
           05  WS-TOT-BAT-OOB          PIC 9(05) COMP-3 VALUE ZERO.
           05  WS-TOT-ACCTS            PIC 9(05) COMP-3 VALUE ZERO.
           05  WS-TOT-DR-POSTED        PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-TOT-CR-POSTED        PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-TOT-NET-POSTED       PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-TOT-DR-REJECT        PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-TOT-CR-REJECT        PIC S9(13)V99 COMP-3 VALUE ZERO.
           05  WS-POST-SEQ             PIC 9(07) VALUE ZERO.

      *  Posted totals by account type: 1=A 2=L 3=Q 4=R 5=E
       01  WS-TYPE-TOTALS.
           05  WS-TYPE-ENTRY OCCURS 5 TIMES.
               10  WS-TYP-CODE         PIC X(01).
               10  WS-TYP-NAME         PIC X(09).
               10  WS-TYP-LINES        PIC 9(07) COMP-3.
               10  WS-TYP-DR           PIC S9(13)V99 COMP-3.
               10  WS-TYP-CR           PIC S9(13)V99 COMP-3.
               10  WS-TYP-NET          PIC S9(13)V99 COMP-3.
       01  WS-TYPE-IDX                 PIC 9(01).

      *  Exceptions by reason code: 1=E001 .. 7=E007
       01  WS-REASON-TOTALS.
           05  WS-RSN-ENTRY OCCURS 7 TIMES.
               10  WS-RSN-CODE         PIC X(04).
               10  WS-RSN-TEXT         PIC X(30).
               10  WS-RSN-COUNT        PIC 9(07) COMP-3.
               10  WS-RSN-AMOUNT       PIC S9(13)V99 COMP-3.
       01  WS-REASON-IDX               PIC 9(01).

      *----------------------------------------------------------------*
      * Report lines (132)                                             *
      *----------------------------------------------------------------*
       01  RL-HEADER-1.
           05  FILLER                  PIC X(10) VALUE 'GLPOST01'.
           05  FILLER                  PIC X(14) VALUE SPACES.
           05  FILLER                  PIC X(52) VALUE
               'DAILY GENERAL LEDGER POSTING - BATCH CONTROL REPORT'.
           05  FILLER                  PIC X(20) VALUE SPACES.
           05  FILLER                  PIC X(09) VALUE 'RUN DATE '.
           05  RL-H1-YYYY              PIC X(04).
           05  FILLER                  PIC X(01) VALUE '-'.
           05  RL-H1-MM                PIC X(02).
           05  FILLER                  PIC X(01) VALUE '-'.
           05  RL-H1-DD                PIC X(02).
           05  FILLER                  PIC X(17) VALUE SPACES.

       01  RL-SECTION.
           05  RL-SEC-TITLE            PIC X(40).
           05  FILLER                  PIC X(92) VALUE SPACES.

       01  RL-BATCH-HDR.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(10) VALUE 'BATCH ID'.
           05  FILLER                  PIC X(08) VALUE '   LINES'.
           05  FILLER                  PIC X(08) VALUE '  POSTED'.
           05  FILLER                  PIC X(08) VALUE '  REJECT'.
           05  FILLER                  PIC X(22) VALUE
               '           DEBIT TOTAL'.
           05  FILLER                  PIC X(22) VALUE
               '          CREDIT TOTAL'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(16) VALUE 'STATUS'.
           05  FILLER                  PIC X(34) VALUE SPACES.

       01  RL-BATCH-LINE.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-BAT-ID               PIC X(08).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-BAT-LINES            PIC Z(7)9.
           05  RL-BAT-POSTED           PIC Z(7)9.
           05  RL-BAT-REJECTED         PIC Z(7)9.
           05  RL-BAT-DR               PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99.
           05  RL-BAT-CR               PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-BAT-STATUS           PIC X(16).
           05  FILLER                  PIC X(34) VALUE SPACES.

       01  RL-TYPE-HDR.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(12) VALUE 'ACCOUNT TYPE'.
           05  FILLER                  PIC X(08) VALUE '   LINES'.
           05  FILLER                  PIC X(22) VALUE
               '           DEBIT TOTAL'.
           05  FILLER                  PIC X(22) VALUE
               '          CREDIT TOTAL'.
           05  FILLER                  PIC X(23) VALUE
               '             NET SIGNED'.
           05  FILLER                  PIC X(43) VALUE SPACES.

       01  RL-TYPE-LINE.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-TYP-CODE             PIC X(01).
           05  FILLER                  PIC X(01) VALUE SPACES.
           05  RL-TYP-NAME             PIC X(10).
           05  RL-TYP-LINES            PIC Z(7)9.
           05  RL-TYP-DR               PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99.
           05  RL-TYP-CR               PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99.
           05  RL-TYP-NET              PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(43) VALUE SPACES.

       01  RL-REASON-HDR.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(36) VALUE 'REASON'.
           05  FILLER                  PIC X(08) VALUE '   LINES'.
           05  FILLER                  PIC X(22) VALUE
               '       REJECTED AMOUNT'.
           05  FILLER                  PIC X(64) VALUE SPACES.

       01  RL-REASON-LINE.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-RSN-CODE             PIC X(04).
           05  FILLER                  PIC X(01) VALUE SPACES.
           05  RL-RSN-TEXT             PIC X(31).
           05  RL-RSN-COUNT            PIC Z(7)9.
           05  RL-RSN-AMOUNT           PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99.
           05  FILLER                  PIC X(64) VALUE SPACES.

       01  RL-TOTAL-COUNT.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-TC-LABEL             PIC X(30).
           05  RL-TC-VALUE             PIC Z(7)9.
           05  FILLER                  PIC X(92) VALUE SPACES.

       01  RL-TOTAL-AMOUNT.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RL-TA-LABEL             PIC X(30).
           05  RL-TA-VALUE             PIC Z(3),ZZZ,ZZZ,ZZZ,ZZ9.99-.
           05  FILLER                  PIC X(77) VALUE SPACES.

       01  RL-BLANK                    PIC X(132) VALUE SPACES.

       PROCEDURE DIVISION.
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-TRANSACTIONS
               UNTIL TRAN-EOF
           PERFORM 3000-BATCH-BREAK
           PERFORM 4000-WRITE-TOTALS
           PERFORM 9000-TERMINATE
           MOVE WS-RETURN-CODE TO RETURN-CODE
           STOP RUN.

      *================================================================*
       1000-INITIALIZE.
           PERFORM 1100-READ-CONTROL-CARDS
           PERFORM 1200-LOAD-ACCOUNT-TABLE
           PERFORM 1300-INIT-TABLES
           OPEN INPUT  TRAN-FILE
           IF WS-FS-TRAN NOT = '00'
               DISPLAY 'GLPOST01 OPEN GLTRANS FAILED FS=' WS-FS-TRAN
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           OPEN OUTPUT POSTED-FILE EXCEPT-FILE REPORT-FILE
           IF WS-FS-POSTED NOT = '00' OR WS-FS-EXCEPT NOT = '00'
              OR WS-FS-RPT NOT = '00'
               DISPLAY 'GLPOST01 OPEN OUTPUT FAILED FS='
                       WS-FS-POSTED '/' WS-FS-EXCEPT '/' WS-FS-RPT
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           PERFORM 1400-WRITE-HEADER
           PERFORM 2100-READ-TRANSACTION
           IF TRAN-EOF
               DISPLAY 'GLPOST01 EMPTY GLTRANS FEED - NOTHING POSTED'
               MOVE 08 TO WS-RETURN-CODE
           END-IF.

       1100-READ-CONTROL-CARDS.
           OPEN INPUT SYSIN-FILE
           IF WS-FS-SYSIN NOT = '00'
               DISPLAY 'GLPOST01 OPEN SYSIN FAILED FS=' WS-FS-SYSIN
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           READ SYSIN-FILE
               AT END
                   DISPLAY 'GLPOST01 SYSIN EMPTY - RUNDATE REQUIRED'
                   MOVE 08 TO RETURN-CODE
                   STOP RUN
           END-READ
           IF SYSIN-REC(1:8) = 'RUNDATE='
               MOVE SYSIN-REC(9:8) TO WS-RUNDATE
           ELSE
               DISPLAY 'GLPOST01 BAD CONTROL CARD: ' SYSIN-REC(1:40)
               MOVE 08 TO RETURN-CODE
               STOP RUN
           END-IF
           MOVE WS-RUNDATE-X(1:6) TO WS-RUN-PERIOD
           CLOSE SYSIN-FILE.

       1200-LOAD-ACCOUNT-TABLE.
           OPEN INPUT ACCT-FILE
           IF WS-FS-ACCT NOT = '00'
               DISPLAY 'GLPOST01 OPEN ACCTMAST FAILED FS=' WS-FS-ACCT
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           PERFORM UNTIL ACCT-EOF
               READ ACCT-FILE
                   AT END SET ACCT-EOF TO TRUE
                   NOT AT END
                       ADD 1 TO WS-ACCT-COUNT
                       IF WS-ACCT-COUNT > WS-ACCT-MAX
                           DISPLAY 'GLPOST01 ACCTMAST TABLE OVERFLOW'
                           MOVE 16 TO RETURN-CODE
                           STOP RUN
                       END-IF
                       MOVE ACM-ACCT-NO
                         TO WS-ACM-ACCT-NO (WS-ACCT-COUNT)
                       MOVE ACM-ACCT-TYPE
                         TO WS-ACM-ACCT-TYPE (WS-ACCT-COUNT)
                       MOVE ACM-STATUS
                         TO WS-ACM-STATUS (WS-ACCT-COUNT)
                       MOVE ACM-NORMAL-BAL
                         TO WS-ACM-NORMAL-BAL (WS-ACCT-COUNT)
                       MOVE ACM-ACCT-NAME
                         TO WS-ACM-ACCT-NAME (WS-ACCT-COUNT)
               END-READ
           END-PERFORM
           MOVE WS-ACCT-COUNT TO WS-TOT-ACCTS
           CLOSE ACCT-FILE.

       1300-INIT-TABLES.
           MOVE 'A' TO WS-TYP-CODE (1)
           MOVE 'ASSET'     TO WS-TYP-NAME (1)
           MOVE 'L' TO WS-TYP-CODE (2)
           MOVE 'LIABILITY' TO WS-TYP-NAME (2)
           MOVE 'Q' TO WS-TYP-CODE (3)
           MOVE 'EQUITY'    TO WS-TYP-NAME (3)
           MOVE 'R' TO WS-TYP-CODE (4)
           MOVE 'REVENUE'   TO WS-TYP-NAME (4)
           MOVE 'E' TO WS-TYP-CODE (5)
           MOVE 'EXPENSE'   TO WS-TYP-NAME (5)
           PERFORM VARYING WS-TYPE-IDX FROM 1 BY 1
                   UNTIL WS-TYPE-IDX > 5
               MOVE ZERO TO WS-TYP-LINES (WS-TYPE-IDX)
                            WS-TYP-DR    (WS-TYPE-IDX)
                            WS-TYP-CR    (WS-TYPE-IDX)
                            WS-TYP-NET   (WS-TYPE-IDX)
           END-PERFORM
           MOVE 'E001' TO WS-RSN-CODE (1)
           MOVE 'ACCOUNT NOT ON MASTER'      TO WS-RSN-TEXT (1)
           MOVE 'E002' TO WS-RSN-CODE (2)
           MOVE 'ACCOUNT CLOSED'             TO WS-RSN-TEXT (2)
           MOVE 'E003' TO WS-RSN-CODE (3)
           MOVE 'ACCOUNT FROZEN - NO POSTING' TO WS-RSN-TEXT (3)
           MOVE 'E004' TO WS-RSN-CODE (4)
           MOVE 'INVALID DR/CR CODE'         TO WS-RSN-TEXT (4)
           MOVE 'E005' TO WS-RSN-CODE (5)
           MOVE 'ZERO AMOUNT'                TO WS-RSN-TEXT (5)
           MOVE 'E006' TO WS-RSN-CODE (6)
           MOVE 'NON-USD CURRENCY SUSPENDED' TO WS-RSN-TEXT (6)
           MOVE 'E007' TO WS-RSN-CODE (7)
           MOVE 'POST DATE OUT OF PERIOD'    TO WS-RSN-TEXT (7)
           PERFORM VARYING WS-REASON-IDX FROM 1 BY 1
                   UNTIL WS-REASON-IDX > 7
               MOVE ZERO TO WS-RSN-COUNT  (WS-REASON-IDX)
                            WS-RSN-AMOUNT (WS-REASON-IDX)
           END-PERFORM.

       1400-WRITE-HEADER.
           MOVE WS-RUN-YYYY TO RL-H1-YYYY
           MOVE WS-RUN-MM   TO RL-H1-MM
           MOVE WS-RUN-DD   TO RL-H1-DD
           WRITE REPORT-REC FROM RL-HEADER-1
           WRITE REPORT-REC FROM RL-BLANK
           MOVE 'BATCH CONTROL' TO RL-SEC-TITLE
           WRITE REPORT-REC FROM RL-SECTION
           WRITE REPORT-REC FROM RL-BATCH-HDR.

      *================================================================*
       2000-PROCESS-TRANSACTIONS.
           IF GLT-BATCH-ID NOT = WS-BAT-PREV-ID
               IF NOT FIRST-BATCH
                   PERFORM 3000-BATCH-BREAK
               END-IF
               PERFORM 3100-BATCH-START
           END-IF
           ADD 1 TO WS-TOT-READ
           ADD 1 TO WS-BAT-LINES
           EVALUATE TRUE
               WHEN GLT-DEBIT
                   ADD GLT-AMOUNT TO WS-BAT-DR-TOTAL
               WHEN GLT-CREDIT
                   ADD GLT-AMOUNT TO WS-BAT-CR-TOTAL
           END-EVALUATE
           PERFORM 2200-VALIDATE-LINE
           IF LINE-VALID
               PERFORM 2300-POST-LINE
           ELSE
               PERFORM 2400-REJECT-LINE
           END-IF
           PERFORM 2100-READ-TRANSACTION.

       2100-READ-TRANSACTION.
           READ TRAN-FILE
               AT END SET TRAN-EOF TO TRUE
           END-READ.

      *----------------------------------------------------------------*
      * Validation order is contractual (first failure wins).          *
      *----------------------------------------------------------------*
       2200-VALIDATE-LINE.
           MOVE 'Y' TO WS-LINE-VALID
           MOVE SPACES TO WS-REASON-CD WS-REASON-TX
           MOVE 'N' TO WS-ACCT-FOUND
           EVALUATE TRUE
               WHEN NOT GLT-DEBIT AND NOT GLT-CREDIT
                   MOVE 4 TO WS-REASON-IDX
               WHEN GLT-AMOUNT = ZERO
                   MOVE 5 TO WS-REASON-IDX
               WHEN NOT GLT-USD
                   MOVE 6 TO WS-REASON-IDX
               WHEN OTHER
                   PERFORM 2210-LOOKUP-ACCOUNT
                   EVALUATE TRUE
                       WHEN NOT ACCT-FOUND
                           MOVE 1 TO WS-REASON-IDX
                       WHEN WS-CUR-STATUS = 'C'
                           MOVE 2 TO WS-REASON-IDX
                       WHEN WS-CUR-STATUS = 'F'
                           MOVE 3 TO WS-REASON-IDX
                       WHEN OTHER
                           MOVE GLT-POST-DATE (1:6) TO WS-TRAN-PERIOD
                           IF WS-TRAN-PERIOD NOT = WS-RUN-PERIOD
                              OR GLT-POST-DATE > WS-RUNDATE
                               MOVE 7 TO WS-REASON-IDX
                           ELSE
                               MOVE 0 TO WS-REASON-IDX
                           END-IF
                   END-EVALUATE
           END-EVALUATE
           IF WS-REASON-IDX > 0
               MOVE 'N' TO WS-LINE-VALID
               MOVE WS-RSN-CODE (WS-REASON-IDX) TO WS-REASON-CD
               MOVE WS-RSN-TEXT (WS-REASON-IDX) TO WS-REASON-TX
           END-IF.

       2210-LOOKUP-ACCOUNT.
           SET ACCT-IDX TO 1
           SEARCH WS-ACCT-ENTRY
               AT END
                   MOVE 'N' TO WS-ACCT-FOUND
               WHEN WS-ACM-ACCT-NO (ACCT-IDX) = GLT-ACCT-NO
                   MOVE 'Y' TO WS-ACCT-FOUND
                   MOVE WS-ACM-ACCT-TYPE  (ACCT-IDX) TO WS-CUR-ACCT-TYPE
                   MOVE WS-ACM-STATUS     (ACCT-IDX) TO WS-CUR-STATUS
                   MOVE WS-ACM-NORMAL-BAL (ACCT-IDX)
                     TO WS-CUR-NORMAL-BAL
           END-SEARCH.

      *----------------------------------------------------------------*
      * BR-P1..P3  post the line                                       *
      *----------------------------------------------------------------*
       2300-POST-LINE.
           ADD 1 TO WS-POST-SEQ
           ADD 1 TO WS-TOT-POSTED
           ADD 1 TO WS-BAT-POSTED
           IF GLT-DR-CR = WS-CUR-NORMAL-BAL
               MOVE GLT-AMOUNT TO WS-SIGNED-AMT
           ELSE
               COMPUTE WS-SIGNED-AMT = ZERO - GLT-AMOUNT
           END-IF
           MOVE SPACES           TO GL-POSTED-REC
           MOVE WS-POST-SEQ      TO GLP-POST-SEQ
           MOVE GLT-TRAN-ID      TO GLP-TRAN-ID
           MOVE GLT-POST-DATE    TO GLP-POST-DATE
           MOVE GLT-ACCT-NO      TO GLP-ACCT-NO
           MOVE WS-CUR-ACCT-TYPE TO GLP-ACCT-TYPE
           MOVE GLT-COST-CTR     TO GLP-COST-CTR
           MOVE WS-SIGNED-AMT    TO GLP-SIGNED-AMT
           MOVE GLT-DR-CR        TO GLP-DR-CR
           MOVE GLT-CURRENCY     TO GLP-CURRENCY
           MOVE GLT-SOURCE       TO GLP-SOURCE
           MOVE GLT-BATCH-ID     TO GLP-BATCH-ID
           IF GLT-DESCRIPTION = SPACES
               MOVE 'NO DESCRIPTION' TO GLP-DESCRIPTION
           ELSE
               MOVE GLT-DESCRIPTION TO GLP-DESCRIPTION
           END-IF
           MOVE WS-RUNDATE       TO GLP-RUN-DATE
           WRITE GL-POSTED-REC
           IF WS-FS-POSTED NOT = '00'
               DISPLAY 'GLPOST01 WRITE GLPOSTED FAILED FS=' WS-FS-POSTED
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           PERFORM 2310-ACCUMULATE-POSTED.

       2310-ACCUMULATE-POSTED.
           EVALUATE WS-CUR-ACCT-TYPE
               WHEN 'A' MOVE 1 TO WS-TYPE-IDX
               WHEN 'L' MOVE 2 TO WS-TYPE-IDX
               WHEN 'Q' MOVE 3 TO WS-TYPE-IDX
               WHEN 'R' MOVE 4 TO WS-TYPE-IDX
               WHEN OTHER MOVE 5 TO WS-TYPE-IDX
           END-EVALUATE
           ADD 1 TO WS-TYP-LINES (WS-TYPE-IDX)
           ADD WS-SIGNED-AMT TO WS-TYP-NET (WS-TYPE-IDX)
                                WS-TOT-NET-POSTED
           IF GLT-DEBIT
               ADD GLT-AMOUNT TO WS-TYP-DR (WS-TYPE-IDX)
                                 WS-TOT-DR-POSTED
           ELSE
               ADD GLT-AMOUNT TO WS-TYP-CR (WS-TYPE-IDX)
                                 WS-TOT-CR-POSTED
           END-IF.

       2400-REJECT-LINE.
           ADD 1 TO WS-TOT-REJECTED
           ADD 1 TO WS-BAT-REJECTED
           ADD 1 TO WS-RSN-COUNT (WS-REASON-IDX)
           ADD GLT-AMOUNT TO WS-RSN-AMOUNT (WS-REASON-IDX)
           EVALUATE TRUE
               WHEN GLT-DEBIT
                   ADD GLT-AMOUNT TO WS-TOT-DR-REJECT
               WHEN GLT-CREDIT
                   ADD GLT-AMOUNT TO WS-TOT-CR-REJECT
           END-EVALUATE
           MOVE SPACES        TO GL-EXCEPT-REC
           MOVE GLT-TRAN-ID   TO GLX-TRAN-ID
           MOVE GLT-ACCT-NO   TO GLX-ACCT-NO
           MOVE WS-REASON-CD  TO GLX-REASON-CD
           MOVE WS-REASON-TX  TO GLX-REASON-TX
           MOVE GLT-AMOUNT    TO GLX-AMOUNT
           MOVE GLT-DR-CR     TO GLX-DR-CR
           MOVE GLT-BATCH-ID  TO GLX-BATCH-ID
           WRITE GL-EXCEPT-REC
           IF WS-FS-EXCEPT NOT = '00'
               DISPLAY 'GLPOST01 WRITE GLEXCEPT FAILED FS=' WS-FS-EXCEPT
               MOVE 16 TO RETURN-CODE
               STOP RUN
           END-IF
           IF WS-RETURN-CODE < 4
               MOVE 4 TO WS-RETURN-CODE
           END-IF.

      *================================================================*
      * Batch control break                                            *
      *================================================================*
       3000-BATCH-BREAK.
           IF WS-BAT-LINES = ZERO
               EXIT PARAGRAPH
           END-IF
           ADD 1 TO WS-TOT-BATCHES
           MOVE WS-BAT-PREV-ID  TO RL-BAT-ID
           MOVE WS-BAT-LINES    TO RL-BAT-LINES
           MOVE WS-BAT-POSTED   TO RL-BAT-POSTED
           MOVE WS-BAT-REJECTED TO RL-BAT-REJECTED
           MOVE WS-BAT-DR-TOTAL TO RL-BAT-DR
           MOVE WS-BAT-CR-TOTAL TO RL-BAT-CR
           IF WS-BAT-DR-TOTAL = WS-BAT-CR-TOTAL
               MOVE 'BALANCED'       TO RL-BAT-STATUS
           ELSE
               MOVE 'OUT OF BALANCE' TO RL-BAT-STATUS
               ADD 1 TO WS-TOT-BAT-OOB
               IF WS-RETURN-CODE < 4
                   MOVE 4 TO WS-RETURN-CODE
               END-IF
           END-IF
           WRITE REPORT-REC FROM RL-BATCH-LINE.

       3100-BATCH-START.
           MOVE 'N' TO WS-FIRST-BATCH
           MOVE GLT-BATCH-ID TO WS-BAT-PREV-ID
           MOVE ZERO TO WS-BAT-LINES WS-BAT-POSTED WS-BAT-REJECTED
                        WS-BAT-DR-TOTAL WS-BAT-CR-TOTAL.

      *================================================================*
      * Report tail                                                    *
      *================================================================*
       4000-WRITE-TOTALS.
           WRITE REPORT-REC FROM RL-BLANK
           MOVE 'POSTED BY ACCOUNT TYPE' TO RL-SEC-TITLE
           WRITE REPORT-REC FROM RL-SECTION
           WRITE REPORT-REC FROM RL-TYPE-HDR
           PERFORM VARYING WS-TYPE-IDX FROM 1 BY 1
                   UNTIL WS-TYPE-IDX > 5
               MOVE WS-TYP-CODE  (WS-TYPE-IDX) TO RL-TYP-CODE
               MOVE WS-TYP-NAME  (WS-TYPE-IDX) TO RL-TYP-NAME
               MOVE WS-TYP-LINES (WS-TYPE-IDX) TO RL-TYP-LINES
               MOVE WS-TYP-DR    (WS-TYPE-IDX) TO RL-TYP-DR
               MOVE WS-TYP-CR    (WS-TYPE-IDX) TO RL-TYP-CR
               MOVE WS-TYP-NET   (WS-TYPE-IDX) TO RL-TYP-NET
               WRITE REPORT-REC FROM RL-TYPE-LINE
           END-PERFORM

           WRITE REPORT-REC FROM RL-BLANK
           MOVE 'EXCEPTIONS BY REASON' TO RL-SEC-TITLE
           WRITE REPORT-REC FROM RL-SECTION
           WRITE REPORT-REC FROM RL-REASON-HDR
           PERFORM VARYING WS-REASON-IDX FROM 1 BY 1
                   UNTIL WS-REASON-IDX > 7
               MOVE WS-RSN-CODE   (WS-REASON-IDX) TO RL-RSN-CODE
               MOVE WS-RSN-TEXT   (WS-REASON-IDX) TO RL-RSN-TEXT
               MOVE WS-RSN-COUNT  (WS-REASON-IDX) TO RL-RSN-COUNT
               MOVE WS-RSN-AMOUNT (WS-REASON-IDX) TO RL-RSN-AMOUNT
               WRITE REPORT-REC FROM RL-REASON-LINE
           END-PERFORM

           WRITE REPORT-REC FROM RL-BLANK
           MOVE 'RUN TOTALS' TO RL-SEC-TITLE
           WRITE REPORT-REC FROM RL-SECTION
           MOVE 'ACCOUNTS ON MASTER'      TO RL-TC-LABEL
           MOVE WS-TOT-ACCTS              TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'TRANSACTIONS READ'       TO RL-TC-LABEL
           MOVE WS-TOT-READ               TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'TRANSACTIONS POSTED'     TO RL-TC-LABEL
           MOVE WS-TOT-POSTED             TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'TRANSACTIONS REJECTED'   TO RL-TC-LABEL
           MOVE WS-TOT-REJECTED           TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'BATCHES READ'            TO RL-TC-LABEL
           MOVE WS-TOT-BATCHES            TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'BATCHES OUT OF BALANCE'  TO RL-TC-LABEL
           MOVE WS-TOT-BAT-OOB            TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT
           MOVE 'POSTED DEBIT TOTAL'      TO RL-TA-LABEL
           MOVE WS-TOT-DR-POSTED          TO RL-TA-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-AMOUNT
           MOVE 'POSTED CREDIT TOTAL'     TO RL-TA-LABEL
           MOVE WS-TOT-CR-POSTED          TO RL-TA-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-AMOUNT
           MOVE 'POSTED NET SIGNED'       TO RL-TA-LABEL
           MOVE WS-TOT-NET-POSTED         TO RL-TA-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-AMOUNT
           MOVE 'REJECTED DEBIT TOTAL'    TO RL-TA-LABEL
           MOVE WS-TOT-DR-REJECT          TO RL-TA-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-AMOUNT
           MOVE 'REJECTED CREDIT TOTAL'   TO RL-TA-LABEL
           MOVE WS-TOT-CR-REJECT          TO RL-TA-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-AMOUNT
           MOVE 'HIGHEST RETURN CODE'     TO RL-TC-LABEL
           MOVE WS-RETURN-CODE            TO RL-TC-VALUE
           WRITE REPORT-REC FROM RL-TOTAL-COUNT.

       9000-TERMINATE.
           CLOSE TRAN-FILE POSTED-FILE EXCEPT-FILE REPORT-FILE
           DISPLAY 'GLPOST01 ENDED  READ='   WS-TOT-READ
                   ' POSTED='   WS-TOT-POSTED
                   ' REJECTED=' WS-TOT-REJECTED
                   ' RC=' WS-RETURN-CODE.
