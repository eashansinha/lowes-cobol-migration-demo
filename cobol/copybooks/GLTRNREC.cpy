      *================================================================*
      * GLTRNREC - DAILY GENERAL LEDGER TRANSACTION FEED (GLTRANS)     *
      *   RECFM=FB LRECL=100  DSN GL.PROD.GLTRANS.DAILY(0)             *
      *   Produced by the sub-ledger extracts (AP, AR, PAY, INV) and   *
      *   manual journal entry (MAN). One record per journal line.     *
      *   Sorted by GLPOST01 STEP010 on BATCH-ID / ACCT-NO / TRAN-ID.  *
      *================================================================*
       01  GL-TRAN-REC.
           05  GLT-TRAN-ID             PIC X(10).
           05  GLT-POST-DATE           PIC 9(08).
           05  GLT-ACCT-NO             PIC X(10).
           05  GLT-COST-CTR            PIC X(06).
           05  GLT-DR-CR               PIC X(01).
               88  GLT-DEBIT           VALUE 'D'.
               88  GLT-CREDIT          VALUE 'C'.
           05  GLT-AMOUNT              PIC 9(11)V99.
           05  GLT-CURRENCY            PIC X(03).
               88  GLT-USD             VALUE 'USD'.
           05  GLT-SOURCE              PIC X(04).
           05  GLT-BATCH-ID            PIC X(08).
           05  GLT-DESCRIPTION         PIC X(30).
           05  FILLER                  PIC X(07).
