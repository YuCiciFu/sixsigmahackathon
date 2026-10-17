# H-02 audit of the published b07d1a3 dataset

## Versions and scope

- Data, generator and original codebook: `b07d1a3ddef5873029e7f8c6393f8e14ad61ceff`, branch `h02-dataset`.
- Latest merged main inspected: `9f091b76f557062d86868dd93be5366d61cd2290`.
- `app/qc.R` last changed in `4449a2be123e29503557f2bbda47c5792e085494`; source MD5 `4fac1921cacea372ae06af24620d79c5`.
- `docs/methods.md` last changed in `aecf9495923e1103f99485d5ce94847cfc0275b0`.
- No Web integration was merged into this branch. No `app/` file, generator, or scenario CSV was changed during this audit.

All reported control limits and flags below come from the merged H-03 `p_chart` and `imr_chart`, not the earlier Python implementation. Run the diagnostic with:

```sh
Rscript data/audit_h02.R /path/to/pinned/app/qc.R . data/audit
```

The qc source must be obtained from the pinned main commit above, or supplied from a checkout of that commit. The script accepts the path to the source; it does not fetch or overwrite app code.

## Blocking loader compatibility finding

Original CSV timestamps end in `-0400`; H-03 `parse_ts` only accepts `Z` or a colon offset such as `-04:00`. Consequently the unmodified H-03 loader retains the station registries but rejects ALL status, attempt and task rows from b07d1a3 as timestamp problems. Retained status/attempt/task counts are 0/0/0 for all three original files. The earlier Python schema checks accepted `-0400` and did not expose this mismatch.

For this diagnostic ONLY, the script converts offset text from `-0400` to `-04:00` in memory, then runs H-03 validation and calculations. The original CSVs and generator are untouched. Therefore the chart results below are conditional on this documented normalization; they do not mean the original CSVs load correctly into H-03 as published. A separately reviewed format fix or loader compatibility decision is needed before integration acceptance.

## Exact chart definition

Primary audit baseline: weekdays 1–10, 2026-09-21 through 2026-10-02, independently within each scenario. Monitoring dates are weekdays 11–20, 2026-10-05 through 2026-10-16. Each subgroup counts all recorded return attempts in [07:00, 10:00) America/New_York across the 25 stations, from the H-03-cleaned attempt table. No outcome is inferred by the audit from inventory.

H-03 estimates p-bar as pooled baseline failures / pooled baseline attempts. It uses variable limits p-bar +/- 3 sqrt(p-bar(1-p-bar)/n), bounded to [0,1]. Rule 1 tests BOTH the upper and lower limits; rule 4 flags the eighth and later consecutive point on the same side of the center line. Flags are evaluated on baseline as well as monitoring points. Thus a baseline signal is visible; its inclusion in phase I does not make it automatically acceptable.

For planted_shift return attempts, baseline totals are 452/15047 and p-bar = 3.0039210474%.

| Day | Date | Failed / attempts | p (%) | LCL (%) | UCL (%) | Rule 1 | Rule 4 |
|---|---|---|---|---|---|---|---|
| 1 | 2026-09-21 | 23/1483 | 1.5509 | 1.6742 | 4.3337 | TRUE | FALSE |
| 8 | 2026-09-30 | 17/1478 | 1.1502 | 1.6719 | 4.3359 | TRUE | FALSE |
| 9 | 2026-10-01 | 79/1549 | 5.1001 | 1.7028 | 4.3050 | TRUE | FALSE |
| 10 | 2026-10-02 | 76/1538 | 4.9415 | 1.6982 | 4.3097 | TRUE | FALSE |
| 11 | 2026-10-05 | 1440/4500 | 32.0000 | 2.2405 | 3.7673 | TRUE | FALSE |

Day 9 and day 10 exceed their upper limits: both trigger rule 1 and neither triggers rule 4. They are before the engineered intervention. Days 1 and 8 are also rule-1 signals, below their lower limits. The previous README note about days 9/10 was incomplete because the old Python checker only listed upper-limit exceedances.

With the same first-ten-day baseline, planted_shift return rule-1 signals are days 1, 8, 9, 10 and 11–20. Return rule-4 signals are days 16–20 (the above-center run starts at day 9). I-MR rule-1 signals are days 11–20, rule-4 signals days 15–20, and the moving range signals on day 11. The engineered change is detected, but the pre-change p-chart baseline is not in control under the stated rules.

## Does baseline also signal?

Yes. With weekdays 1–10 as its baseline, baseline return p-bar is 310/15135 = 2.0482325735%. Return rule-1 signals occur on days 3, 4, 6, 7, 13, 16 and 20; no return rule-4 signals occur. Rent rule-1 signals occur on days 7, 10, 14, 15, 16, 19 and 20. The baseline I-MR chart has no rule-1, rule-4 or MR signal.

As a separately labelled phase-I sensitivity calculation, using all 20 baseline-scenario weekdays to estimate return limits gives p-bar = 2.489627%, with rule-1 signals on days 3, 5, 7, 9, 10, 14, 16 and 20; no rule-4 signal. This does not repair the lack of control. Do not use all 20 planted_shift days as the primary baseline: that includes the engineered intervention and contaminates the limits. Results for that diagnostic are saved only for transparency in the result tables.

Therefore `baseline` does not meet the methods description “in control” for its p charts, although its I-MR chart has no signal. A signal is a chart result under the specified assumptions, not proof that the intervention started early or proof of a specific real-world cause.

## Why the early p-chart signals occur

The intervention branch explicitly requires scenario == planted_shift AND day >= 11 AND rush hour. On weekdays 1–10 all failed returns in both scenarios have reason `no_dock` (baseline 310; planted_shift 452); none is a planted `dock_fault`. On day 9 the 79 failures are contributed by S012 (17), S020 (16), S002 (15), S005 (15), S011 (8), S006 (5), S014 (3). On day 10 the 76 failures are contributed by S011 (28), S017 (19), S005 (10), S012 (9), S023 (6), S009 (4).

The generator evolves inventory as a bounded minute-by-minute random walk and labels attempts from the current inventory. A station can remain full, so successive return failures cluster. This is not an independently sampled common-probability Bernoulli stream. Stations also have different initial inventories and demand transition probabilities. The generator's time-invariant pre-change rules do not guarantee a binomial, statistically in-control network p chart.

Evidence of clustering, using successive recorded return attempts within each station-day in weekdays 1–10: after a failed return the next return fails 68.33% of the time in planted_shift, versus 0.989% after a success; the corresponding baseline figures are 61.24% and 0.816%. These descriptive conditional rates are not estimates of intervention effects.

A diagnostic Pearson dispersion across the ten daily proportions, sum((fail-n*pbar)^2/(n*pbar*(1-pbar)))/9, is 10.113 for planted_shift and 14.056 for baseline. This is substantial extra-binomial daily variation relative to the nominal p-chart variance. It supports the generator/assumption mismatch explanation; it is not a formal independent-data hypothesis test, and no control limits were widened or data tuned to remove the signals.

Finally, set.seed is called once for the entire three-scenario script. baseline consumes the RNG stream before planted_shift. The first ten planted_shift days are therefore a separate random realization, not copies of baseline's first ten days. The two scenarios share the network layout, not matched pre-change demand/inventory histories.

## Reproducibility

A fresh full run of the exact b07d1a3 generator under R 4.6.1 reproduced all three committed CSVs byte for byte. The earlier two-run check was also consistent. Repeat the complete script in its original scenario order; calling the internal run function separately does not reset the random seed.

| File | Rows (excluding header) | SHA-256 |
|---|---|---|
| baseline.csv | 240800 | `2ab2764e7754037bccdf119aa23a88bd0332ca5aaa3a5faf54dd9bc3524aefc0` |
| planted_shift.csv | 330866 | `cfcedbc0a5462b1d51849d170063e6fee126bb8393f2a12894bc133af1a28813` |
| edge_case.csv | 956 | `c8d98fde632867bdcadbd810db2a48a63e68d2d673a7971ad4e0cbc64fe0599e` |

No cross-version R/tzdata reproducibility claim is made. Reproducibility is distinct from a valid in-control scenario or loader compatibility.

## Codebook and scenario expected results

- All 27 union-schema columns, units, non-applicable blanks, source labelling, and real collection sources are covered by the codebook. All rows are simulated. Two large scenarios have 25 station rows, 150500 raw status rows (301 times/day/station), 20 weekdays, two vans and 60 completed tasks (three/day). baseline has 90215 attempts; planted_shift has 180281. Task response times are 9, 10, 11 minutes each day; the KA-7 example is a separate arithmetic example, not this scenario's measured task output.
- The timestamp notation is incompatible with H-03 as described above. Successful Python validation alone was insufficient. The current in-control wording and the earlier early-signal note require qualification; the observed chart tables are the expectation for this fixed seed, not a reason to edit the observations to fit a label.
- After diagnostic offset normalization, H-03 reports no row issues for baseline or planted_shift. Every day has 4500 known rush-hour station-minutes and 100% coverage.
- edge_case has 2 stations, 599 raw status rows and 355 attempts, no task rows. The schema supports the tasks record type, but the tiny file has no actual tasks. At S002 07:06 there are THREE conflicting rows (the original plus two additions), all rejected by H-03. After normalization the clean status count is 596 and H-03 reports three conflicting-duplicate issues. S001 has 180 known minutes, 100% coverage, zero rent/return/either failures. S002 has 178 known minutes, two unknown (07:12 and 07:13), 98.8889% coverage and 65 rent-unusable minutes. The 07:05 omission and 07:06 conflict fall back to earlier valid snapshots; neither adds an unknown minute under stale_limit = 2. No return attempts exist in this tiny scenario; its return p is NA. With one day, control limits are NA rather than an invented estimate.
- data/expected_results.md documents independent formula known answers. It does not supply scenario expected outputs. The concrete scenario results above and the CSV audit tables fill that documentation gap. The user subsequently approved moving the two H-02-added files out of tests/: they now live at data/validate_schema.py and data/expected_results.md. Actual H-03 tests and fixtures were not changed.
- The generator is an inventory/attempt fixture, not an event-conserving simulator; no conservation or integration claim is made.

## Disposition

H-02 remains in_progress. Do not sign it off as fully accepted: timestamp compatibility and p-chart baseline validity are unresolved. The file-ownership migration was approved by the user and completed in a subsequent commit. No seed changes, failure changes, control-limit changes, or dataset regeneration into the repository were made. H-05 is deferred until H-02 review/closure, so the same owner does not hold two active tasks.
