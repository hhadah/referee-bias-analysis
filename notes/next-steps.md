# Recommended next steps

2026-10-03

The next round should repair source coverage before adding models. Then widen
Barcelona's comparison group to clubs with similar playing styles. More
precise estimates of recorded decisions still do not establish whether those
decisions were correct.

These are recommendations, not analyses already completed. The current
[report](../output/analysis-report.html) contains the specification comparisons,
pooled Champions League estimates, seasonal shrinkage, precision calculations
and early-card diagnostic. The [research design](research-design.md) describes
those implementations.

## 1. Repair fixture and penalty coverage before interpreting rare outcomes

Start with `04-clean-espn.R`, `05-build-team-match-panel.R` and the coverage
manifests produced by `20-build-analysis-report.R`.

- Separate empty ESPN records from genuine score disagreements. For example,
  cached event `420601`, Granada versus Barcelona in 2011/12, has empty team
  statistics, no key events, a 0-0 score and `isFinal = false`, despite its
  `STATUS_FULL_TIME` label. The current score-disagreement audit does not
  distinguish that case from two substantive sources reporting different
  results. Add box-score presence, event-log presence and an empty-record flag
  to the audit. Resolve scores against a documented source before they update
  Elo; do not count empty records as verified draws. Keep on-pitch and
  administratively awarded scores separate.
- Audit scheduled and missing-status records in completed seasons across all
  six competitions. Refresh the affected event IDs, including the stale
  2022/23 La Liga fixtures, rather than re-downloading every match. Report
  missing statuses before filtering, and reconcile fixture lists as well as
  aggregate match counts. The current "completed matches" label reflects
  parsed status, not an independent fixture-completeness audit.
- Validate penalty logs against an independent match report or event source.
  An end marker and reconciled goals do not establish that penalty labels or
  missed penalties were recorded. Use unusually low league-season penalty
  rates as coverage warnings, not automatic proof of incomplete data. Inspect
  suspect seasons, including early Champions League seasons, and compare an
  independently validated sample with the current eligible sample. If a
  rate-based exclusion remains as a sensitivity check, fix its rule before
  comparing club coefficients and disclose the resulting sample changes.

Completion criterion: every missing fixture, empty record and score conflict
has an explicit disposition; penalty eligibility and verified coverage are
separate fields; Elo and all affected estimates are rebuilt from the repaired
inputs. Preserve the raw downloads and retain source provenance.

## 2. Compare Barcelona with teams that actually play like Barcelona

The La Liga prior-style diagnostic reports almost no overlap between Barcelona
and non-elite clubs. Adding more flexible splines does not supply observations
at the missing possession levels.

Extend `17-barcelona-style-adjusted-decisions.R` with a pooled five-league
comparison. Manchester City, Bayern Munich and Paris Saint-Germain are
candidate peers, not automatically valid controls. Measure their overlap with
Barcelona in prior possession, attacking activity and expected strength before
choosing a comparison sample.

Use league-by-season and opponent fixed effects, venue and pre-match strength
controls. Compare common style slopes with league-specific slopes as a
sensitivity check. Cross-league comparisons require assumptions about different
officiating environments; domestic league fixed effects alone do not make
those environments interchangeable. Retain the La Liga-only analysis.

Hold each outcome's sample fixed across specifications. Report how many
Barcelona matches remain within joint support, the balance of the retained
sample, and which seasons are lost. Do not describe a trimmed population as
representing every Barcelona match.

Deliverable: a pooled-versus-La-Liga comparison figure accompanied by a
possession-overlap plot and sample-flow table. Prefer a smaller defensible
comparison to an apparently precise extrapolation.

## 3. Make the early-card sample representative of Champions League stages

`19-card-timing-diagnostics.R` currently constructs five-match style histories
within competition and season. This requires a long CL history before a match
can enter and can disproportionately remove group-stage matches.

Construct prior style from each club's strictly earlier domestic and CL
matches, ordered by date. An expanding mean of valid prior observations, with
at least three observations required, is a simple starting point. Report the
age and number of observations contributing to each history. Never use the
current match or later information.

Publish sample retention by competition, season and stage before interpreting
the estimates. Compare first-30-minute and full-match outcomes on identical
eligible matches. Where event coverage permits, add score state and manpower
immediately before each incident. These remain descriptive diagnostics unless
the incident opportunities are comparable.

## 4. Keep Champions League precision gains tied to a stated estimand

Retain the pooled average comparisons and the implemented empirical-Bayes
seasonal estimates. Keep the full covariance of seasonal coefficients,
heterogeneity sensitivity, and unpooled estimates visible. Shrinkage estimates
answer a model-dependent question; they do not create additional matches.

- Decide whether the primary question concerns the average gap, knockout
  matches, or a particular era before selecting a specification. Report the
  available matches and seasons for each. Do not select title-winning seasons
  after observing outcomes.
- Specify substantively meaningful equivalence margins for cards and penalties
  before interpreting null results. Keep minimum detectable effects beside
  confidence intervals; a wide interval is not evidence of equal treatment.
- Add an all-club coefficient-versus-precision display if useful. Use the
  fitted model's clustered covariance and an explicit reference contrast.
  A naive funnel based only on residual standard deviation divided by the
  square root of matches ignores schedule differences, paired observations
  and clustering. Calibrate any outlier limits and account for looking across
  many clubs.
- Keep domestic data useful for predicting style and strength without assuming
  that domestic and UEFA refereeing effects are identical.

Deliverable: one chart separating pooled uncertainty, annual uncertainty and
conditional shrinkage intervals, with the estimand and assumptions stated.

## 5. Collect incident opportunities and independent correctness judgments

The most informative new outcome would be an incorrect decision per comparable
incident, not simply more fouls, fewer cards or a favorable penalty balance.

Draw a documented sample of matches, not a collection of famous controversies.
Record called and uncalled incidents, including penalty-area contacts, possible
handballs and card-worthy challenges. Code severity, location, possession or
attacking opportunity, score state, manpower, referee and VAR involvement.
Use independent reviewers who do not know the study's desired result; mask club
identity where feasible. Record disagreement and adjudication rules.

Separate favorable incorrect calls, unfavorable incorrect calls, missed calls
and correct decisions. Check coverage and reviewer agreement before comparing
clubs. VAR reversals alone are not a correctness rate because they omit
incidents that were never reviewed. This requires new data beyond the current
match totals and key-event logs.

## 6. Revisit stoppage time without discarding the outcome

Elapsed time after 90 minutes is a usable descriptive outcome even when the
announced minimum is unavailable. The distinction between elapsed time and
the board number is not, by itself, grounds to dismiss the analysis.

Reconstruct score state at 90 minutes and model interruptions before and during
stoppage time, including goals, substitutions, injuries and VAR delays where
observed. Separate close-match score states and competition-era rules. If the
announced minimum can be collected, analyze it separately from additional time
played beyond that minimum. Incomplete interruption data remain a confounder;
a trailing-versus-leading difference alone does not identify favoritism.

## 7. Update the paper only after the revised data and comparisons are frozen

Keep favorable, adverse and imprecise results in the same reporting framework.
In particular, retain Madrid's adverse called-foul-adjusted yellow-card result
and Barcelona's adverse net-red-card comparison against non-elite clubs
alongside the exploratory favorable Barcelona CL comparison. Identify which
contrasts belong to the headline multiple-testing family and which do not.

The 2018 split remains descriptive because payment timing overlaps with VAR
and changes in squads and performance. A causal interpretation needs a
separate identification argument, not only a before/after coefficient.

The original manuscript and programs 06-16 remain historical material. Before
using them in an updated paper, regenerate the exhibits that will be retained,
replace superseded text, and reconcile every numerical claim to the same run.
Do not mix historical tables with rebuilt supplement results without labeling
the difference.

After source-data repairs, run the cached-source rebuild:

```bash
Rscript programs/95-make-all.R
latexmk -cd -pdf -interaction=nonstopmode -halt-on-error my_paper/analysis-update.tex
```

Use `--analysis-only` only when the built panel is already current. Use
`--legacy` when intentionally regenerating the historical exhibits; it does
not validate their old interpretations. Keep the run ID, input hashes,
verification results and package versions with the numerical outputs.

## Recommended order

Finish the source audit and rebuild first. Next, implement the five-league
style comparison and repair the early-card history. Then assess CL precision
under the revised samples. Pilot independent incident coding before expanding
it. Integrate the paper last, after deciding which comparisons the data can
support.
