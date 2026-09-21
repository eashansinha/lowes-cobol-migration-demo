//INVREPL01 JOB (MERCH,INV),'NIGHTLY REPLENISHMENT',CLASS=N,
//         MSGCLASS=X,MSGLEVEL=(1,1),NOTIFY=&SYSUID,REGION=0M
//*-------------------------------------------------------------------*
//* INVREPL01 - NIGHTLY STORE REPLENISHMENT SUGGESTIONS                *
//*                                                                    *
//* SCHEDULE   : NIGHTLY 02:15 (see schedules/nightly.txt)             *
//* PREDECESSOR: PRCUPD01 MAXCC <= 4                                   *
//*              INVREPL01 reads PRC.PROD.ITEM.PRICE.AFTER.CSV, the    *
//*              post-promo ITEM_PRICE state written by PRCUPD01, to   *
//*              lift replenishment quantities on promoted SKUs.       *
//*              If PRCUPD01 fails this job must NOT run against the   *
//*              stale before-state (see PREDCHK).                     *
//* SUCCESSOR  : STRXMIT1 (store order transmission, 04:00)            *
//*                                                                    *
//* NOTE: thin representation for the demo - the program INVREPL01 is  *
//*       not included in this repository.                             *
//*-------------------------------------------------------------------*
//         JCLLIB ORDER=(PRC.PROD.PROCLIB)
//*
//*---------------------------------------------------------------*
//* PREDCHK - assert PRCUPD01 produced today's after-state         *
//*---------------------------------------------------------------*
//PREDCHK  EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  LISTCAT ENTRIES(PRC.PROD.ITEM.PRICE.AFTER.CSV)
  IF LASTCC > 0 THEN SET MAXCC = 12
/*
//*
//*---------------------------------------------------------------*
//* STEP010 - REPLENISHMENT CALCULATION                            *
//*---------------------------------------------------------------*
//STEP010  EXEC PGM=INVREPL01,COND=(0,LT,PREDCHK),REGION=0M
//STEPLIB  DD DSN=PRC.PROD.LOADLIB,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//ITEMMAST DD DSN=PRC.PROD.ITEMMAST.UNLOAD,DISP=SHR
//ITMPRC   DD DSN=PRC.PROD.ITEM.PRICE.AFTER.CSV,DISP=SHR
//ONHAND   DD DSN=INV.PROD.STORE.ONHAND(0),DISP=SHR
//REPLOUT  DD DSN=INV.PROD.REPL.SUGGEST(+1),
//            DISP=(NEW,CATLG,DELETE),UNIT=SYSDA,
//            SPACE=(CYL,(20,10),RLSE),
//            DCB=(RECFM=FB,LRECL=120,BLKSIZE=27960)
//REPLRPT  DD SYSOUT=*
//SYSIN    DD *
RUNDATE=20260921
LIFTPCT=25
/*
//
