      *================================================================*
      * DCLGEN TABLE(PRCDB.PRICE_HIST)                                 *
      *        LIBRARY(PRCD.DCLGEN(DCLPRHST))                          *
      *        LANGUAGE(COBOL) QUOTE                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      *                                                                *
      * Demo estate: table represented by data/db2/before/price_hist   *
      * .csv; rows are appended by PRCUPD01 (insert-only table).       *
      *================================================================*
      *    EXEC SQL DECLARE PRCDB.PRICE_HIST TABLE
      *    ( HIST_SEQ                       INTEGER NOT NULL,
      *      SKU                            CHAR(8) NOT NULL,
      *      REGION_CD                      CHAR(2) NOT NULL,
      *      OLD_PRICE                      DECIMAL(7, 2) NOT NULL,
      *      NEW_PRICE                      DECIMAL(7, 2) NOT NULL,
      *      PROMO_ID                       CHAR(10),
      *      CHANGE_DT                      DATE NOT NULL,
      *      CHANGE_RSN                     CHAR(6) NOT NULL,
      *      JOB_NAME                       CHAR(8) NOT NULL
      *    ) END-EXEC.
      *================================================================*
      * COBOL DECLARATION FOR TABLE PRCDB.PRICE_HIST                   *
      *================================================================*
       01  DCLPRICE-HIST.
           10  HS-HIST-SEQ             PIC S9(09) COMP.
           10  HS-SKU                  PIC X(08).
           10  HS-REGION-CD            PIC X(02).
           10  HS-OLD-PRICE            PIC S9(05)V99 COMP-3.
           10  HS-NEW-PRICE            PIC S9(05)V99 COMP-3.
           10  HS-PROMO-ID             PIC X(10).
           10  HS-CHANGE-DT            PIC 9(08).
           10  HS-CHANGE-RSN           PIC X(06).
           10  HS-JOB-NAME             PIC X(08).
      *================================================================*
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 9       *
      *================================================================*
