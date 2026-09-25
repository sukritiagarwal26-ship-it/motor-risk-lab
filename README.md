# The rare claim problem

**[Open the interactive website](https://sukritiagarwal26-ship-it.github.io/motor-risk-lab/)**

An independent actuarial statistics portfolio project by **Sukriti Agarwal**. The interactive case study estimates motor liability claim frequency, tests whether segmentation helps claim severity, and explores an illustrative per-claim excess-of-loss layer.

## Main result

The exposure-offset Poisson GLM improved held-out claim-count deviance from **0.2569** to **0.2531** per policy and produced a test-set count O/E of **0.997**. A Gamma severity GLM performed worse than the constant training mean on validation, so the final expected-loss model uses the constant mean severity. The held-out aggregate loss O/E was **0.808** (policy bootstrap 95% interval **0.701–0.948**). This gap is material: the training claim mean was **2,264 amount units**, versus **1,834** in test. Only **59 of 16,181** claims exceeded 50,000, yet they contributed **28.6%** of recorded loss.

The result supports segmenting frequency, while treating the severity tail as a major uncertainty. It does not support using this model as a commercial premium or treaty quote.

## Reproduce

Requires R (base installation) and Python 3 (standard library only).

```sh
Rscript analysis.R
python3 build_site.py
python3 -m http.server 8000
```

Open `http://localhost:8000`. The R script downloads two pinned source files into `data/`, checks the linkage and row counts, fits the models, and writes CSV result tables. The Python script turns those tables into `data.js` for the static site. Raw source files are fetched directly from the CASdatasets authors and are not included in this project.

### Data source and citation

- C. Dutang and A. Charpentier, *CASdatasets: Insurance datasets*, DOI [10.57745/P0KHAG](https://doi.org/10.57745/P0KHAG).
- [Authors’ documentation for `freMTPLfreq` and `freMTPLsev`](https://dutangc.github.io/CASdatasets/reference/freMTPL.html).
- [Pinned CASdatasets source commit](https://github.com/dutangc/CASdatasets/tree/227fb56b8734bdb7c0327a41180e01d2ddaeaf26).

The pinned files contain 413,169 policies and 16,181 positive claim amounts. `PolicyID` links policies to claims, and policy `ClaimNb` matches the number of linked claim records. `Exposure` is in years. The data provider describes the source as an unknown private insurer and does not specify the currency of `ClaimAmount`; this project therefore uses **amount units**. Some claim amounts are fixed under the French IRSA-IDA settlement convention. The package declares GPL ≥2. This repository publishes code and derived aggregates; readers fetch the source files from the authors.

## Statistical design

1. **Audit:** Validate unique policy IDs, positive exposure and claim amounts, complete claim linkage, and policy count equality.
2. **Split:** Assign whole policies to 70% train, 15% validation and 15% test with seed `20260925`; claims inherit the parent policy’s split. This prevents a policy from appearing in both fitting and evaluation.
3. **Frequency:** Fit a Poisson log-link GLM with `log(Exposure)` as an offset. Predictors: binned driver age, binned vehicle age, binned vehicle power, fuel, region and `log(1 + Density)`. Compare with a single portfolio rate per exposure-year.
4. **Severity:** Fit a positive-claim Gamma log-link GLM on the same pre-claim predictors except density. Compare with the training-claim mean.
5. **Select:** Compare mean validation deviance for each candidate against its baseline. Retain the frequency GLM; use baseline severity. Do not select on the test set.
6. **Test:** Report held-out mean Poisson and Gamma deviance, aggregate O/E, policy-level mean absolute cost error, count dispersion, and calibration in ten predicted-cost groups. Bootstrap test policies 400 times for an interval on **held-out total-cost O/E with the fitted model held fixed**.
7. **Layer:** For attachment `a` and limit `L`, calculate `min(max(S-a,0),L)` for each observed claim. Multiply its empirical mean by portfolio claim frequency to express expected ceded amount per exposure-year. This assumes the observed claim distribution and frequency combine as shown; it is a sensitivity calculation.

The methods map to [IFoA CS1’s 2026 syllabus](https://actuaries.org.uk/media/5xzbwoyf/cs1_syllabus-2026-_final-proof.pdf): distributions, GLMs, likelihood-based model comparison, model checks and bootstrap uncertainty.

## Interpretation and limits

- Claim-count performance is a modest improvement. Training Poisson Pearson dispersion is **1.68**, so a basic Poisson variance assumption understates variation.
- The severity candidate lost to the baseline on validation; selecting the simpler component was a deliberate decision. The final combined model still overpredicts test loss. The bootstrap interval quantifies variation in this particular held-out ratio, not uncertainty in fitted parameters or future claims.
- The data do not provide the original insurer’s identity, a stated period for this dataset, a currency, event identifiers, commercial premiums, expenses, inflation indices or capital costs.
- Fixed settlement amounts and sparse high claims distort the observed severity shape. At an attachment of 50,000, only 59 claims are above attachment in the full sample. High-layer estimates are particularly fragile.
- Regions follow the source’s historical classification and do not imply present geographic risk. Correlation, selection effects and changing claims practices may affect transfer to another book.

This project is independent and is not affiliated with CASdatasets, the original insurer or Munich Re.

## Files

- `analysis.R`: source acquisition, audits, modelling and result tables.
- `build_site.py`: static data bundle generation.
- `results/*.csv`: derived tables used in the site; no policy or claim-level records.
- `index.html`, `styles.css`, `app.js`, `data.js`: public site.
