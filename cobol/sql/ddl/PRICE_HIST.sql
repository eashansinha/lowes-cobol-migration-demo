-- PRCDB.PRICE_HIST : insert-only audit trail of every price change
-- Inserted by PRCUPD01 (one row per (SKU, REGION_CD) change) and by
-- the online price maintenance transaction PRCM (not in this repo).
-- Demo stand-in : data/db2/before/PRICE_HIST.csv -> data/db2/expected_after/PRICE_HIST.csv
-- DCLGEN        : cobol/copybooks/DCLPRHST.cpy

CREATE TABLE PRCDB.PRICE_HIST
(
    HIST_SEQ        INTEGER        NOT NULL,
    SKU             CHAR(8)        NOT NULL,
    REGION_CD       CHAR(2)        NOT NULL,
    OLD_PRICE       DECIMAL(7, 2)  NOT NULL,
    NEW_PRICE       DECIMAL(7, 2)  NOT NULL,
    PROMO_ID        CHAR(10),
    CHANGE_DT       DATE           NOT NULL,
    CHANGE_RSN      CHAR(6)        NOT NULL,
    JOB_NAME        CHAR(8)        NOT NULL,
    CREATED_TS      TIMESTAMP      NOT NULL WITH DEFAULT,
    CONSTRAINT PK_PRICE_HIST PRIMARY KEY (HIST_SEQ),
    CONSTRAINT CK_CHANGE_RSN CHECK
        (CHANGE_RSN IN ('PROMO ', 'FLOOR ', 'RGNOVR', 'EXPIRE', 'MANUAL', 'CLEAR '))
)
IN PRCDB.TSPRHIST
CCSID EBCDIC;

-- HIST_SEQ is allocated from this sequence in production; the batch
-- program takes MAX(HIST_SEQ) + 1 from the unload in the demo estate.
CREATE SEQUENCE PRCDB.SQ_PRICE_HIST
    AS INTEGER START WITH 1 INCREMENT BY 1 NO CYCLE CACHE 100;

CREATE INDEX PRCDB.XPRICE_HIST_01
    ON PRCDB.PRICE_HIST (SKU, REGION_CD, CHANGE_DT DESC);

CREATE INDEX PRCDB.XPRICE_HIST_02
    ON PRCDB.PRICE_HIST (CHANGE_DT, JOB_NAME);

COMMENT ON TABLE PRCDB.PRICE_HIST IS
    'Insert-only price change history. Never updated or deleted by batch.';
