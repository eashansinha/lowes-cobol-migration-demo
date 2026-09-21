      *================================================================*
      * DCLGEN TABLE(PRCDB.STORE_REGION)                               *
      *        LIBRARY(PRCD.DCLGEN(DCLSTRGN))                          *
      *        LANGUAGE(COBOL) QUOTE                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      *                                                                *
      * Demo estate: reference table, read-only for PRCUPD01.          *
      * Unload lives in data/input/store_region.csv (DD STORERGN).     *
      *================================================================*
      *    EXEC SQL DECLARE PRCDB.STORE_REGION TABLE
      *    ( STORE_NBR                      CHAR(4) NOT NULL,
      *      STORE_NAME                     VARCHAR(30) NOT NULL,
      *      STATE_CD                       CHAR(2) NOT NULL,
      *      REGION_CD                      CHAR(2) NOT NULL
      *    ) END-EXEC.
      *================================================================*
      * COBOL DECLARATION FOR TABLE PRCDB.STORE_REGION                 *
      *================================================================*
       01  DCLSTORE-REGION.
           10  SR-STORE-NBR            PIC X(04).
           10  SR-STORE-NAME.
               49  SR-STORE-NAME-LEN   PIC S9(04) COMP.
               49  SR-STORE-NAME-TEXT  PIC X(30).
           10  SR-STATE-CD             PIC X(02).
           10  SR-REGION-CD            PIC X(02).
      *================================================================*
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 4       *
      *================================================================*
