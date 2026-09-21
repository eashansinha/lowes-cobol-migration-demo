       IDENTIFICATION DIVISION.
       PROGRAM-ID.    PRCUPD01.
       AUTHOR.        PRICING SYSTEMS - MERCH IT.
      *================================================================*
      * PRCUPD01 - NIGHTLY PROMOTIONAL PRICE UPDATE                    *
      *                                                                *
      * JCL      : jcl/PRCUPD01.jcl  (step PRCUPD, PROC PRCUPD01)      *
      * Schedule : NIGHTLY 01:30 after MERCH item master unload,       *
      *            predecessor of INVREPL01 (see schedules/nightly.txt)*
      *                                                                *
      * FUNCTION                                                       *
      *  Phase 1  Expire promo prices whose end date has passed and    *
      *           revert them to the regular price (BR-E1).            *
      *  Phase 2  Read the SORTED promo feed, match each promo to the  *
      *           item master, resolve the target pricing regions,     *
      *           compute the promo price (percent / fixed / BOGO),    *
      *           apply region overrides via PRCRGN01, apply the       *
      *           margin floor and .x9 price-ending rounding, then     *
      *           update PRCDB.ITEM_PRICE and insert PRCDB.PRICE_HIST. *
      *  Phase 3  Write the audit / exception report and totals.       *
      *                                                                *
      * DD NAMES                                                       *
      *  SYSIN     control cards        RUNDATE=YYYYMMDD               *
      *  PROMOIN   sorted promo feed    PROMOREC (80)                  *
      *  ITEMMAST  item master unload   ITEMMAST (80) sorted by SKU    *
      *  STORERGN  STORE_REGION unload  CSV                            *
      *  ITMPRCI   ITEM_PRICE  unload   CSV  (DB2 stand-in, input)     *
      *  ITMPRCO   ITEM_PRICE  after    CSV  (DB2 stand-in, output)    *
      *  PRCHSTI   PRICE_HIST  unload   CSV  (DB2 stand-in, input)     *
      *  PRCHSTO   PRICE_HIST  after    CSV  (DB2 stand-in, output)    *
      *  PRCRPT    audit / exception report (132)                      *
      *                                                                *
      * RETURN CODES  0 clean   4 warnings/exceptions   8 fatal        *
      *                                                                *
      * NOTE ON DB2: in the production estate the 8xxx-DB2-* paragraphs*
      * are EXEC SQL statements against PRCDB. In this demo estate DB2  *
      * is unreachable, so the same paragraphs read/write CSV unloads. *
      * The SQL each paragraph stands in for is shown in its comment.  *
      *                                                                *
      * CHANGE LOG                                                     *
      *  2016-05-09  MERCH-2210  initial                               *
      *  2018-11-20  MERCH-3990  .x9 price-ending rounding (BR-P4)     *
      *  2019-03-11  MERCH-4471  call PRCRGN01 for region overrides    *
      *  2022-08-15  MERCH-6875  clearance stacking markdown (BR-P6)   *
      *  2024-02-02  MERCH-8102  phase 1 promo expiry                  *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SYSIN-FILE   ASSIGN TO SYSIN
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-SYSIN.
           SELECT PROMO-FILE   ASSIGN TO PROMOIN
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-PROMO.
           SELECT ITEM-FILE    ASSIGN TO ITEMMAST
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-ITEM.
           SELECT STORE-FILE   ASSIGN TO STORERGN
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-STORE.
           SELECT PRICE-IN     ASSIGN TO ITMPRCI
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-PRCI.
           SELECT PRICE-OUT    ASSIGN TO ITMPRCO
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-PRCO.
           SELECT HIST-IN      ASSIGN TO PRCHSTI
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-HSTI.
           SELECT HIST-OUT     ASSIGN TO PRCHSTO
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-HSTO.
           SELECT REPORT-FILE  ASSIGN TO PRCRPT
                  ORGANIZATION IS LINE SEQUENTIAL
                  FILE STATUS IS WS-FS-RPT.

       DATA DIVISION.
       FILE SECTION.
       FD  SYSIN-FILE.
       01  SYSIN-REC                   PIC X(80).
       FD  PROMO-FILE.
           COPY PROMOREC.
       FD  ITEM-FILE.
           COPY ITEMMAST.
       FD  STORE-FILE.
       01  STORE-CSV-REC               PIC X(200).
       FD  PRICE-IN.
       01  PRICE-IN-REC                PIC X(200).
       FD  PRICE-OUT.
       01  PRICE-OUT-REC               PIC X(200).
       FD  HIST-IN.
       01  HIST-IN-REC                 PIC X(200).
       FD  HIST-OUT.
       01  HIST-OUT-REC                PIC X(200).
       FD  REPORT-FILE.
       01  REPORT-REC                  PIC X(132).

       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-ID               PIC X(08) VALUE 'PRCUPD01'.

       01  WS-FILE-STATUS.
           05  WS-FS-SYSIN             PIC X(02).
           05  WS-FS-PROMO             PIC X(02).
           05  WS-FS-ITEM              PIC X(02).
           05  WS-FS-STORE             PIC X(02).
           05  WS-FS-PRCI              PIC X(02).
           05  WS-FS-PRCO              PIC X(02).
           05  WS-FS-HSTI              PIC X(02).
           05  WS-FS-HSTO              PIC X(02).
           05  WS-FS-RPT               PIC X(02).

       01  WS-FLAGS.
           05  WS-EOF-PROMO            PIC X(01) VALUE 'N'.
           05  WS-EOF-ITEM             PIC X(01) VALUE 'N'.
           05  WS-EOF-STORE            PIC X(01) VALUE 'N'.
           05  WS-EOF-PRICE            PIC X(01) VALUE 'N'.
           05  WS-EOF-HIST             PIC X(01) VALUE 'N'.
           05  WS-EOF-SYSIN            PIC X(01) VALUE 'N'.
           05  WS-FLOOR-APPLIED        PIC X(01) VALUE 'N'.
           05  WS-PROMO-OK             PIC X(01) VALUE 'Y'.
           05  WS-HEADER-SKIPPED       PIC X(01) VALUE 'N'.

       01  WS-CONTROL.
           05  WS-RUN-DATE             PIC 9(08) VALUE ZERO.
           05  WS-RUN-DATE-X REDEFINES WS-RUN-DATE.
               10  WS-RUN-YYYY         PIC X(04).
               10  WS-RUN-MM           PIC X(02).
               10  WS-RUN-DD           PIC X(02).
           05  WS-CLEARANCE-MARKDOWN   PIC 9(03) VALUE 090.
           05  WS-SQLCODE              PIC S9(09) COMP VALUE 0.
               88  SQL-OK              VALUE 0.
               88  SQL-NOT-FOUND       VALUE +100.

       01  WS-COUNTERS.
           05  WS-CNT-PROMOS-READ      PIC 9(07) VALUE 0.
           05  WS-CNT-PRICES-APPLIED   PIC 9(07) VALUE 0.
           05  WS-CNT-NO-CHANGE        PIC 9(07) VALUE 0.
           05  WS-CNT-FLOORED          PIC 9(07) VALUE 0.
           05  WS-CNT-RGN-OVERRIDE     PIC 9(07) VALUE 0.
           05  WS-CNT-SKIPPED          PIC 9(07) VALUE 0.
           05  WS-CNT-EXCEPTIONS       PIC 9(07) VALUE 0.
           05  WS-CNT-EXPIRED          PIC 9(07) VALUE 0.
           05  WS-CNT-HIST-WRITTEN     PIC 9(07) VALUE 0.
           05  WS-CNT-PRICE-ROWS       PIC 9(07) VALUE 0.
           05  WS-CNT-ITEMS            PIC 9(07) VALUE 0.
           05  WS-CNT-STORES           PIC 9(07) VALUE 0.

      *----------------------------------------------------------------*
      * Item master table (VSAM KSDS stand-in, binary search on SKU)   *
      *----------------------------------------------------------------*
       01  WS-ITEM-TABLE.
           05  WS-IT-COUNT             PIC 9(05) VALUE 0.
           05  WS-IT-ENTRY OCCURS 1 TO 5000 TIMES
                                       DEPENDING ON WS-IT-COUNT
                                       ASCENDING KEY IS WS-IT-SKU
                                       INDEXED BY IT-IDX.
               10  WS-IT-SKU           PIC X(08).
               10  WS-IT-DESC          PIC X(30).
               10  WS-IT-DEPT          PIC X(04).
               10  WS-IT-CLASS         PIC X(04).
               10  WS-IT-STATUS        PIC X(01).
               10  WS-IT-UNIT-COST     PIC 9(05)V99.
               10  WS-IT-REG-PRICE     PIC 9(05)V99.
               10  WS-IT-FLOOR-PCT     PIC 9(03).

      *----------------------------------------------------------------*
      * STORE_REGION reference table                                   *
      *----------------------------------------------------------------*
       01  WS-STORE-TABLE.
           05  WS-ST-COUNT             PIC 9(04) VALUE 0.
           05  WS-ST-ENTRY OCCURS 500 TIMES INDEXED BY ST-IDX.
               10  WS-ST-STORE-NBR     PIC X(04).
               10  WS-ST-REGION-CD     PIC X(02).

      *----------------------------------------------------------------*
      * ITEM_PRICE working set (cursor result set stand-in)            *
      *----------------------------------------------------------------*
       01  WS-PRICE-TABLE.
           05  WS-PT-COUNT             PIC 9(05) VALUE 0.
           05  WS-PT-ENTRY OCCURS 5000 TIMES INDEXED BY PT-IDX.
               10  WS-PT-SKU           PIC X(08).
               10  WS-PT-REGION-CD     PIC X(02).
               10  WS-PT-REG-PRICE     PIC 9(05)V99.
               10  WS-PT-CURR-PRICE    PIC 9(05)V99.
               10  WS-PT-PRICE-TYPE    PIC X(01).
               10  WS-PT-PROMO-ID      PIC X(10).
               10  WS-PT-EFF-DT        PIC 9(08).
               10  WS-PT-END-DT        PIC 9(08).
               10  WS-PT-LAST-UPD-JOB  PIC X(08).
               10  WS-PT-UPDATED       PIC X(01).

       01  WS-ALL-REGIONS.
           05  WS-REGION-LIST          PIC X(10) VALUE 'NESEMWWCNC'.
           05  WS-REGION-ARRAY REDEFINES WS-REGION-LIST.
               10  WS-REGION-ITEM      PIC X(02) OCCURS 5 TIMES.

       01  WS-TARGET-REGIONS.
           05  WS-TR-COUNT             PIC 9(01) VALUE 0.
           05  WS-TR-REGION            PIC X(02) OCCURS 5 TIMES.
           05  WS-TR-IDX               PIC 9(01).

       01  WS-PRICING-WORK.
           05  WS-BASE-PRICE           PIC 9(05)V99.
           05  WS-WORK-PRICE           PIC 9(05)V99.
           05  WS-FLOOR-PRICE          PIC 9(05)V99.
           05  WS-OLD-PRICE            PIC 9(05)V99.
           05  WS-CENTS                PIC S9(09).
           05  WS-ENDING               PIC 9(01).
           05  WS-CHANGE-RSN           PIC X(06).
           05  WS-CUR-REGION           PIC X(02).
           05  WS-LAST-HIST-SEQ        PIC 9(09) VALUE 0.
           05  WS-RGN-IDX              PIC 9(01).

       01  WS-CSV-FIELDS.
           05  WS-F01                  PIC X(30).
           05  WS-F02                  PIC X(30).
           05  WS-F03                  PIC X(30).
           05  WS-F04                  PIC X(30).
           05  WS-F05                  PIC X(30).
           05  WS-F06                  PIC X(30).
           05  WS-F07                  PIC X(30).
           05  WS-F08                  PIC X(30).
           05  WS-F09                  PIC X(30).
           05  WS-CSV-OUT              PIC X(200).
           05  WS-PRICE-EDIT           PIC Z(04)9.99.
           05  WS-PRICE-EDIT2          PIC Z(04)9.99.
           05  WS-SEQ-EDIT             PIC Z(08)9.
           05  WS-DATE-ISO             PIC X(10).
           05  WS-DATE-ISO2            PIC X(10).
           05  WS-DATE-NUM             PIC 9(08).
           05  WS-DATE-NUM-X REDEFINES WS-DATE-NUM.
               10  WS-DN-YYYY          PIC X(04).
               10  WS-DN-MM            PIC X(02).
               10  WS-DN-DD            PIC X(02).

           COPY PRICEHST.
           COPY DCLITMPR.
           COPY DCLPRHST.
           COPY DCLSTRGN.
           COPY PRCRGNCA.

      *----------------------------------------------------------------*
      * Report layouts                                                 *
      *----------------------------------------------------------------*
       01  WS-REPORT-CTL.
           05  WS-PAGE-NBR             PIC 9(04) VALUE 0.
           05  WS-LINE-CNT             PIC 9(02) VALUE 99.
           05  WS-LINES-PER-PAGE       PIC 9(02) VALUE 55.

       01  RPT-HEADER-1.
           05  FILLER                  PIC X(10) VALUE 'PRCUPD01  '.
           05  FILLER                  PIC X(53) VALUE
               'NIGHTLY PROMOTIONAL PRICE UPDATE - AUDIT / EXCEPTIONS'.
           05  FILLER                  PIC X(29) VALUE SPACES.
           05  FILLER                  PIC X(09) VALUE 'RUN DATE '.
           05  RH1-DATE                PIC X(10).
           05  FILLER                  PIC X(08) VALUE '   PAGE '.
           05  RH1-PAGE                PIC ZZZ9.
           05  FILLER                  PIC X(09) VALUE SPACES.

       01  RPT-HEADER-2.
           05  FILLER                  PIC X(10) VALUE 'PROMO-ID'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(08) VALUE 'SKU'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(02) VALUE 'RG'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(01) VALUE 'T'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(10) VALUE ' REG-PRICE'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(10) VALUE ' OLD-PRICE'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(10) VALUE ' NEW-PRICE'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(06) VALUE 'REASON'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(06) VALUE 'OVERRD'.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  FILLER                  PIC X(08) VALUE 'STATUS'.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  FILLER                  PIC X(40) VALUE 'MESSAGE'.
           05  FILLER                  PIC X(07) VALUE SPACES.

       01  RPT-HEADER-3.
           05  FILLER                  PIC X(132) VALUE ALL '-'.

       01  RPT-DETAIL.
           05  RD-PROMO-ID             PIC X(10).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-SKU                  PIC X(08).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-REGION               PIC X(02).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-TYPE                 PIC X(01).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-REG-PRICE            PIC Z(06)9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-OLD-PRICE            PIC Z(06)9.99.
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-NEW-PRICE            PIC Z(06)9.99.
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-RSN                  PIC X(06).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-OVERRIDE             PIC X(06).
           05  FILLER                  PIC X(02) VALUE SPACES.
           05  RD-STATUS               PIC X(08).
           05  FILLER                  PIC X(01) VALUE SPACE.
           05  RD-MESSAGE              PIC X(40).
           05  FILLER                  PIC X(07) VALUE SPACES.

       01  RPT-TOTAL-LINE.
           05  FILLER                  PIC X(04) VALUE SPACES.
           05  RT-LABEL                PIC X(40).
           05  RT-VALUE                PIC Z(06)9.
           05  FILLER                  PIC X(81) VALUE SPACES.

       01  RPT-BLANK                   PIC X(132) VALUE SPACES.

       01  WS-ITEM-PRICE-HDR.
           05  FILLER                  PIC X(51) VALUE
               'SKU,REGION_CD,REG_PRICE,CURR_PRICE,PRICE_TYPE,PROMO'.
           05  FILLER                  PIC X(42) VALUE
               '_ID,PROMO_EFF_DT,PROMO_END_DT,LAST_UPD_JOB'.
           05  FILLER                  PIC X(107) VALUE SPACES.

       PROCEDURE DIVISION.
       0000-MAIN.
           PERFORM 1000-INITIALISE
           PERFORM 3000-EXPIRE-LAPSED-PROMOS
           PERFORM 2000-PROCESS-PROMO
               UNTIL WS-EOF-PROMO = 'Y'
           PERFORM 8500-DB2-COMMIT-ITEM-PRICE
           PERFORM 9000-WRITE-TOTALS
           PERFORM 9500-TERMINATE
           IF WS-CNT-EXCEPTIONS > 0 OR WS-CNT-SKIPPED > 0
               MOVE 4 TO RETURN-CODE
           ELSE
               MOVE 0 TO RETURN-CODE
           END-IF
           GOBACK.

      *================================================================*
      * 1000 - INITIALISATION                                          *
      *================================================================*
       1000-INITIALISE.
           PERFORM 1100-READ-CONTROL-CARDS
           OPEN INPUT  PROMO-FILE ITEM-FILE STORE-FILE
           OPEN OUTPUT REPORT-FILE HIST-OUT
           PERFORM 1200-LOAD-ITEM-MASTER
           PERFORM 1300-LOAD-STORE-REGION
           PERFORM 8100-DB2-OPEN-ITEM-PRICE-CURSOR
           PERFORM 8600-DB2-COPY-PRICE-HIST
           PERFORM 9100-PRINT-HEADINGS
           PERFORM 2100-READ-PROMO.

       1100-READ-CONTROL-CARDS.
           OPEN INPUT SYSIN-FILE
           IF WS-FS-SYSIN NOT = '00'
               DISPLAY 'PRCUPD01 E001 CANNOT OPEN SYSIN FS='
                       WS-FS-SYSIN
               MOVE 8 TO RETURN-CODE
               STOP RUN
           END-IF
           PERFORM UNTIL WS-EOF-SYSIN = 'Y'
               READ SYSIN-FILE
                   AT END MOVE 'Y' TO WS-EOF-SYSIN
                   NOT AT END
                       IF SYSIN-REC(1:8) = 'RUNDATE='
                           MOVE SYSIN-REC(9:8) TO WS-RUN-DATE
                       END-IF
               END-READ
           END-PERFORM
           CLOSE SYSIN-FILE
           IF WS-RUN-DATE = ZERO
               DISPLAY 'PRCUPD01 E002 RUNDATE CONTROL CARD MISSING'
               MOVE 8 TO RETURN-CODE
               STOP RUN
           END-IF.

       1200-LOAD-ITEM-MASTER.
           PERFORM UNTIL WS-EOF-ITEM = 'Y'
               READ ITEM-FILE
                   AT END MOVE 'Y' TO WS-EOF-ITEM
                   NOT AT END
                       ADD 1 TO WS-IT-COUNT
                       MOVE IM-SKU        TO WS-IT-SKU (WS-IT-COUNT)
                       MOVE IM-DESC       TO WS-IT-DESC (WS-IT-COUNT)
                       MOVE IM-DEPT       TO WS-IT-DEPT (WS-IT-COUNT)
                       MOVE IM-CLASS      TO WS-IT-CLASS (WS-IT-COUNT)
                       MOVE IM-STATUS     TO WS-IT-STATUS (WS-IT-COUNT)
                       MOVE IM-UNIT-COST  TO
                            WS-IT-UNIT-COST (WS-IT-COUNT)
                       MOVE IM-REG-PRICE  TO
                            WS-IT-REG-PRICE (WS-IT-COUNT)
                       MOVE IM-FLOOR-PCT  TO
                            WS-IT-FLOOR-PCT (WS-IT-COUNT)
               END-READ
           END-PERFORM
           MOVE WS-IT-COUNT TO WS-CNT-ITEMS.

      *   Stand-in for: SELECT STORE_NBR, REGION_CD                    *
      *                 FROM PRCDB.STORE_REGION                        *
       1300-LOAD-STORE-REGION.
           MOVE 'N' TO WS-HEADER-SKIPPED
           PERFORM UNTIL WS-EOF-STORE = 'Y'
               READ STORE-FILE
                   AT END MOVE 'Y' TO WS-EOF-STORE
                   NOT AT END
                       IF WS-HEADER-SKIPPED = 'N'
                           MOVE 'Y' TO WS-HEADER-SKIPPED
                       ELSE
                           MOVE SPACES TO WS-F01 WS-F02 WS-F03 WS-F04
                           UNSTRING STORE-CSV-REC DELIMITED BY ','
                               INTO WS-F01 WS-F02 WS-F03 WS-F04
                           END-UNSTRING
                           ADD 1 TO WS-ST-COUNT
                           MOVE WS-F01 TO WS-ST-STORE-NBR (WS-ST-COUNT)
                           MOVE WS-F04 TO WS-ST-REGION-CD (WS-ST-COUNT)
                       END-IF
               END-READ
           END-PERFORM
           MOVE WS-ST-COUNT TO WS-CNT-STORES.

      *================================================================*
      * 2000 - PROCESS ONE PROMO RECORD                                *
      *================================================================*
       2000-PROCESS-PROMO.
           ADD 1 TO WS-CNT-PROMOS-READ
           MOVE 'Y'    TO WS-PROMO-OK
           MOVE 0      TO WS-TR-COUNT
           MOVE SPACES TO WS-CUR-REGION
           INITIALIZE PRCRGN-COMMAREA
           PERFORM 2200-VALIDATE-PROMO
           IF WS-PROMO-OK = 'Y'
               PERFORM 2300-RESOLVE-TARGET-REGIONS
           END-IF
           IF WS-PROMO-OK = 'Y'
               PERFORM 2400-COMPUTE-BASE-PRICE
               PERFORM VARYING WS-TR-IDX FROM 1 BY 1
                       UNTIL WS-TR-IDX > WS-TR-COUNT
                   MOVE WS-TR-REGION (WS-TR-IDX) TO WS-CUR-REGION
                   PERFORM 2500-PRICE-ONE-REGION
               END-PERFORM
           END-IF
           PERFORM 2100-READ-PROMO.

       2100-READ-PROMO.
           READ PROMO-FILE
               AT END MOVE 'Y' TO WS-EOF-PROMO
           END-READ.

      *----------------------------------------------------------------*
      * BR-V1..V5 promo validation                                     *
      *----------------------------------------------------------------*
       2200-VALIDATE-PROMO.
           IF NOT PR-TYPE-VALID
               MOVE 'INVALID PROMO TYPE' TO RD-MESSAGE
               PERFORM 7100-REPORT-EXCEPTION
           END-IF
           IF WS-PROMO-OK = 'Y'
               SEARCH ALL WS-IT-ENTRY
                   AT END
                       MOVE 'SKU NOT ON ITEM MASTER' TO RD-MESSAGE
                       PERFORM 7100-REPORT-EXCEPTION
                   WHEN WS-IT-SKU (IT-IDX) = PR-SKU
                       CONTINUE
               END-SEARCH
           END-IF
           IF WS-PROMO-OK = 'Y'
               IF WS-IT-STATUS (IT-IDX) = 'D'
                   MOVE 'ITEM DISCONTINUED' TO RD-MESSAGE
                   PERFORM 7100-REPORT-EXCEPTION
               END-IF
           END-IF
           IF WS-PROMO-OK = 'Y'
               IF PR-EFF-DATE > WS-RUN-DATE
                   MOVE 'NOT YET EFFECTIVE' TO RD-MESSAGE
                   PERFORM 7200-REPORT-SKIP
               ELSE
                   IF PR-END-DATE < WS-RUN-DATE
                       MOVE 'PROMO ALREADY ENDED' TO RD-MESSAGE
                       PERFORM 7200-REPORT-SKIP
                   END-IF
               END-IF
           END-IF.

      *----------------------------------------------------------------*
      * BR-T1..T3 target region resolution                             *
      *----------------------------------------------------------------*
       2300-RESOLVE-TARGET-REGIONS.
           MOVE 0 TO WS-TR-COUNT
           EVALUATE TRUE
               WHEN PR-STORE-NBR NOT = SPACES
                   SET ST-IDX TO 1
                   SEARCH WS-ST-ENTRY
                       AT END
                           MOVE 'STORE NOT ON STORE_REGION'
                               TO RD-MESSAGE
                           PERFORM 7100-REPORT-EXCEPTION
                       WHEN WS-ST-STORE-NBR (ST-IDX) = PR-STORE-NBR
                           MOVE 1 TO WS-TR-COUNT
                           MOVE WS-ST-REGION-CD (ST-IDX)
                             TO WS-TR-REGION (1)
                   END-SEARCH
               WHEN PR-REGION-CD = SPACES
                   MOVE 5 TO WS-TR-COUNT
                   PERFORM VARYING WS-RGN-IDX FROM 1 BY 1
                           UNTIL WS-RGN-IDX > 5
                       MOVE WS-REGION-ITEM (WS-RGN-IDX)
                         TO WS-TR-REGION (WS-RGN-IDX)
                   END-PERFORM
               WHEN OTHER
                   MOVE 1 TO WS-TR-COUNT
                   MOVE PR-REGION-CD TO WS-TR-REGION (1)
           END-EVALUATE.

      *----------------------------------------------------------------*
      * BR-P1..P3 base promo price                                     *
      *----------------------------------------------------------------*
       2400-COMPUTE-BASE-PRICE.
           EVALUATE TRUE
               WHEN PR-TYPE-PERCENT
                   COMPUTE WS-BASE-PRICE =
                       WS-IT-REG-PRICE (IT-IDX)
                       * (100 - PR-PROMO-VALUE) / 100
               WHEN PR-TYPE-FIXED
                   MOVE PR-PROMO-VALUE TO WS-BASE-PRICE
               WHEN PR-TYPE-BOGO
                   COMPUTE WS-BASE-PRICE = WS-IT-REG-PRICE (IT-IDX) / 2
           END-EVALUATE.

      *----------------------------------------------------------------*
      * Price one (promo, region) pair                                 *
      *----------------------------------------------------------------*
       2500-PRICE-ONE-REGION.
           MOVE 'N'     TO WS-FLOOR-APPLIED
           MOVE 'PROMO' TO WS-CHANGE-RSN
           PERFORM 2510-CALL-REGION-RULES
           EVALUATE TRUE
               WHEN NOT RGN-RC-OK
                   MOVE 'UNKNOWN REGION CODE' TO RD-MESSAGE
                   PERFORM 7100-REPORT-EXCEPTION
               WHEN RGN-SKIP
                   STRING 'REGION RULE ' RGN-OUT-OVERRIDE
                       DELIMITED BY SIZE INTO RD-MESSAGE
                   END-STRING
                   PERFORM 7200-REPORT-SKIP
               WHEN OTHER
                   MOVE RGN-OUT-PRICE TO WS-WORK-PRICE
                   IF RGN-OUT-OVERRIDE NOT = SPACES
                       MOVE 'RGNOVR' TO WS-CHANGE-RSN
                       ADD 1 TO WS-CNT-RGN-OVERRIDE
                   END-IF
                   IF WS-IT-STATUS (IT-IDX) = 'C'
                       PERFORM 2620-CLEARANCE-PRICING
                   ELSE
                       PERFORM 2610-STANDARD-PRICING
                   END-IF
                   IF WS-FLOOR-APPLIED = 'Y'
                       MOVE 'FLOOR' TO WS-CHANGE-RSN
                       ADD 1 TO WS-CNT-FLOORED
                   END-IF
                   PERFORM 2700-APPLY-TO-ITEM-PRICE
           END-EVALUATE.

       2510-CALL-REGION-RULES.
           MOVE WS-CUR-REGION           TO RGN-IN-REGION-CD
           MOVE WS-IT-DEPT (IT-IDX)     TO RGN-IN-DEPT
           MOVE PR-PROMO-TYPE           TO RGN-IN-PROMO-TYPE
           MOVE WS-IT-REG-PRICE (IT-IDX) TO RGN-IN-REG-PRICE
           MOVE WS-BASE-PRICE           TO RGN-IN-PRICE
           CALL 'PRCRGN01' USING PRCRGN-COMMAREA.

      *----------------------------------------------------------------*
      * BR-P4 / BR-P5 : standard items                                 *
      *   round down to a .x9 ending, then enforce the margin floor;   *
      *   a floored price is rounded UP to the next .x9 ending so the  *
      *   shelf price never drops below the floor.                     *
      *----------------------------------------------------------------*
       2610-STANDARD-PRICING.
           PERFORM 2650-ROUND-DOWN-X9
           PERFORM 2660-APPLY-MARGIN-FLOOR
           IF WS-FLOOR-APPLIED = 'Y'
               PERFORM 2670-ROUND-UP-X9
           END-IF.

      *----------------------------------------------------------------*
      * BR-P6 : clearance items (IM-STATUS = C)                        *
      *   take an additional 10% stacking markdown on the promo price  *
      *   before the margin floor and .x9 rounding are applied.        *
      *----------------------------------------------------------------*
       2620-CLEARANCE-PRICING.
           COMPUTE WS-WORK-PRICE =
               WS-WORK-PRICE * WS-CLEARANCE-MARKDOWN / 100
           PERFORM 2660-APPLY-MARGIN-FLOOR
           PERFORM 2650-ROUND-DOWN-X9.

       2650-ROUND-DOWN-X9.
           COMPUTE WS-CENTS = WS-WORK-PRICE * 100
           COMPUTE WS-ENDING = FUNCTION MOD (WS-CENTS, 10)
           IF WS-ENDING NOT = 9
               COMPUTE WS-CENTS = WS-CENTS - WS-ENDING - 1
               IF WS-CENTS < 9
                   MOVE 9 TO WS-CENTS
               END-IF
               COMPUTE WS-WORK-PRICE = WS-CENTS / 100
           END-IF.

       2660-APPLY-MARGIN-FLOOR.
           COMPUTE WS-FLOOR-PRICE =
               WS-IT-UNIT-COST (IT-IDX)
               * (100 + WS-IT-FLOOR-PCT (IT-IDX)) / 100
           IF WS-WORK-PRICE < WS-FLOOR-PRICE
               MOVE WS-FLOOR-PRICE TO WS-WORK-PRICE
               MOVE 'Y' TO WS-FLOOR-APPLIED
           END-IF.

       2670-ROUND-UP-X9.
           COMPUTE WS-CENTS = WS-WORK-PRICE * 100
           COMPUTE WS-ENDING = FUNCTION MOD (WS-CENTS, 10)
           IF WS-ENDING NOT = 9
               COMPUTE WS-CENTS = WS-CENTS - WS-ENDING + 9
               COMPUTE WS-WORK-PRICE = WS-CENTS / 100
           END-IF.

      *----------------------------------------------------------------*
      * BR-U1..U3 : apply computed price to ITEM_PRICE + PRICE_HIST    *
      *----------------------------------------------------------------*
       2700-APPLY-TO-ITEM-PRICE.
           MOVE PR-SKU        TO IP-SKU
           MOVE WS-CUR-REGION TO IP-REGION-CD
           PERFORM 8200-DB2-SELECT-ITEM-PRICE
           EVALUATE TRUE
               WHEN SQL-NOT-FOUND
                   MOVE 'NO ITEM_PRICE ROW FOR REGION' TO RD-MESSAGE
                   PERFORM 7100-REPORT-EXCEPTION
               WHEN IP-CURR-PRICE = WS-WORK-PRICE
                AND IP-PROMO-ID   = PR-PROMO-ID
                   ADD 1 TO WS-CNT-NO-CHANGE
                   MOVE IP-CURR-PRICE TO WS-OLD-PRICE
                   MOVE 'NOCHG'   TO RD-STATUS
                   MOVE 'PROMO ALREADY IN EFFECT' TO RD-MESSAGE
                   PERFORM 7300-REPORT-PRICE-LINE
               WHEN OTHER
                   MOVE IP-CURR-PRICE TO WS-OLD-PRICE
                   MOVE WS-WORK-PRICE TO IP-CURR-PRICE
                   MOVE 'P'           TO IP-PRICE-TYPE
                   MOVE PR-PROMO-ID   TO IP-PROMO-ID
                   MOVE PR-EFF-DATE   TO IP-PROMO-EFF-DT
                   MOVE PR-END-DATE   TO IP-PROMO-END-DT
                   MOVE WS-PROGRAM-ID TO IP-LAST-UPD-JOB
                   PERFORM 8300-DB2-UPDATE-ITEM-PRICE
                   MOVE PR-PROMO-ID   TO PH-PROMO-ID
                   PERFORM 8400-DB2-INSERT-PRICE-HIST
                   ADD 1 TO WS-CNT-PRICES-APPLIED
                   MOVE 'UPDATED' TO RD-STATUS
                   MOVE SPACES    TO RD-MESSAGE
                   PERFORM 7300-REPORT-PRICE-LINE
           END-EVALUATE.

      *================================================================*
      * 3000 - PHASE 1: EXPIRE LAPSED PROMOS (BR-E1)                   *
      *================================================================*
       3000-EXPIRE-LAPSED-PROMOS.
           PERFORM VARYING PT-IDX FROM 1 BY 1
                   UNTIL PT-IDX > WS-PT-COUNT
               IF WS-PT-PRICE-TYPE (PT-IDX) = 'P'
                AND WS-PT-END-DT (PT-IDX) < WS-RUN-DATE
                   PERFORM 3100-EXPIRE-ONE-ROW
               END-IF
           END-PERFORM.

       3100-EXPIRE-ONE-ROW.
           PERFORM 8210-DB2-FETCH-ROW-AT-CURSOR
           MOVE IP-CURR-PRICE TO WS-OLD-PRICE
           MOVE IP-REG-PRICE  TO WS-WORK-PRICE
           MOVE IP-PROMO-ID   TO PH-PROMO-ID
           MOVE IP-PROMO-ID   TO RD-PROMO-ID
           MOVE IP-SKU        TO RD-SKU
           MOVE IP-REGION-CD  TO RD-REGION
           MOVE IP-REGION-CD  TO WS-CUR-REGION
           MOVE 'EXPIRE'      TO WS-CHANGE-RSN
           MOVE IP-REG-PRICE  TO IP-CURR-PRICE
           MOVE 'R'           TO IP-PRICE-TYPE
           MOVE SPACES        TO IP-PROMO-ID
           MOVE ZERO          TO IP-PROMO-EFF-DT IP-PROMO-END-DT
           MOVE WS-PROGRAM-ID TO IP-LAST-UPD-JOB
           PERFORM 8300-DB2-UPDATE-ITEM-PRICE
           PERFORM 8400-DB2-INSERT-PRICE-HIST
           ADD 1 TO WS-CNT-EXPIRED
           MOVE SPACES        TO RPT-DETAIL
           MOVE PH-PROMO-ID   TO RD-PROMO-ID
           MOVE IP-SKU        TO RD-SKU
           MOVE IP-REGION-CD  TO RD-REGION
           MOVE '-'           TO RD-TYPE
           MOVE IP-REG-PRICE  TO RD-REG-PRICE
           MOVE WS-OLD-PRICE  TO RD-OLD-PRICE
           MOVE WS-WORK-PRICE TO RD-NEW-PRICE
           MOVE WS-CHANGE-RSN TO RD-RSN
           MOVE 'EXPIRED'     TO RD-STATUS
           MOVE 'PROMO END DATE PASSED' TO RD-MESSAGE
           PERFORM 9200-WRITE-DETAIL.

      *================================================================*
      * 7000 - REPORT LINE BUILDERS                                    *
      *================================================================*
       7100-REPORT-EXCEPTION.
           MOVE 'N' TO WS-PROMO-OK
           ADD 1 TO WS-CNT-EXCEPTIONS
           MOVE 'REJECT' TO RD-STATUS
           PERFORM 7400-REPORT-PROMO-LINE.

       7200-REPORT-SKIP.
           MOVE 'N' TO WS-PROMO-OK
           ADD 1 TO WS-CNT-SKIPPED
           MOVE 'SKIP' TO RD-STATUS
           PERFORM 7400-REPORT-PROMO-LINE.

       7300-REPORT-PRICE-LINE.
           MOVE PR-PROMO-ID              TO RD-PROMO-ID
           MOVE PR-SKU                   TO RD-SKU
           MOVE WS-CUR-REGION            TO RD-REGION
           MOVE PR-PROMO-TYPE            TO RD-TYPE
           MOVE WS-IT-REG-PRICE (IT-IDX) TO RD-REG-PRICE
           MOVE WS-OLD-PRICE             TO RD-OLD-PRICE
           MOVE WS-WORK-PRICE            TO RD-NEW-PRICE
           MOVE WS-CHANGE-RSN            TO RD-RSN
           MOVE RGN-OUT-OVERRIDE         TO RD-OVERRIDE
           PERFORM 9200-WRITE-DETAIL.

       7400-REPORT-PROMO-LINE.
           MOVE PR-PROMO-ID   TO RD-PROMO-ID
           MOVE PR-SKU        TO RD-SKU
           MOVE WS-CUR-REGION TO RD-REGION
           IF WS-TR-COUNT = 0
               MOVE PR-REGION-CD TO RD-REGION
           END-IF
           MOVE PR-PROMO-TYPE TO RD-TYPE
           MOVE ZERO          TO RD-REG-PRICE RD-OLD-PRICE
                                 RD-NEW-PRICE
           MOVE SPACES        TO RD-RSN
           IF RGN-SKIP
               MOVE RGN-OUT-OVERRIDE TO RD-OVERRIDE
           ELSE
               MOVE SPACES           TO RD-OVERRIDE
           END-IF
           PERFORM 9200-WRITE-DETAIL.

      *================================================================*
      * 8000 - DB2 ACCESS LAYER (CSV STAND-IN FOR EXEC SQL)            *
      *================================================================*
      *  EXEC SQL DECLARE PRICE_CSR CURSOR WITH HOLD FOR               *
      *    SELECT SKU, REGION_CD, REG_PRICE, CURR_PRICE, PRICE_TYPE,   *
      *           PROMO_ID, PROMO_EFF_DT, PROMO_END_DT, LAST_UPD_JOB   *
      *    FROM   PRCDB.ITEM_PRICE                                     *
      *    ORDER  BY SKU, REGION_CD                                    *
      *    FOR UPDATE OF CURR_PRICE, PRICE_TYPE, PROMO_ID,             *
      *           PROMO_EFF_DT, PROMO_END_DT, LAST_UPD_JOB             *
      *  END-EXEC                                                      *
       8100-DB2-OPEN-ITEM-PRICE-CURSOR.
           OPEN INPUT PRICE-IN
           MOVE 'N' TO WS-HEADER-SKIPPED
           PERFORM UNTIL WS-EOF-PRICE = 'Y'
               READ PRICE-IN
                   AT END MOVE 'Y' TO WS-EOF-PRICE
                   NOT AT END
                       IF WS-HEADER-SKIPPED = 'N'
                           MOVE 'Y' TO WS-HEADER-SKIPPED
                       ELSE
                           PERFORM 8110-LOAD-PRICE-ROW
                       END-IF
               END-READ
           END-PERFORM
           CLOSE PRICE-IN
           MOVE WS-PT-COUNT TO WS-CNT-PRICE-ROWS.

       8110-LOAD-PRICE-ROW.
           MOVE SPACES TO WS-F01 WS-F02 WS-F03 WS-F04 WS-F05
                          WS-F06 WS-F07 WS-F08 WS-F09
           UNSTRING PRICE-IN-REC DELIMITED BY ','
               INTO WS-F01 WS-F02 WS-F03 WS-F04 WS-F05
                    WS-F06 WS-F07 WS-F08 WS-F09
           END-UNSTRING
           ADD 1 TO WS-PT-COUNT
           SET PT-IDX TO WS-PT-COUNT
           MOVE WS-F01 TO WS-PT-SKU (PT-IDX)
           MOVE WS-F02 TO WS-PT-REGION-CD (PT-IDX)
           COMPUTE WS-PT-REG-PRICE (PT-IDX)  = FUNCTION NUMVAL (WS-F03)
           COMPUTE WS-PT-CURR-PRICE (PT-IDX) = FUNCTION NUMVAL (WS-F04)
           MOVE WS-F05 TO WS-PT-PRICE-TYPE (PT-IDX)
           MOVE WS-F06 TO WS-PT-PROMO-ID (PT-IDX)
           MOVE WS-F07 TO WS-DATE-ISO
           PERFORM 8900-ISO-TO-NUMERIC-DATE
           MOVE WS-DATE-NUM TO WS-PT-EFF-DT (PT-IDX)
           MOVE WS-F08 TO WS-DATE-ISO
           PERFORM 8900-ISO-TO-NUMERIC-DATE
           MOVE WS-DATE-NUM TO WS-PT-END-DT (PT-IDX)
           MOVE WS-F09 TO WS-PT-LAST-UPD-JOB (PT-IDX)
           MOVE 'N'    TO WS-PT-UPDATED (PT-IDX).

      *  EXEC SQL SELECT ... INTO :DCLITEM-PRICE                       *
      *    FROM PRCDB.ITEM_PRICE                                       *
      *    WHERE SKU = :IP-SKU AND REGION_CD = :IP-REGION-CD           *
      *  END-EXEC                                                      *
       8200-DB2-SELECT-ITEM-PRICE.
           MOVE +100 TO WS-SQLCODE
           SET PT-IDX TO 1
           SEARCH WS-PT-ENTRY
               AT END CONTINUE
               WHEN WS-PT-SKU (PT-IDX) = IP-SKU
                AND WS-PT-REGION-CD (PT-IDX) = IP-REGION-CD
                   PERFORM 8210-DB2-FETCH-ROW-AT-CURSOR
           END-SEARCH.

       8210-DB2-FETCH-ROW-AT-CURSOR.
           MOVE 0 TO WS-SQLCODE
           MOVE WS-PT-SKU (PT-IDX)          TO IP-SKU
           MOVE WS-PT-REGION-CD (PT-IDX)    TO IP-REGION-CD
           MOVE WS-PT-REG-PRICE (PT-IDX)    TO IP-REG-PRICE
           MOVE WS-PT-CURR-PRICE (PT-IDX)   TO IP-CURR-PRICE
           MOVE WS-PT-PRICE-TYPE (PT-IDX)   TO IP-PRICE-TYPE
           MOVE WS-PT-PROMO-ID (PT-IDX)     TO IP-PROMO-ID
           MOVE WS-PT-EFF-DT (PT-IDX)       TO IP-PROMO-EFF-DT
           MOVE WS-PT-END-DT (PT-IDX)       TO IP-PROMO-END-DT
           MOVE WS-PT-LAST-UPD-JOB (PT-IDX) TO IP-LAST-UPD-JOB.

      *  EXEC SQL UPDATE PRCDB.ITEM_PRICE                              *
      *    SET CURR_PRICE = :IP-CURR-PRICE, PRICE_TYPE = :IP-PRICE-TYPE*
      *        PROMO_ID = :IP-PROMO-ID :IP-PROMO-ID-IND,               *
      *        PROMO_EFF_DT = :IP-PROMO-EFF-DT :IP-PROMO-EFF-DT-IND,   *
      *        PROMO_END_DT = :IP-PROMO-END-DT :IP-PROMO-END-DT-IND,   *
      *        LAST_UPD_JOB = :IP-LAST-UPD-JOB                         *
      *    WHERE CURRENT OF PRICE_CSR                                  *
      *  END-EXEC                                                      *
       8300-DB2-UPDATE-ITEM-PRICE.
           MOVE IP-CURR-PRICE   TO WS-PT-CURR-PRICE (PT-IDX)
           MOVE IP-PRICE-TYPE   TO WS-PT-PRICE-TYPE (PT-IDX)
           MOVE IP-PROMO-ID     TO WS-PT-PROMO-ID (PT-IDX)
           MOVE IP-PROMO-EFF-DT TO WS-PT-EFF-DT (PT-IDX)
           MOVE IP-PROMO-END-DT TO WS-PT-END-DT (PT-IDX)
           MOVE IP-LAST-UPD-JOB TO WS-PT-LAST-UPD-JOB (PT-IDX)
           MOVE 'Y'             TO WS-PT-UPDATED (PT-IDX)
           MOVE 0 TO WS-SQLCODE.

      *  EXEC SQL INSERT INTO PRCDB.PRICE_HIST                         *
      *    (HIST_SEQ, SKU, REGION_CD, OLD_PRICE, NEW_PRICE, PROMO_ID,  *
      *     CHANGE_DT, CHANGE_RSN, JOB_NAME)                           *
      *    VALUES (:HS-HIST-SEQ, :HS-SKU, :HS-REGION-CD, :HS-OLD-PRICE,*
      *     :HS-NEW-PRICE, :HS-PROMO-ID, :HS-CHANGE-DT, :HS-CHANGE-RSN,*
      *     :HS-JOB-NAME)                                              *
      *  END-EXEC                                                      *
       8400-DB2-INSERT-PRICE-HIST.
           ADD 1 TO WS-LAST-HIST-SEQ
           MOVE WS-LAST-HIST-SEQ TO HS-HIST-SEQ
           MOVE IP-SKU           TO HS-SKU
           MOVE WS-CUR-REGION    TO HS-REGION-CD
           MOVE WS-OLD-PRICE     TO HS-OLD-PRICE
           MOVE WS-WORK-PRICE    TO HS-NEW-PRICE
           MOVE PH-PROMO-ID      TO HS-PROMO-ID
           MOVE WS-RUN-DATE      TO HS-CHANGE-DT
           MOVE WS-CHANGE-RSN    TO HS-CHANGE-RSN
           MOVE WS-PROGRAM-ID    TO HS-JOB-NAME
           MOVE HS-HIST-SEQ      TO WS-SEQ-EDIT
           MOVE HS-OLD-PRICE     TO WS-PRICE-EDIT
           MOVE HS-NEW-PRICE     TO WS-PRICE-EDIT2
           MOVE HS-CHANGE-DT     TO WS-DATE-NUM
           PERFORM 8910-NUMERIC-TO-ISO-DATE
           MOVE SPACES TO WS-CSV-OUT
           STRING FUNCTION TRIM (WS-SEQ-EDIT)      ','
                  FUNCTION TRIM (HS-SKU)           ','
                  FUNCTION TRIM (HS-REGION-CD)     ','
                  FUNCTION TRIM (WS-PRICE-EDIT)    ','
                  FUNCTION TRIM (WS-PRICE-EDIT2)   ','
                  FUNCTION TRIM (HS-PROMO-ID)      ','
                  WS-DATE-ISO                      ','
                  FUNCTION TRIM (HS-CHANGE-RSN)    ','
                  FUNCTION TRIM (HS-JOB-NAME)
               DELIMITED BY SIZE INTO WS-CSV-OUT
           END-STRING
           WRITE HIST-OUT-REC FROM WS-CSV-OUT
           ADD 1 TO WS-CNT-HIST-WRITTEN
           MOVE 0 TO WS-SQLCODE.

      *  EXEC SQL COMMIT END-EXEC  (write the after-state unload)      *
       8500-DB2-COMMIT-ITEM-PRICE.
           OPEN OUTPUT PRICE-OUT
           WRITE PRICE-OUT-REC FROM WS-ITEM-PRICE-HDR
           PERFORM VARYING PT-IDX FROM 1 BY 1
                   UNTIL PT-IDX > WS-PT-COUNT
               MOVE WS-PT-REG-PRICE (PT-IDX)  TO WS-PRICE-EDIT
               MOVE WS-PT-CURR-PRICE (PT-IDX) TO WS-PRICE-EDIT2
               MOVE WS-PT-EFF-DT (PT-IDX)     TO WS-DATE-NUM
               PERFORM 8910-NUMERIC-TO-ISO-DATE
               MOVE WS-DATE-ISO               TO WS-DATE-ISO2
               MOVE WS-PT-END-DT (PT-IDX)     TO WS-DATE-NUM
               PERFORM 8910-NUMERIC-TO-ISO-DATE
               MOVE SPACES TO WS-CSV-OUT
               STRING FUNCTION TRIM (WS-PT-SKU (PT-IDX))          ','
                      FUNCTION TRIM (WS-PT-REGION-CD (PT-IDX))    ','
                      FUNCTION TRIM (WS-PRICE-EDIT)               ','
                      FUNCTION TRIM (WS-PRICE-EDIT2)              ','
                      WS-PT-PRICE-TYPE (PT-IDX)                   ','
                      FUNCTION TRIM (WS-PT-PROMO-ID (PT-IDX))     ','
                      FUNCTION TRIM (WS-DATE-ISO2)                ','
                      FUNCTION TRIM (WS-DATE-ISO)                 ','
                      FUNCTION TRIM (WS-PT-LAST-UPD-JOB (PT-IDX))
                   DELIMITED BY SIZE INTO WS-CSV-OUT
               END-STRING
               WRITE PRICE-OUT-REC FROM WS-CSV-OUT
           END-PERFORM
           CLOSE PRICE-OUT.

      *  PRICE_HIST is insert-only: copy the existing unload through   *
      *  and remember the highest HIST_SEQ for new inserts.            *
       8600-DB2-COPY-PRICE-HIST.
           OPEN INPUT HIST-IN
           PERFORM UNTIL WS-EOF-HIST = 'Y'
               READ HIST-IN
                   AT END MOVE 'Y' TO WS-EOF-HIST
                   NOT AT END
                       WRITE HIST-OUT-REC FROM HIST-IN-REC
                       IF HIST-IN-REC (1:8) NOT = 'HIST_SEQ'
                           MOVE SPACES TO WS-F01
                           UNSTRING HIST-IN-REC DELIMITED BY ','
                               INTO WS-F01
                           END-UNSTRING
                           COMPUTE WS-LAST-HIST-SEQ =
                               FUNCTION NUMVAL (WS-F01)
                       END-IF
               END-READ
           END-PERFORM
           CLOSE HIST-IN.

       8900-ISO-TO-NUMERIC-DATE.
           IF WS-DATE-ISO = SPACES
               MOVE ZERO TO WS-DATE-NUM
           ELSE
               MOVE WS-DATE-ISO (1:4)  TO WS-DN-YYYY
               MOVE WS-DATE-ISO (6:2)  TO WS-DN-MM
               MOVE WS-DATE-ISO (9:2)  TO WS-DN-DD
           END-IF.

       8910-NUMERIC-TO-ISO-DATE.
           IF WS-DATE-NUM = ZERO
               MOVE SPACES TO WS-DATE-ISO
           ELSE
               MOVE SPACES TO WS-DATE-ISO
               STRING WS-DN-YYYY '-' WS-DN-MM '-' WS-DN-DD
                   DELIMITED BY SIZE INTO WS-DATE-ISO
               END-STRING
           END-IF.

      *================================================================*
      * 9000 - REPORT WRITER                                           *
      *================================================================*
       9000-WRITE-TOTALS.
           MOVE 99 TO WS-LINE-CNT
           PERFORM 9100-PRINT-HEADINGS
           MOVE 'RUN TOTALS' TO REPORT-REC
           WRITE REPORT-REC
           WRITE REPORT-REC FROM RPT-BLANK
           MOVE 'ITEM MASTER RECORDS LOADED'  TO RT-LABEL
           MOVE WS-CNT-ITEMS                  TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'STORE_REGION ROWS LOADED'    TO RT-LABEL
           MOVE WS-CNT-STORES                 TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'ITEM_PRICE ROWS IN CURSOR'   TO RT-LABEL
           MOVE WS-CNT-PRICE-ROWS             TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PROMOS EXPIRED (PHASE 1)'    TO RT-LABEL
           MOVE WS-CNT-EXPIRED                TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PROMO RECORDS READ'          TO RT-LABEL
           MOVE WS-CNT-PROMOS-READ            TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PRICES UPDATED'              TO RT-LABEL
           MOVE WS-CNT-PRICES-APPLIED         TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE '  OF WHICH RAISED TO FLOOR'  TO RT-LABEL
           MOVE WS-CNT-FLOORED                TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE '  OF WHICH REGION OVERRIDE'  TO RT-LABEL
           MOVE WS-CNT-RGN-OVERRIDE           TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PRICES UNCHANGED'            TO RT-LABEL
           MOVE WS-CNT-NO-CHANGE              TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PROMOS SKIPPED (WARNING)'    TO RT-LABEL
           MOVE WS-CNT-SKIPPED                TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PROMOS REJECTED (EXCEPTION)' TO RT-LABEL
           MOVE WS-CNT-EXCEPTIONS             TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           MOVE 'PRICE_HIST ROWS INSERTED'    TO RT-LABEL
           MOVE WS-CNT-HIST-WRITTEN           TO RT-VALUE
           WRITE REPORT-REC FROM RPT-TOTAL-LINE
           WRITE REPORT-REC FROM RPT-BLANK
           MOVE '*** END OF REPORT ***' TO REPORT-REC
           WRITE REPORT-REC.

       9100-PRINT-HEADINGS.
           ADD 1 TO WS-PAGE-NBR
           MOVE WS-PAGE-NBR TO RH1-PAGE
           MOVE WS-RUN-DATE TO WS-DATE-NUM
           PERFORM 8910-NUMERIC-TO-ISO-DATE
           MOVE WS-DATE-ISO TO RH1-DATE
           WRITE REPORT-REC FROM RPT-HEADER-1
           WRITE REPORT-REC FROM RPT-BLANK
           WRITE REPORT-REC FROM RPT-HEADER-2
           WRITE REPORT-REC FROM RPT-HEADER-3
           MOVE 4 TO WS-LINE-CNT.

       9200-WRITE-DETAIL.
           IF WS-LINE-CNT >= WS-LINES-PER-PAGE
               PERFORM 9100-PRINT-HEADINGS
           END-IF
           WRITE REPORT-REC FROM RPT-DETAIL
           ADD 1 TO WS-LINE-CNT
           MOVE SPACES TO RD-MESSAGE RD-STATUS RD-OVERRIDE.

       9500-TERMINATE.
           CLOSE PROMO-FILE ITEM-FILE STORE-FILE REPORT-FILE HIST-OUT.
