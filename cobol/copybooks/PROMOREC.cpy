      *================================================================*
      * PROMOREC - PROMOTIONAL PRICE FEED RECORD (80 BYTES, ASCII)     *
      *                                                                *
      * Source system : Merchandising promo planner (daily extract)    *
      * Sorted by     : PRCUPD01 step 1 (SORT) on SKU, EFF-DATE, ID    *
      *                                                                *
      * PR-PROMO-TYPE  P = percent off regular price                   *
      *                    (PR-PROMO-VALUE = percent, 2 decimals)      *
      *                F = fixed promo price                           *
      *                    (PR-PROMO-VALUE = price)                    *
      *                B = buy-one-get-one, priced as REG / 2 per unit *
      *                    (PR-PROMO-VALUE ignored)                    *
      * PR-REGION-CD   pricing region; SPACES = all regions            *
      * PR-STORE-NBR   single store override; SPACES = all stores.     *
      *                When present it takes precedence over region    *
      *                and is resolved to the store's region.          *
      *================================================================*
       01  PROMO-REC.
           05  PR-PROMO-ID             PIC X(10).
           05  PR-SKU                  PIC X(08).
           05  PR-PROMO-TYPE           PIC X(01).
               88  PR-TYPE-PERCENT     VALUE 'P'.
               88  PR-TYPE-FIXED       VALUE 'F'.
               88  PR-TYPE-BOGO        VALUE 'B'.
               88  PR-TYPE-VALID       VALUE 'P' 'F' 'B'.
           05  PR-PROMO-VALUE          PIC 9(05)V99.
           05  PR-EFF-DATE             PIC 9(08).
           05  PR-END-DATE             PIC 9(08).
           05  PR-REGION-CD            PIC X(02).
           05  PR-STORE-NBR            PIC X(04).
           05  PR-CAMPAIGN             PIC X(12).
           05  FILLER                  PIC X(20).
