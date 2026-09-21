//PRCUPD01 JOB (MERCH,PRC),'NIGHTLY PROMO PRICE',CLASS=N,MSGCLASS=X,
//         MSGLEVEL=(1,1),NOTIFY=&SYSUID,REGION=0M,
//         RESTART=*
//*-------------------------------------------------------------------*
//* PRCUPD01 - NIGHTLY PROMOTIONAL PRICE UPDATE                        *
//*                                                                    *
//* SCHEDULE   : NIGHTLY 01:30 (see schedules/nightly.txt)             *
//* PREDECESSOR: ITMUNLD1 (item master unload), PRMEXTR1 (promo feed)  *
//* SUCCESSOR  : INVREPL01 (replenishment reads PRC.ITEM_PRICE.AFTER)  *
//*                                                                    *
//* STEP010 SORT    sort promo feed on SKU, EFF-DATE, PROMO-ID         *
//* STEP020 PRCUPD  PRCUPD01 - apply promo pricing, update DB2         *
//* STEP030 COMPARE golden-master compare (regression environments)    *
//*                                                                    *
//* RETURN CODES: 0 clean  4 warnings on PRCRPT  8 fatal (see SYSOUT)  *
//* RESTART     : restartable from STEP010; ITEM_PRICE updates are     *
//*               committed once at end of STEP020.                    *
//*-------------------------------------------------------------------*
//         JCLLIB ORDER=(PRC.PROD.PROCLIB)
//         SET RUNDT=&LYYMMDD
//*
//*=================================================================*
//* PROC PRCUPD01                                                   *
//*=================================================================*
//PRCUPD01 PROC HLQ=PRC.PROD,
//         FEEDGDG=PRC.PROD.PROMO.FEED,
//         LOADLIB=PRC.PROD.LOADLIB
//*
//*---------------------------------------------------------------*
//* STEP010 - SORT THE INCOMING PROMO FEED                         *
//*   KEY: SKU (11,8) / EFF-DATE (27,8) / PROMO-ID (1,10)          *
//*---------------------------------------------------------------*
//STEP010  EXEC PGM=SORT,PARM='DYNALLOC=(SYSDA,4)'
//SYSOUT   DD SYSOUT=*
//SORTIN   DD DSN=&FEEDGDG(0),DISP=SHR
//SORTOUT  DD DSN=&&PROMOSRT,DISP=(NEW,PASS),
//            UNIT=SYSDA,SPACE=(CYL,(5,2),RLSE),
//            DCB=(RECFM=FB,LRECL=80,BLKSIZE=27920)
//SYSIN    DD DSN=&HLQ.PARMLIB(PRCUPDS1),DISP=SHR
//*
//*---------------------------------------------------------------*
//* STEP020 - PRCUPD01 PROMO PRICE UPDATE                          *
//*   DD names match the SELECT ... ASSIGN clauses in PRCUPD01.cbl *
//*---------------------------------------------------------------*
//STEP020  EXEC PGM=PRCUPD01,COND=(4,LT,STEP010),REGION=0M
//STEPLIB  DD DSN=&LOADLIB,DISP=SHR
//         DD DSN=DSN.V13.SDSNLOAD,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSUDUMP DD SYSOUT=D
//*
//*  control cards  RUNDATE=YYYYMMDD
//SYSIN    DD *
RUNDATE=20260921
/*
//*  sorted promo feed from STEP010                    (PROMOREC)
//PROMOIN  DD DSN=&&PROMOSRT,DISP=(OLD,DELETE)
//*  item master unload (VSAM KSDS -> QSAM, sorted SKU) (ITEMMAST)
//ITEMMAST DD DSN=&HLQ.ITEMMAST.UNLOAD,DISP=SHR
//*  DB2 unloads - in production these DDs are dummied and the    *
//*  program uses EXEC SQL against PRCDB. In the demo estate DB2  *
//*  is unreachable so the same program reads/writes CSV unloads. *
//STORERGN DD DSN=&HLQ.STORE.REGION.CSV,DISP=SHR
//ITMPRCI  DD DSN=&HLQ.ITEM.PRICE.BEFORE.CSV,DISP=SHR
//ITMPRCO  DD DSN=&HLQ.ITEM.PRICE.AFTER.CSV,
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(10,5),RLSE),
//            DCB=(RECFM=VB,LRECL=204,BLKSIZE=27998)
//PRCHSTI  DD DSN=&HLQ.PRICE.HIST.BEFORE.CSV,DISP=SHR
//PRCHSTO  DD DSN=&HLQ.PRICE.HIST.AFTER.CSV,
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(10,5),RLSE),
//            DCB=(RECFM=VB,LRECL=204,BLKSIZE=27998)
//*  audit / exception report (132)
//PRCRPT   DD DSN=&HLQ.PRCUPD01.RPT.D&RUNDT,
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(5,5),RLSE),
//            DCB=(RECFM=FBA,LRECL=132,BLKSIZE=27984)
//*
//*---------------------------------------------------------------*
//* STEP030 - GOLDEN-MASTER COMPARE (regression / migration envs) *
//*   Runs only when STEP020 ended 0 or 4. Compares the report    *
//*   and the DB2 after-state unloads to the approved baselines.  *
//*   Local equivalent: scripts/compare.sh                        *
//*---------------------------------------------------------------*
//STEP030  EXEC PGM=ISRSUPC,COND=(4,LT,STEP020),
//            PARM=(DELTAL,LINECMP,'','')
//NEWDD    DD DSN=&HLQ.PRCUPD01.RPT.D&RUNDT,DISP=SHR
//         DD DSN=&HLQ.ITEM.PRICE.AFTER.CSV,DISP=SHR
//         DD DSN=&HLQ.PRICE.HIST.AFTER.CSV,DISP=SHR
//OLDDD    DD DSN=&HLQ.BASELINE.PRCUPD01.RPT,DISP=SHR
//         DD DSN=&HLQ.BASELINE.ITEM.PRICE.CSV,DISP=SHR
//         DD DSN=&HLQ.BASELINE.PRICE.HIST.CSV,DISP=SHR
//OUTDD    DD SYSOUT=*
//         PEND
//*
//*=================================================================*
//* EXECUTE THE PROC                                                *
//*=================================================================*
//RUN      EXEC PRCUPD01
//
