      *================================================================*
      * PRCRGNCA - COMMUNICATION AREA FOR SUBPROGRAM PRCRGN01           *
      *            (REGION / STORE PRICE OVERRIDE RULES)               *
      *                                                                *
      * Caller fills RGN-IN-*; PRCRGN01 sets RGN-OUT-*.                *
      *                                                                *
      * RGN-OUT-ACTION   A = apply RGN-OUT-PRICE                       *
      *                  S = skip promo for this region                *
      * RGN-OUT-OVERRIDE spaces  = no override applied                 *
      *                  NCFRT  = non-contiguous freight uplift        *
      *                  WCLUM  = west-coast lumber discount cap       *
      *                  NOBOGO = BOGO not honoured in region          *
      * RGN-OUT-RC       00 ok, 08 unknown region code                 *
      *================================================================*
       01  PRCRGN-COMMAREA.
           05  RGN-IN-REGION-CD        PIC X(02).
           05  RGN-IN-DEPT             PIC X(04).
           05  RGN-IN-PROMO-TYPE       PIC X(01).
           05  RGN-IN-REG-PRICE        PIC 9(05)V99.
           05  RGN-IN-PRICE            PIC 9(05)V99.
           05  RGN-OUT-PRICE           PIC 9(05)V99.
           05  RGN-OUT-ACTION          PIC X(01).
               88  RGN-APPLY           VALUE 'A'.
               88  RGN-SKIP            VALUE 'S'.
           05  RGN-OUT-OVERRIDE        PIC X(06).
           05  RGN-OUT-RC              PIC X(02).
               88  RGN-RC-OK           VALUE '00'.
               88  RGN-RC-BAD-REGION   VALUE '08'.
