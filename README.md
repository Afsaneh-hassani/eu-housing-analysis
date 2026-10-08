# Croatian House Prices in a European Context (Eurostat, 2005–2026)

**How have Croatian house prices behaved since 2015, and how do they compare with neighbouring countries and the EU average?**

An end-to-end data analysis project: raw Eurostat data → cleaning with Python → analysis in PostgreSQL (CTEs, window functions) → interactive Power BI dashboard.

## Dashboard

![Overview](dashboard/overview.png)

![2008 crisis](dashboard/crisis_2008.png)

*A PDF export is available in [`dashboard/eu_housing_dashboard.pdf`](dashboard/eu_housing_dashboard.pdf).*

## Key findings

All figures use the Eurostat house price index (2015 = 100), all dwellings, latest quarter 2026-Q2.

- **Croatian prices are about 2.5× their 2015 level.** The index stands at **252.6**, versus **168.6** for the EU (27 countries), i.e. 84 points above the EU average.
- **Croatia ranks 7th of 28 countries**, behind Hungary (389.6), Portugal, Lithuania, Bulgaria, Iceland and Czechia, and ahead of Slovenia (234.2) and Austria (175.4).
- **Annual growth is still double-digit:** 12.7% in 2026-Q2 (provisional figure).
- **The post-2008 correction was moderate, but recovery was slow.** Croatian prices fell **21.6%** from the 2008-Q3 peak to the 2015-Q2 trough and only regained the 2008 peak in 2020-Q1, about **11.5 years** after the peak. Among the 15 countries with a fall of 10% or more, Croatia ranks 10th by depth of the fall and 7th by length of recovery.
- **Existing dwellings have become far more expensive than new ones** (SQL analysis, not in the dashboard): in the first two quarters of 2026 the index averages 261.8 for existing dwellings versus 194.5 for newly built ones (both 2015 = 100).

## Data

- **Source:** Eurostat, *House price index (2015 = 100) – quarterly data* (`prc_hpi_q`), downloaded in October 2026.
- **Coverage:** 38 countries and aggregates, 2005-Q1 to 2026-Q2 (Croatia: 2007-Q4 to 2026-Q2, 75 quarters).
- **Dimensions used:** purchase type (`TOTAL`, `DW_EXST` existing, `DW_NEW` new) and unit (`I15_Q` index 2015 = 100, `RCH_A` annual change).
- The raw file must contain **codes** (e.g. `HR`), not text labels (e.g. `Croatia`).

## Method

1. **Cleaning (Python / pandas):** `scripts/01_load_clean.py` reshapes the Eurostat file into a tidy table (one row per country, purchase type, unit and quarter), keeps Eurostat's quality flags (e.g. `p` = provisional), marks aggregates (EU, euro area), and writes `data/processed/hpi_tidy.csv` (32,753 rows).
2. **Database (PostgreSQL):** the tidy table is loaded into table `hpi`.
3. **Analysis (SQL):**
   - year-over-year growth with `LAG()`, **validated against Eurostat's own annual rate** (difference of at most 0.03 percentage points over the 12 most recent quarters, i.e. rounding only);
   - country ranking with `RANK()` and distance from the EU average;
   - 2008 crisis: pre-crisis peak, trough and recovery quarter per country using CTEs and `ROW_NUMBER()`;
   - new vs. existing dwellings with conditional aggregation.
4. **Reporting layer:** a country lookup table and three views (`v_hpi_quarterly`, `v_latest_ranking`, `v_crash_recovery`) feed the Power BI dashboard.
5. **Dashboard (Power BI):** an overview page (price index line chart and four KPI cards) and a 2008-crisis page (depth of the fall and years to recovery, Croatia highlighted).

## Project structure

```
├── data/
│   ├── raw/estat_prc_hpi_q_en.csv      # Eurostat download (not edited by hand)
│   └── processed/hpi_tidy.csv          # output of the Python script
├── scripts/01_load_clean.py
├── sql/
│   ├── 01_create_and_load.sql          # table + load
│   ├── 02_croatia_vs_peers.sql         # YoY growth, ranking
│   ├── 03_crash_and_new_vs_existing.sql
│   └── 04_views_for_powerbi.sql        # country names + 3 views
├── dashboard/
│   ├── eu_housing_dashboard.pbix
│   ├── eu_housing_dashboard.pdf
│   ├── overview.png
│   └── crisis_2008.png
└── requirements.txt
```

## How to reproduce

Requirements: Python 3.10+, PostgreSQL 14+ (developed on 18.4), Power BI Desktop (Windows).

```bash
pip install -r requirements.txt

# 1. Clean the raw data
python scripts/01_load_clean.py data/raw/estat_prc_hpi_q_en.csv

# 2. Create the database and load the data (adjust user and port to your setup)
psql -U postgres -c "CREATE DATABASE eu_housing;"
psql -U postgres -d eu_housing -f sql/01_create_and_load.sql

# 3. Run the analysis queries and create the views
psql -U postgres -d eu_housing -P pager=off -f sql/02_croatia_vs_peers.sql
psql -U postgres -d eu_housing -P pager=off -f sql/03_crash_and_new_vs_existing.sql
psql -U postgres -d eu_housing -f sql/04_views_for_powerbi.sql
```

Then open `dashboard/eu_housing_dashboard.pbix` in Power BI Desktop and point the data source to your PostgreSQL server (default `localhost:5432`).

## Limitations

- **Prices are nominal.** The index is not adjusted for inflation, so "recovery to the 2008 peak" would likely take longer in real terms.
- **The latest quarter (2026-Q2) is provisional** for Croatia and several other countries and may be revised.
- **Not a valuation analysis.** The project describes price dynamics only. It does not use incomes, rents or interest rates, so it cannot say whether prices are overvalued.
- **The 2008 analysis covers 15 countries**, defined by fixed rules (peak up to 2010-Q4, trough up to 2019-Q4, fall of at least 10%). Italy, Austria and Poland are excluded because their Eurostat series start in 2010; the United Kingdom series ends in 2020-Q3.
- **2026 contains only two quarters**, so its annual averages are partial.

## Possible next steps

- Deflate the index with Eurostat's HICP to get real prices.
- Add income or rent data to assess affordability.
- Extend the dashboard with the new vs. existing dwellings comparison.

## Skills demonstrated

SQL (CTEs, window functions, conditional aggregation, views) · PostgreSQL · Python / pandas · data validation · Power BI · data storytelling

---

*Author: Afsaneh Hasani — Data Analyst, PhD in Mathematics*
