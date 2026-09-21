      *================================================================*
      * GLEXCREC - POSTING EXCEPTIONS FILE (GLEXCEPT)                  *
      *   RECFM=FB LRECL=80  DSN GL.PROD.GLEXCEPT.DAILY(+1)            *
      *   One record per rejected journal line; re-keyed by the        *
      *   accounting team through the MAN source the next day.         *
      *   REASON-CD  E001 account not on master   E002 account closed  *
      *              E003 account frozen          E004 invalid DR/CR   *
      *              E005 zero amount             E006 non-USD suspended*
      *              E007 post date out of period                       *
      *================================================================*
       01  GL-EXCEPT-REC.
           05  GLX-TRAN-ID             PIC X(10).
           05  GLX-ACCT-NO             PIC X(10).
           05  GLX-REASON-CD           PIC X(04).
           05  GLX-REASON-TX           PIC X(30).
           05  GLX-AMOUNT              PIC 9(11)V99.
           05  GLX-DR-CR               PIC X(01).
           05  GLX-BATCH-ID            PIC X(08).
           05  FILLER                  PIC X(04).
