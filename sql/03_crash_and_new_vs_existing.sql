-- 03_crash_and_new_vs_existing.sql
-- Run from the project root:
--   psql -U postgres -d eu_housing -P pager=off -f sql/03_crash_and_new_vs_existing.sql

-- ---------------------------------------------------------------------------
-- Query 3: The post-2008 crash and how long each country took to recover
--   peak     = highest index up to 2010-Q4 (pre-crisis peak)
--   trough   = lowest index after the peak, up to 2019-Q4 (before the 2020s boom)
--   recovery = first quarter after the trough when the index is back at the peak
-- Only countries whose Eurostat series start by 2007-Q4 are comparable
-- (e.g. Italy, Austria and Poland start in 2010, so they are excluded),
-- and only real crashes (drop of 10% or more) are shown.
-- ---------------------------------------------------------------------------
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
       p.peak_period,
       p.peak_value,
       t.trough_period,
       t.trough_value,
       ROUND(100.0 * (t.trough_value - p.peak_value) / p.peak_value, 1) AS drawdown_pct,
       r.recovery_period,
       ROUND((r.recovery_no - p.peak_no) / 4.0, 1)                      AS years_peak_to_recovery
FROM peak p
JOIN trough t        ON t.country_code = p.country_code
LEFT JOIN recovery r ON r.country_code = p.country_code
WHERE (t.trough_value - p.peak_value) / p.peak_value <= -0.10
ORDER BY drawdown_pct;

-- ---------------------------------------------------------------------------
-- Query 4: Croatia, new vs existing dwellings (annual average of the index)
-- Conditional aggregation (CASE WHEN) turns the two purchase types into columns.
-- Note: 2026 contains only the quarters published so far (see the quarters column).
-- ---------------------------------------------------------------------------
SELECT year,
       ROUND(AVG(CASE WHEN purchase = 'DW_EXST' THEN value END), 1) AS existing_dwellings,
       ROUND(AVG(CASE WHEN purchase = 'DW_NEW'  THEN value END), 1) AS new_dwellings,
       ROUND(AVG(CASE WHEN purchase = 'DW_NEW'  THEN value END)
           - AVG(CASE WHEN purchase = 'DW_EXST' THEN value END), 1) AS gap_points,
       COUNT(CASE WHEN purchase = 'DW_EXST' THEN 1 END)             AS quarters
FROM hpi
WHERE country_code = 'HR'
  AND unit = 'I15_Q'
  AND purchase IN ('DW_EXST', 'DW_NEW')
  AND year >= 2015
GROUP BY year
ORDER BY year;
