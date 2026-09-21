      *================================================================*
      * PRICEHST - PRICE CHANGE HISTORY WORK RECORD                    *
      *                                                                *
      * Program-side view of one PRICE_HIST row before it is inserted  *
      * through the DB2 layer (see DCLPRHST for the DCLGEN host vars). *
      *                                                                *
      * PH-CHANGE-RSN  PROMO  promo price applied                      *
      *                FLOOR  promo price raised to margin floor       *
      *                RGNOVR region/store override changed the price  *
      *                EXPIRE promo ended, reverted to regular price   *
      *================================================================*
       01  PRICE-HIST-REC.
           05  PH-HIST-SEQ             PIC 9(09).
           05  PH-SKU                  PIC X(08).
           05  PH-REGION-CD            PIC X(02).
           05  PH-OLD-PRICE            PIC 9(05)V99.
           05  PH-NEW-PRICE            PIC 9(05)V99.
           05  PH-PROMO-ID             PIC X(10).
           05  PH-CHANGE-DT            PIC 9(08).
           05  PH-CHANGE-RSN           PIC X(06).
           05  PH-JOB-NAME             PIC X(08).
