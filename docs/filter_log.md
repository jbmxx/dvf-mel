# Filter log — DVF raw → clean price/m² dataset

Scope: Métropole Européenne de Lille, 95 communes, 2021–2025
Source: 5 raw DGFiP files, 20,382,915 rows, 2.6 GB
Engine: DuckDB 1.5.5 — full 5-file scan in 2.4s, no import step

## Row-level baseline

| Year | Raw rows |
|------|----------|
| 2021 | 4,674,542 |
| 2022 | 4,676,187 |
| 2023 | 3,817,426 |
| 2024 | 3,499,931 |
| 2025 | 3,714,829 |

Rows per mutation (2021, national): 2.69 — 63% of raw rows are repetitions of
the same sale price across parcels and lots.

## Mutation-level filter cascade (MEL, 2021–2025)

| # | Filter | Remaining | Dropped | % of initial |
|---|--------|-----------|---------|--------------|
| 0 | MEL mutations, deduplicated | 109,184 | — | 100.0% |
| 1 | `Nature mutation = 'Vente'` | 99,391 | 9,793 | −9.0% |
| 2 | Non-null transaction value | 98,928 | 463 | −0.4% |
| 3 | Exactly one built property | 76,975 | 21,953 | −20.1% |
| 4 | No commercial premises | 75,404 | 1,571 | −1.4% |
| 5 | Built surface > 0 | 75,388 | 16 | −0.01% |
| 6 | Price ≥ €10,000 | 75,298 | 90 | −0.08% |

**Retention: 69.0%** (75,298 usable mutations from 109,184).

### Breaking down filter 3

The headline 20% loss is mostly out-of-scope data rather than discarded
transactions:

| Built properties in mutation | Mutations | Share |
|------|-----------|-------|
| 0 (bare land, agricultural plots) | 15,943 | 16.1% |
| 1 (**retained**) | 76,975 | 77.8% |
| 2–3 | 4,556 | 4.6% |
| 4–10 | 1,298 | 1.3% |
| 11+ (block sales) | 156 | 0.2% |

Bare land carries no built surface and is irrelevant to a price/m² study.
Genuine multi-property sales — where a single price covers several dwellings
and cannot be allocated per unit — account for 6.1%.

## Known limitations of the composite key
- Two distinct sales, same day, same commune, same price → merged into one.
- A single sale spanning several communes → split into several keys (see §audit).

## Gotchas

**Commune codes are not zero-padded.** Raw file stores `9`, not `009`.
Full INSEE code must be built as `"Code departement" || lpad("Code commune", 3, '0')`
→ `59` + `009` = `59009`. Skipping this silently drops ~half the rows
on any join with an external INSEE-keyed dataset.

**`Code type local` is NULL for bare land** (agricultural plots, woods,
building land). Not a data quality issue — these rows are simply out of
scope for a price/m² study.

**`count(DISTINCT ...)` ignores NULLs.** A mutation showing `n_types = 0`
contains no built property at all.

## Audit note — composite key fragmentation

The composite key (`date + disposition + value + dept + commune`) has two
failure modes, in opposite directions:

1. **Merge** — two unrelated sales, same day, same commune, same price
   collapse into one. Anticipated from the start.
2. **Split** — one real mutation spanning several communes is broken into
   as many keys. Discovered during audit.

Measuring (2) required care. A first attempt keyed on
`date + disposition + value` without commune returned 699,251 groups against
1,739,833 mutations — a 60% collapse, not credible. With `No disposition`
almost always `000001` and prices overwhelmingly round, unrelated sales
collide constantly at ~4,700 mutations/day nationwide. The query was
measuring coincidence, not structure.

Restricting to non-round values (near-unique within a year) gives a usable
signal: 28,315 of 437,788 mutations span multiple communes (6.5%). But the
distribution shows these are almost entirely artefacts — 1,772 of the 1,822
worst cases span multiple *departments*, and the top offenders are €1
transfers (disguised gifts, intra-family conveyances) removed by the price
floor anyway.

One genuine case stands out: 2021-07-29, €220,623,264, 141 communes within a
single department, 19,482 rows — a social housing portfolio transfer, truly
fragmented by the key. Such mutations are removed by the "exactly one built
property" rule.

**Second measurement error, same cause.** Re-running the fragmentation check
on filter-eligible mutations (single built property, price ≥ €10k) initially
returned 67% fragmented — because the non-round-value restriction was not
carried over. Single-built-property sales are ordinary house and flat
transactions, i.e. exactly the population with the roundest prices, so
collisions dominate. A control filter must be restated in every query that
depends on it; it does not carry forward.

**Verdict.** With the control filter correctly applied, 6,123 of 221,670
eligible non-round-value mutations are fragmented (2.8%) — but 5,966 of them
span multiple departments, i.e. they are residual collisions, not splits.
Genuine same-department fragmentation affects 157 mutations, **0.07%** of the
eligible population.

The composite key is accepted for this study. The residual error is an order
of magnitude below the uncertainty introduced by the price floor and the
single-built-property rule. Documented, bounded, and reported rather than
hidden.

**Order of magnitude going in:** 941,272 national mutations pass
`Nature mutation = 'Vente'` + exactly one built property + price ≥ €10,000
for 2021.

## Scope definition — MEL perimeter

The study area is the Métropole Européenne de Lille (95 communes, EPCI
`200093201`). Rather than hardcoding 95 INSEE codes into every query, the
list is pulled once from the official `geo.api.gouv.fr` endpoint and stored
as a reference table:

    CREATE OR REPLACE TABLE communes_mel AS
    SELECT code AS code_insee, nom AS nom_commune
    FROM read_json_auto(
      'https://geo.api.gouv.fr/epcis/200093201/communes?fields=nom,code'
    );

Exported to `data/ref/communes_mel.csv` (versioned in the repo). Every
downstream query filters by joining this table — the perimeter lives in the
data, not in the code, and is reproducible from an authoritative source in
one command.

**Join key.** DVF stores `Code commune` unpadded (`9`, not `009`), so the
INSEE code must be rebuilt as
`"Code departement" || lpad("Code commune", 3, '0')`.
Villeneuve-d'Ascq is `59009` — without the padding it becomes `599` and
drops out of the join with no error raised.

**Join validated on 2021:** all 95 MEL communes are present in the raw file,
zero unmatched on either side.

**Associated communes.** Lomme and Hellemmes-Lille hold their own INSEE codes
but DVF reports them under Lille (`59350`) — a single row for the whole
commune, 13,674 rows in 2021. No silent data loss, but Lille's median blends
three distinct submarkets. Cannot be disaggregated from DVF alone; stated as
a known limitation rather than worked around.

## Methodological check — do outbuildings inflate €/m²?

DVF reports the total transaction price but only the built surface of the
main dwelling. A sale bundling a flat with a cellar and a parking space
should therefore show an inflated €/m². Aggregate figures appeared to
confirm this: €2,617/m² with no outbuilding, €2,822 with 1–2, €3,128 with 3+.

Controlling for property type reverses the picture for flats:

| Type | Outbuildings | n | Median €/m² | Median surface |
|------|--------------|---|-------------|----------------|
| Flat | 0 | 7,403 | 3,523 | 40 m² |
| Flat | 1–2 | 20,110 | 3,015 | 60 m² |
| Flat | 3+ | 1,632 | 3,178 | 83 m² |
| House | 0 | 35,052 | 2,510 | 89 m² |
| House | 1–2 | 10,830 | 2,538 | 84 m² |
| House | 3+ | 271 | 2,654 | 96 m² |

Flats with no outbuilding are the *most* expensive per m², because they are
studios (40 m² median) — small units command a premium per square metre and
rarely come with a cellar or parking. The aggregate pattern was a
composition effect, not a pricing one.

For houses, where median surface is stable, a genuine effect remains:
+5.7% for 3+ outbuildings, on 271 mutations.

**Decision: outbuildings are retained.** Excluding them would remove ~40% of
the sample to correct a ~5% bias on a marginal subgroup. The residual bias is
documented rather than traded for a loss of statistical power.

## Outlier bounds

| Filter | Remaining | Dropped | % |
|--------|-----------|---------|---|
| Clean sample (after cascade) | 75,298 | — | — |
| Built surface 9–400 m² | 75,287 | 11 | 0.015% |
| €/m² between 500 and 15,000 | 74,937 | 350 | 0.46% |

**Final sample: 74,937 mutations, 68.6% of the 109,184 MEL mutations.**

Bounds are set on domain reasoning, not percentiles. The 9 m² floor is the
legal minimum surface for a habitable dwelling in France. The €500/m² floor
is below any plausible market transaction in the MEL; the €15,000/m² ceiling
sits well above prime Vieux-Lille (€6,000–7,000/m²).

**The composite key's split behaviour, observed.** Three 2024 mutations in
three different communes (59527, 59286, 59378) share the exact value
€3,435,641.50 across houses of 32, 47 and 48 m² — one real transaction
fragmented by the key, the same-department case the audit bounded at 0.07%.
The €/m² ceiling removes all three. Other extremes: a €722.6M "house" of
119 m² (portfolio transfer), a €132,000 flat recorded as 1 m² (missing
surface), 94 m² Lille flats at €14M (whole-building sales misfiled).

## Output — median €/m² by commune × type × year

795 cells covering 95 communes, 2 property types, 5 years.

| Sales per cell | Cells | Sales | Share |
|------|-------|-------|-------|
| < 5 | 119 | 242 | 0.3% |
| 5–9 | 71 | 500 | 0.7% |
| 10–29 | 199 | 3,427 | 4.6% |
| 30+ | 406 | 70,768 | 94.4% |

Cells below 10 sales are flagged `fiable = false` rather than deleted: a
missing cell in a dashboard reads as a bug, a flagged one reads as a
documented limitation. 605 cells (99.0% of sales) meet the threshold.

**Sanity check.** Lille flats: €3,722/m² (2021) → €3,864 (2022) → €3,857
(2023) → €3,669 (2024) → €3,713 (2025), with volume falling from 3,142 to
2,057 sales before recovering. The pipeline reproduces the documented French
market cycle — low rates, then the rate-driven contraction, then
stabilisation — without any tuning for it.