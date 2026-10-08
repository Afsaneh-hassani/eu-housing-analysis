"""
Step 1: Load the raw Eurostat house price index file (prc_hpi_q) and
convert it to a tidy (long) CSV that is ready for PostgreSQL.

Usage:
    python scripts/01_load_clean.py data/raw/prc_hpi_q.csv.gz

Accepts:
  * wide TSV     (header like: freq,purchase,unit,geo\\TIME_PERIOD <tab> 2005-Q1 ...)
  * long SDMX-CSV (columns: freq, purchase, unit, geo, TIME_PERIOD, OBS_VALUE, ...)
  * either of the above gzip-compressed (detected automatically)

The dimension values must be CODES (HR, TOTAL, I15_Q), not text labels.
"""
import gzip
import re
import sys
from pathlib import Path

import pandas as pd

def is_aggregate_code(code: str) -> bool:
    """Euro area (EA, EA19, EA20, EA21...) and EU (EU, EU27_2020, EU28) are groups, not countries."""
    return code.startswith("EA") or code.startswith("EU")


def is_gzip(path: Path) -> bool:
    with open(path, "rb") as f:
        return f.read(2) == b"\x1f\x8b"


def read_first_line(path: Path) -> str:
    opener = gzip.open if is_gzip(path) else open
    with opener(path, "rt", encoding="utf-8-sig") as f:
        return f.readline()


def read_wide(path: Path, compression) -> pd.DataFrame:
    raw = pd.read_csv(path, sep="\t", dtype=str, compression=compression)
    first = raw.columns[0]
    dim_names = [d.strip().lower() for d in re.split(r"[\\/]", first)[0].split(",")]
    dims = raw[first].str.split(",", expand=True)
    dims.columns = dim_names
    wide = pd.concat([dims, raw.drop(columns=first)], axis=1)
    wide.columns = [c.strip() for c in wide.columns]
    return wide.melt(id_vars=dim_names, var_name="period", value_name="value")


def read_long(path: Path, compression) -> pd.DataFrame:
    raw = pd.read_csv(path, dtype=str, compression=compression, encoding="utf-8-sig")
    raw.columns = [c.strip() for c in raw.columns]
    keep = [c for c in ["freq", "purchase", "unit", "geo"] if c in raw.columns]
    missing = {"geo", "TIME_PERIOD", "OBS_VALUE"} - set(raw.columns)
    if missing:
        sys.exit(f"Unexpected columns {list(raw.columns)}; missing {sorted(missing)}")
    flag = ["OBS_FLAG"] if "OBS_FLAG" in raw.columns else []
    return raw[keep + ["TIME_PERIOD", "OBS_VALUE"] + flag].rename(
        columns={"TIME_PERIOD": "period", "OBS_VALUE": "value", "OBS_FLAG": "obs_flag"}
    )


def load(path: Path) -> pd.DataFrame:
    compression = "gzip" if is_gzip(path) else None
    header = read_first_line(path)
    df = read_wide(path, compression) if "\t" in header else read_long(path, compression)

    # Guard: the file must contain codes, not labels (e.g. "Croatia" instead of "HR")
    geos = set(df["geo"].astype(str).str.strip())
    if "HR" not in geos and "Croatia" in geos:
        sys.exit(
            "This file contains text labels (e.g. 'Croatia') instead of codes (e.g. 'HR').\n"
            "Re-download with codes: use labels=id in the API URL "
            "(or choose 'Codes' in the Eurostat download dialog)."
        )

    # Wide format hides the flag inside the value ("123.4 p"); pull it out
    if "obs_flag" not in df.columns:
        df["obs_flag"] = df["value"].astype(str).str.extract(r"[\d.]\s*([a-z]+)\s*$", expand=False)
    df["obs_flag"] = df["obs_flag"].astype("string").str.strip()

    # Eurostat values can look like "123.4 p" (flag) or ":" (missing)
    df["value"] = (
        df["value"].astype(str).str.extract(r"(-?\d+\.?\d*)", expand=False).astype(float)
    )
    df["period"] = df["period"].str.strip()
    df = df.dropna(subset=["value"])

    df = df.rename(columns={"geo": "country_code"})
    df["country_code"] = df["country_code"].str.strip()
    df["year"] = df["period"].str[:4].astype(int)
    df["quarter"] = df["period"].str[-1].astype(int)
    df["is_aggregate"] = df["country_code"].map(is_aggregate_code)
    cols = ["country_code", "is_aggregate", "purchase", "unit",
            "period", "year", "quarter", "value", "obs_flag"]
    return df[cols].sort_values(["country_code", "purchase", "unit", "period"])


def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: python scripts/01_load_clean.py <path-to-eurostat-file>")
    tidy = load(Path(sys.argv[1]))

    out = Path("data/processed/hpi_tidy.csv")
    out.parent.mkdir(parents=True, exist_ok=True)
    tidy.to_csv(out, index=False)

    # Quick quality report
    print(f"Saved {len(tidy):,} rows -> {out}")
    print("Countries:", tidy["country_code"].nunique())
    print("Units:", sorted(tidy["unit"].unique()))
    print("Purchase types:", sorted(tidy["purchase"].unique()))
    hr = tidy[(tidy.country_code == "HR") & (tidy.unit == "I15_Q") & (tidy.purchase == "TOTAL")]
    if hr.empty:
        print("WARNING: no Croatia (HR) rows found for TOTAL / I15_Q")
    else:
        print(f"Croatia coverage: {hr.period.min()} -> {hr.period.max()} ({len(hr)} quarters)")


if __name__ == "__main__":
    main()
