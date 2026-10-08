-- 04_views_for_powerbi.sql
-- Creates a country lookup table and three views that Power BI will read.
-- Run from the project root:
--   psql -U postgres -d eu_housing -P pager=off -f sql/04_views_for_powerbi.sql

DROP VIEW  IF EXISTS v_latest_ranking;
DROP VIEW  IF EXISTS v_crash_recovery;
DROP VIEW  IF EXISTS v_hpi_quarterly;
DROP TABLE IF EXISTS dim_country;

-- ---------------------------------------------------------------------------
-- Country names (Eurostat only gives codes)
-- ---------------------------------------------------------------------------
CREATE TABLE dim_country (
    country_code TEXT PRIMARY KEY,
    country_name TEXT    NOT NULL,
    is_aggregate BOOLEAN NOT NULL
);

INSERT INTO dim_country (country_code, country_name, is_aggregate) VALUES
('AT','Austria',FALSE),('BE','Belgium',FALSE),('BG','Bulgaria',FALSE),
('CH','Switzerland',FALSE),('CY','Cyprus',FALSE),('CZ','Czechia',FALSE),
('DE','Germany',FALSE),('DK','Denmark',FALSE),('EE','Estonia',FALSE),
('ES','Spain',FALSE),('FI','Finland',FALSE),('FR','France',FALSE),
('HR','Croatia',FALSE),('HU','Hungary',FALSE),('IE','Ireland',FALSE),
('IS','Iceland',FALSE),('IT','Italy',FALSE),('LT','Lithuania',FALSE),
('LU','Luxembourg',FALSE),('LV','Latvia',FALSE),('MT','Malta',FALSE),
('NL','Netherlands',FALSE),('NO','Norway',FALSE),('PL','Poland',FALSE),
('PT','Portugal',FALSE),('RO','Romania',FALSE),('SE','Sweden',FALSE),
('SI','Slovenia',FALSE),('SK','Slovakia',FALSE),('TR','Turkiye',FALSE),
('UK','United Kingdom',FALSE),
('EA','Euro area',TRUE),('EA19','Euro area (19 countries)',TRUE),
('EA20','Euro area (20 countries)',TRUE),('EA21','Euro area (21 countries)',TRUE),
('EU','European Union',TRUE),('EU27_2020','EU (27 countries)',TRUE),
('EU28','EU (28 countries)',TRUE);

-- ---------------------------------------------------------------------------
-- View 1: main fact view. One row per country / purchase type / quarter,
-- with the index (2015=100) and the annual change side by side.
-- ---------------------------------------------------------------------------
CREATE VIEW v_hpi_quarterly AS
SELECT h.country_code,
       c.country_name,
       c.is_aggregate,
       h.purchase,
       h.period,
       h.year,
       h.quarter,
       MAKE_DATE(h.year, (h.quarter - 1) * 3 + 1, 1)           AS period_start,
       MAX(CASE WHEN h.unit = 'I15_Q' THEN h.value END)        AS index_2015_100,
       MAX(CASE WHEN h.unit = 'RCH_A' THEN h.value END)        AS yoy_change_pct,
       MAX(CASE WHEN h.unit = 'I15_Q' THEN h.obs_flag END)     AS obs_flag
FROM hpi h
JOIN dim_country c ON c.country_code = h.country_code
WHERE h.unit IN ('I15_Q', 'RCH_A')
GROUP BY h.country_code, c.country_name, c.is_aggregate,
         h.purchase, h.period, h.year, h.quarter;

-- ---------------------------------------------------------------------------
-- View 2: ranking of countries in the latest quarter (same logic as query 2)
-- ---------------------------------------------------------------------------
CREATE VIEW v_latest_ranking AS
WITH latest AS (
    SELECT MAX(period) AS period
    FROM hpi
    WHERE country_code = 'HR' AND purchase = 'TOTAL' AND unit = 'I15_Q'
),
eu AS (
    SELECT h.value AS eu_value
    FROM hpi h
    JOIN latest l ON l.period = h.period
    WHERE h.country_code = 'EU27_2020' AND h.purchase = 'TOTAL' AND h.unit = 'I15_Q'
)
SELECT RANK() OVER (ORDER BY h.value DESC)  AS rank_pos,
       h.country_code,
       c.country_name,
       l.period                              AS latest_period,
       h.value                               AS index_2015_100,
       ROUND(h.value - eu.eu_value, 2)       AS points_above_eu27,
       h.obs_flag
FROM hpi h
JOIN latest l ON l.period = h.period
JOIN dim_country c ON c.country_code = h.country_code
CROSS JOIN eu
WHERE h.purchase = 'TOTAL' AND h.unit = 'I15_Q' AND c.is_aggregate = FALSE;

-- ---------------------------------------------------------------------------
-- View 3: post-2008 crash and recovery (same logic as query 3)
-- ---------------------------------------------------------------------------
CREATE VIEW v_crash_recovery AS
WITH series AS (
    SELECT country_code, period, value, year * 4 + quarter AS period_no
    FROM hpi
    WHERE purchase = 'TOTAL' AND unit = 'I15_Q' AND is_aggregate = FALSE
),
coverage AS (
    SELECT country_code
    FROM series
    GROUP BY country_code
    HAVING MIN(period) <= '2007-Q4'
),
peak AS (
    SELECT country_code, period AS peak_period, value AS peak_value, period_no AS peak_no
    FROM (
        SELECT s.country_code, s.period, s.value, s.period_no,
               ROW_NUMBER() OVER (PARTITION BY s.country_code
                                  ORDER BY s.value DESC, s.period) AS rn
        FROM series s
        JOIN coverage c ON c.country_code = s.country_code
        WHERE s.period <= '2010-Q4'
    ) x
    WHERE rn = 1
),
trough AS (
    SELECT country_code, period AS trough_period, value AS trough_value
    FROM (
        SELECT s.country_code, s.period, s.value,
               ROW_NUMBER() OVER (PARTITION BY s.country_code
                                  ORDER BY s.value, s.period) AS rn
        FROM series s
        JOIN peak p ON p.country_code = s.country_code
        WHERE s.period > p.peak_period AND s.period <= '2019-Q4'
    ) x
    WHERE rn = 1
),
recovery AS (
    SELECT t.country_code, MIN(s.period) AS recovery_period, MIN(s.period_no) AS recovery_no
    FROM trough t
    JOIN peak p   ON p.country_code = t.country_code
    JOIN series s ON s.country_code = t.country_code
                 AND s.period > t.trough_period
                 AND s.value >= p.peak_value
    GROUP BY t.country_code
)
SELECT p.country_code,
       c.country_name,
       p.peak_period,
       p.peak_value,
       t.trough_period,
       t.trough_value,
       ROUND(100.0 * (t.trough_value - p.peak_value) / p.peak_value, 1) AS drawdown_pct,
       r.recovery_period,
       ROUND((r.recovery_no - p.peak_no) / 4.0, 1)                      AS years_peak_to_recovery
FROM peak p
JOIN trough t        ON t.country_code = p.country_code
JOIN dim_country c   ON c.country_code = p.country_code
LEFT JOIN recovery r ON r.country_code = p.country_code
WHERE (t.trough_value - p.peak_value) / p.peak_value <= -0.10;

-- ---------------------------------------------------------------------------
-- Checks (expected: HR 2026-Q2 -> 252.62 and 12.70; ranking 28 rows; crash view 15 rows)
-- ---------------------------------------------------------------------------
SELECT country_name, purchase, period, period_start, index_2015_100, yoy_change_pct, obs_flag
FROM v_hpi_quarterly
WHERE country_code = 'HR' AND purchase = 'TOTAL'
ORDER BY period DESC
LIMIT 3;

SELECT (SELECT COUNT(*) FROM v_latest_ranking)  AS ranking_rows,
       (SELECT COUNT(*) FROM v_crash_recovery)  AS crash_rows,
       (SELECT COUNT(*) FROM hpi h
         WHERE NOT EXISTS (SELECT 1 FROM dim_country c WHERE c.country_code = h.country_code)) AS codes_without_name;
