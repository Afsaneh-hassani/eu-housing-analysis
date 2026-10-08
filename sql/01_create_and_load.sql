-- 01_create_and_load.sql
-- Creates the `hpi` table (Eurostat house price index, prc_hpi_q) and loads
-- data/processed/hpi_tidy.csv into it.
--
-- Run from the PROJECT ROOT (the path below is relative to it):
--   psql -U postgres -d eu_housing -f sql/01_create_and_load.sql

DROP TABLE IF EXISTS hpi;

CREATE TABLE hpi (
    country_code  TEXT          NOT NULL,   -- HR, SI, AT ... or an aggregate (EU27_2020, EA20 ...)
    is_aggregate  BOOLEAN       NOT NULL,   -- TRUE for EU / euro-area groups
    purchase      TEXT          NOT NULL,   -- TOTAL, DW_EXST (existing), DW_NEW (newly built)
    unit          TEXT          NOT NULL,   -- I15_Q (2015=100), I25_Q (2025=100), RCH_A, RCH_Q
    period        TEXT          NOT NULL,   -- e.g. 2026-Q2
    year          INT           NOT NULL,
    quarter       INT           NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    value         NUMERIC(10,2) NOT NULL,
    obs_flag      TEXT,                     -- p = provisional, e = estimated, b = break, d = definition differs
    PRIMARY KEY (country_code, purchase, unit, period)
);

\copy hpi FROM 'data/processed/hpi_tidy.csv' WITH (FORMAT csv, HEADER true)

-- ---- Quick checks (expected: 32753 rows, 38 countries, HR = 75 quarters) ----
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT country_code) AS countries FROM hpi;

SELECT country_code, MIN(period) AS first_period, MAX(period) AS last_period, COUNT(*) AS quarters
FROM hpi
WHERE country_code = 'HR' AND purchase = 'TOTAL' AND unit = 'I15_Q'
GROUP BY country_code;
