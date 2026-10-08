-- 02_croatia_vs_peers.sql
-- First analytical queries on the `hpi` table.
-- Run from the project root:
--   psql -U postgres -d eu_housing -f sql/02_croatia_vs_peers.sql

-- ---------------------------------------------------------------------------
-- Query 1: Croatia's price index with year-over-year growth (last 12 quarters)
-- Uses a CTE + LAG(). Growth is recomputed by us and cross-checked against
-- Eurostat's own annual rate of change (unit RCH_A) as a data-quality test.
-- ---------------------------------------------------------------------------
WITH croatia AS (
    SELECT period,
           value,
           LAG(value, 4) OVER (ORDER BY period) AS value_year_ago
    FROM hpi
    WHERE country_code = 'HR'
      AND purchase = 'TOTAL'
      AND unit = 'I15_Q'
),
yoy AS (
    SELECT period,
           value AS index_2015_100,
           ROUND(100.0 * (value - value_year_ago) / value_year_ago, 2) AS yoy_pct_calc
    FROM croatia
)
SELECT y.period,
       y.index_2015_100,
       y.yoy_pct_calc,
       e.value                                   AS yoy_pct_eurostat,
       ROUND(y.yoy_pct_calc - e.value, 2)        AS difference
FROM yoy y
LEFT JOIN hpi e
       ON e.country_code = 'HR'
      AND e.purchase = 'TOTAL'
      AND e.unit = 'RCH_A'
      AND e.period = y.period
ORDER BY y.period DESC
LIMIT 12;

-- ---------------------------------------------------------------------------
-- Query 2: Where does Croatia rank among European countries (latest quarter)?
-- Uses RANK() and compares every country with the EU27 average.
-- ---------------------------------------------------------------------------
WITH latest AS (
    SELECT MAX(period) AS period
    FROM hpi
    WHERE country_code = 'HR' AND purchase = 'TOTAL' AND unit = 'I15_Q'
),
eu AS (
    SELECT h.value AS eu_value
    FROM hpi h, latest l
    WHERE h.country_code = 'EU27_2020'
      AND h.purchase = 'TOTAL' AND h.unit = 'I15_Q' AND h.period = l.period
)
SELECT RANK() OVER (ORDER BY h.value DESC)  AS rank_pos,
       h.country_code,
       h.value                              AS index_2015_100,
       ROUND(h.value - eu.eu_value, 2)      AS points_above_eu27,
       h.obs_flag
FROM hpi h, latest l, eu
WHERE h.purchase = 'TOTAL' AND h.unit = 'I15_Q' AND h.period = l.period
  AND h.is_aggregate = FALSE
ORDER BY rank_pos;
