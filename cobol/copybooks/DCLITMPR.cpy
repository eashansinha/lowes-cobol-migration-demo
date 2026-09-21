      *================================================================*
      * DCLGEN TABLE(PRCDB.ITEM_PRICE)                                 *
      *        LIBRARY(PRCD.DCLGEN(DCLITMPR))                          *
      *        LANGUAGE(COBOL) QUOTE                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      *                                                                *
      * In this demo estate DB2 is not reachable; the table is         *
      * represented by a CSV unload (data/db2/before/item_price.csv)   *
      * and the host variables below are populated by PRCUPD01's       *
      * DB2-* paragraphs, which stand in for EXEC SQL statements.      *
      *================================================================*
      *    EXEC SQL DECLARE PRCDB.ITEM_PRICE TABLE
      *    ( SKU                            CHAR(8) NOT NULL,
      *      REGION_CD                      CHAR(2) NOT NULL,
      *      REG_PRICE                      DECIMAL(7, 2) NOT NULL,
      *      CURR_PRICE                     DECIMAL(7, 2) NOT NULL,
      *      PRICE_TYPE                     CHAR(1) NOT NULL,
      *      PROMO_ID                       CHAR(10),
      *      PROMO_EFF_DT                   DATE,
      *      PROMO_END_DT                   DATE,
      *      LAST_UPD_JOB                   CHAR(8) NOT NULL
      *    ) END-EXEC.
      *================================================================*
      * COBOL DECLARATION FOR TABLE PRCDB.ITEM_PRICE                   *
      *================================================================*
       01  DCLITEM-PRICE.
           10  IP-SKU                  PIC X(08).
           10  IP-REGION-CD            PIC X(02).
           10  IP-REG-PRICE            PIC S9(05)V99 COMP-3.
           10  IP-CURR-PRICE           PIC S9(05)V99 COMP-3.
           10  IP-PRICE-TYPE           PIC X(01).
               88  IP-REGULAR          VALUE 'R'.
               88  IP-PROMO            VALUE 'P'.
           10  IP-PROMO-ID             PIC X(10).
           10  IP-PROMO-EFF-DT         PIC 9(08).
           10  IP-PROMO-END-DT         PIC 9(08).
           10  IP-LAST-UPD-JOB         PIC X(08).
      *================================================================*
      * INDICATOR VARIABLES FOR NULLABLE COLUMNS                       *
      *================================================================*
       01  DCLITEM-PRICE-IND.
           10  IP-PROMO-ID-IND         PIC S9(04) COMP.
           10  IP-PROMO-EFF-DT-IND     PIC S9(04) COMP.
           10  IP-PROMO-END-DT-IND     PIC S9(04) COMP.
      *================================================================*
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 9       *
      *================================================================*
