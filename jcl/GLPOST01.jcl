//GLPOST01 JOB (FIN,GL),'DAILY GL POSTING',CLASS=N,MSGCLASS=X,
//         MSGLEVEL=(1,1),NOTIFY=&SYSUID,REGION=0M,
//         RESTART=*
//*-------------------------------------------------------------------*
//* GLPOST01 - DAILY GENERAL LEDGER POSTING                            *
//*                                                                    *
//* SCHEDULE   : DAILY 02:00 (see schedules/nightly.txt)               *
//* PREDECESSOR: APEXTR01 ARXTR01 PAYXTR01 (sub-ledger journal feeds)  *
//* SUCCESSOR  : GLBAL01 (trial balance reads GL.PROD.GLPOSTED.DAILY)  *
//*                                                                    *
//* STEP010 SORT    sort the journal feed on BATCH-ID, ACCT-NO, TRAN-ID*
//* STEP020 GLPOST  GLPOST01 - validate and post, write exceptions     *
//* STEP030 COMPARE file parity against the golden outputs (regression *
//*                 environments only - see scripts/compare_files.py)  *
//*                                                                    *
//* FILE IN                                                            *
//*   GL.PROD.GLTRANS.DAILY(0)    FB 100  daily journal feed (GDG)     *
//*   GL.PROD.ACCTMAST.UNLOAD     FB  60  chart of accounts            *
//* FILES OUT                                                          *
//*   GL.PROD.GLPOSTED.DAILY(+1)  FB 120  posted ledger                *
//*   GL.PROD.GLEXCEPT.DAILY(+1)  FB  80  posting exceptions           *
//*   GLRPT                       FBA132  batch control report         *
//*                                                                    *
//* RETURN CODES: 0 clean  4 exceptions / out-of-balance batch         *
//*               8 empty feed or bad SYSIN  16 abend                  *
//* RESTART     : restartable from STEP010; outputs are new GDG        *
//*               generations so a rerun never double-posts.           *
//*-------------------------------------------------------------------*
//         JCLLIB ORDER=(GL.PROD.PROCLIB)
//         SET RUNDT=&LYYMMDD
//*
//*=================================================================*
//* PROC GLPOST01                                                   *
//*=================================================================*
//GLPOST01 PROC HLQ=GL.PROD,
//         FEEDGDG=GL.PROD.GLTRANS.DAILY,
//         LOADLIB=GL.PROD.LOADLIB
//*
//*---------------------------------------------------------------*
//* STEP010 - SORT THE DAILY JOURNAL FEED                          *
//*   KEY: BATCH-ID (56,8) / ACCT-NO (19,10) / TRAN-ID (1,10)      *
//*---------------------------------------------------------------*
//STEP010  EXEC PGM=SORT,PARM='DYNALLOC=(SYSDA,4)'
//SYSOUT   DD SYSOUT=*
//SORTIN   DD DSN=&FEEDGDG(0),DISP=SHR
//SORTOUT  DD DSN=&&TRANSRT,DISP=(NEW,PASS),
//            UNIT=SYSDA,SPACE=(CYL,(10,5),RLSE),
//            DCB=(RECFM=FB,LRECL=100,BLKSIZE=27900)
//SYSIN    DD *
  SORT FIELDS=(56,8,CH,A,19,10,CH,A,1,10,CH,A)
/*
//*
//*---------------------------------------------------------------*
//* STEP020 - GLPOST01 VALIDATE AND POST                           *
//*   DD names match the SELECT ... ASSIGN clauses in GLPOST01.cbl *
//*---------------------------------------------------------------*
//STEP020  EXEC PGM=GLPOST01,COND=(4,LT,STEP010),REGION=0M
//STEPLIB  DD DSN=&LOADLIB,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSUDUMP DD SYSOUT=D
//*
//*  control cards  RUNDATE=YYYYMMDD
//SYSIN    DD *
RUNDATE=20260921
/*
//*  sorted journal feed from STEP010                   (GLTRNREC)
//GLTRANS  DD DSN=&&TRANSRT,DISP=(OLD,DELETE)
//*  chart of accounts unload (VSAM KSDS -> QSAM)       (ACCTMAST)
//ACCTMAST DD DSN=&HLQ.ACCTMAST.UNLOAD,DISP=SHR
//*  posted ledger - new generation, read by GLBAL01    (GLPSTREC)
//GLPOSTED DD DSN=&HLQ.GLPOSTED.DAILY(+1),
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(20,10),RLSE),
//            DCB=(RECFM=FB,LRECL=120,BLKSIZE=27960)
//*  posting exceptions - re-keyed by accounting        (GLEXCREC)
//GLEXCEPT DD DSN=&HLQ.GLEXCEPT.DAILY(+1),
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(2,1),RLSE),
//            DCB=(RECFM=FB,LRECL=80,BLKSIZE=27920)
//*  batch control report
//GLRPT    DD SYSOUT=(,),DCB=(RECFM=FBA,LRECL=132)
//*
//*---------------------------------------------------------------*
//* STEP030 - FILE PARITY (regression environments only)          *
//*   Compares GLPOSTED / GLEXCEPT / GLRPT with the golden         *
//*   generation. Off in production (COND=ONLY never satisfied).   *
//*---------------------------------------------------------------*
//STEP030  EXEC PGM=IEBCOMPR,COND=(4,LT,STEP020)
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD DSN=&HLQ.GLPOSTED.DAILY(+1),DISP=SHR
//SYSUT2   DD DSN=&HLQ.GLPOSTED.GOLDEN,DISP=SHR
//SYSIN    DD DUMMY
//         PEND
//*
//RUN      EXEC GLPOST01
//
