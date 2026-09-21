       IDENTIFICATION DIVISION.
       PROGRAM-ID.    PRCRGN01.
       AUTHOR.        PRICING SYSTEMS - MERCH IT.
      *================================================================*
      * PRCRGN01 - REGION / STORE PRICE OVERRIDE RULES                 *
      *                                                                *
      * Called by PRCUPD01 once per (promo, target region) with the    *
      * candidate promo price. Applies region-specific commercial      *
      * rules and returns the adjusted price plus an override code.    *
      *                                                                *
      * Regions (PRCDB.STORE_REGION.REGION_CD):                        *
      *   NE Northeast   SE Southeast   MW Midwest                     *
      *   WC West Coast  NC Non-contiguous (AK / HI)                   *
      *                                                                *
      * Rules (see docs/MIGRATION_SPEC_TEMPLATE.md, section BR-R*):    *
      *   BR-R1  NC: BOGO promos are not honoured -> skip              *
      *   BR-R2  NC: freight uplift of 8% on the promo price,          *
      *              capped at the regular price                       *
      *   BR-R3  WC: department LUMB promos may not discount more      *
      *              than 15% below regular price                      *
      *   BR-R4  Any other region: price passes through unchanged      *
      *   Unknown region -> RC 08, action S                            *
      *                                                                *
      * CHANGE LOG                                                     *
      *  2019-03-11  MERCH-4471  initial (NC freight uplift)           *
      *  2021-07-02  MERCH-6120  add WC lumber cap                     *
      *  2023-01-19  MERCH-7788  NC BOGO exclusion                     *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-NC-FREIGHT-PCT       PIC 9(03) VALUE 108.
           05  WS-WC-LUMBER-MIN-PCT    PIC 9(03) VALUE 085.

       01  WS-REGION-VALUES            PIC X(10) VALUE 'NESEMWWCNC'.
       01  WS-REGION-TABLE REDEFINES WS-REGION-VALUES.
           05  WS-REGION-ENTRY OCCURS 5 TIMES.
               10  WS-REGION-CD        PIC X(02).

       01  WS-WORK.
           05  WS-IDX                  PIC 9(01).
           05  WS-REGION-FOUND         PIC X(01).
           05  WS-CALC-PRICE           PIC 9(05)V99.
           05  WS-MIN-PRICE            PIC 9(05)V99.

       LINKAGE SECTION.
           COPY PRCRGNCA.

       PROCEDURE DIVISION USING PRCRGN-COMMAREA.
       0000-MAIN.
           PERFORM 1000-INITIALISE
           PERFORM 2000-VALIDATE-REGION
           IF RGN-RC-OK
               PERFORM 3000-APPLY-REGION-RULES
           END-IF
           GOBACK.

       1000-INITIALISE.
           MOVE RGN-IN-PRICE           TO RGN-OUT-PRICE
           MOVE 'A'                    TO RGN-OUT-ACTION
           MOVE SPACES                 TO RGN-OUT-OVERRIDE
           MOVE '00'                   TO RGN-OUT-RC.

       2000-VALIDATE-REGION.
           MOVE 'N' TO WS-REGION-FOUND
           PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > 5
               IF WS-REGION-CD (WS-IDX) = RGN-IN-REGION-CD
                   MOVE 'Y' TO WS-REGION-FOUND
               END-IF
           END-PERFORM
           IF WS-REGION-FOUND = 'N'
               MOVE '08' TO RGN-OUT-RC
               MOVE 'S'  TO RGN-OUT-ACTION
           END-IF.

       3000-APPLY-REGION-RULES.
           EVALUATE RGN-IN-REGION-CD
               WHEN 'NC'
                   PERFORM 3100-NON-CONTIGUOUS-RULES
               WHEN 'WC'
                   PERFORM 3200-WEST-COAST-RULES
               WHEN OTHER
                   CONTINUE
           END-EVALUATE.

      *----------------------------------------------------------------*
      * BR-R1 / BR-R2 : Alaska & Hawaii                                *
      *----------------------------------------------------------------*
       3100-NON-CONTIGUOUS-RULES.
           IF RGN-IN-PROMO-TYPE = 'B'
               MOVE 'S'      TO RGN-OUT-ACTION
               MOVE 'NOBOGO' TO RGN-OUT-OVERRIDE
           ELSE
               COMPUTE WS-CALC-PRICE =
                   RGN-IN-PRICE * WS-NC-FREIGHT-PCT / 100
               IF WS-CALC-PRICE > RGN-IN-REG-PRICE
                   MOVE RGN-IN-REG-PRICE TO WS-CALC-PRICE
               END-IF
               IF WS-CALC-PRICE NOT = RGN-IN-PRICE
                   MOVE WS-CALC-PRICE TO RGN-OUT-PRICE
                   MOVE 'NCFRT'       TO RGN-OUT-OVERRIDE
               END-IF
           END-IF.

      *----------------------------------------------------------------*
      * BR-R3 : West Coast lumber discount cap                         *
      *----------------------------------------------------------------*
       3200-WEST-COAST-RULES.
           IF RGN-IN-DEPT = 'LUMB'
               COMPUTE WS-MIN-PRICE =
                   RGN-IN-REG-PRICE * WS-WC-LUMBER-MIN-PCT / 100
               IF RGN-IN-PRICE < WS-MIN-PRICE
                   MOVE WS-MIN-PRICE TO RGN-OUT-PRICE
                   MOVE 'WCLUM'      TO RGN-OUT-OVERRIDE
               END-IF
           END-IF.
