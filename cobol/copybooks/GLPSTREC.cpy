      *================================================================*
      * GLPSTREC - POSTED LEDGER FILE (GLPOSTED)                       *
      *   RECFM=FB LRECL=120  DSN GL.PROD.GLPOSTED.DAILY(+1)           *
      *   Consumed by GLBAL01 (trial balance) and the FIN data mart.   *
      *   SIGNED-AMT is positive when the entry increases the account  *
      *   (DR-CR equals the account's NORMAL-BAL), negative otherwise. *
      *   SIGN LEADING SEPARATE: '+' or '-' in column 43.              *
      *================================================================*
       01  GL-POSTED-REC.
           05  GLP-POST-SEQ            PIC 9(07).
           05  GLP-TRAN-ID             PIC X(10).
           05  GLP-POST-DATE           PIC 9(08).
           05  GLP-ACCT-NO             PIC X(10).
           05  GLP-ACCT-TYPE           PIC X(01).
           05  GLP-COST-CTR            PIC X(06).
           05  GLP-SIGNED-AMT          PIC S9(11)V99
                                       SIGN LEADING SEPARATE.
           05  GLP-DR-CR               PIC X(01).
           05  GLP-CURRENCY            PIC X(03).
           05  GLP-SOURCE              PIC X(04).
           05  GLP-BATCH-ID            PIC X(08).
           05  GLP-DESCRIPTION         PIC X(30).
           05  GLP-RUN-DATE            PIC 9(08).
           05  FILLER                  PIC X(10).
