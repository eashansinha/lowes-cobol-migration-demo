      *================================================================*
      * ACCTMAST - CHART OF ACCOUNTS MASTER (VSAM KSDS unload -> QSAM) *
      *   RECFM=FB LRECL=60  DSN GL.PROD.ACCTMAST.UNLOAD  sorted ACCT  *
      *   ACCT-TYPE  A asset  L liability  Q equity  R revenue  E exp. *
      *   STATUS     A active  C closed  F frozen (no posting)         *
      *   NORMAL-BAL D debit-normal  C credit-normal                   *
      *================================================================*
       01  ACCT-MAST-REC.
           05  ACM-ACCT-NO             PIC X(10).
           05  ACM-ACCT-TYPE           PIC X(01).
           05  ACM-STATUS              PIC X(01).
               88  ACM-ACTIVE          VALUE 'A'.
               88  ACM-CLOSED          VALUE 'C'.
               88  ACM-FROZEN          VALUE 'F'.
           05  ACM-NORMAL-BAL          PIC X(01).
           05  ACM-ACCT-NAME           PIC X(30).
           05  ACM-CLOSE-DATE          PIC 9(08).
           05  FILLER                  PIC X(09).
