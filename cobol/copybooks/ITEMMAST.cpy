      *================================================================*
      * ITEMMAST - ITEM MASTER RECORD (80 BYTES, ASCII, SORTED BY SKU)  *
      *                                                                *
      * Source system : MERCH item master (nightly VSAM KSDS unload,   *
      *                 key = IM-SKU)                                  *
      * Consumers     : PRCUPD01, INVREPL01, ITMRPT02                  *
      *                                                                *
      * IM-STATUS   A = active   C = clearance   D = discontinued      *
      * IM-FLOOR-PCT  minimum margin over unit cost, whole percent.    *
      *               price floor = IM-UNIT-COST * (100 + PCT) / 100   *
      *================================================================*
       01  ITEM-MASTER-REC.
           05  IM-SKU                  PIC X(08).
           05  IM-DESC                 PIC X(30).
           05  IM-DEPT                 PIC X(04).
           05  IM-CLASS                PIC X(04).
           05  IM-STATUS               PIC X(01).
               88  IM-ACTIVE           VALUE 'A'.
               88  IM-CLEARANCE        VALUE 'C'.
               88  IM-DISCONTINUED     VALUE 'D'.
           05  IM-UNIT-COST            PIC 9(05)V99.
           05  IM-REG-PRICE            PIC 9(05)V99.
           05  IM-FLOOR-PCT            PIC 9(03).
           05  IM-UOM                  PIC X(02).
           05  IM-VENDOR-NBR           PIC X(06).
           05  FILLER                  PIC X(08).
