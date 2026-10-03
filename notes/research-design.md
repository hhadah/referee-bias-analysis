# Research design notes

The original design below is retained to preserve its research questions and
specification references. The October 2026 update supersedes its measurement
and inference claims. In particular, club ranks are not randomization tests,
and cards conditional on called fouls do not isolate referee discretion.
The [next-step recommendations](next-steps.md) distinguish proposed work from
the analyses already implemented.

*Last updated: 2026-10-02*

## Questions

1. Do referees make systematically more favorable decisions for some clubs than
   for others in the top-5 European leagues and the Champions League?
2. Where does FC Barcelona sit in the cross-club distribution of
   refereeing favorability, and how does it compare with Real Madrid and the
   other perennial Champions League clubs?
3. Is Barcelona's treatment by Spanish referees (La Liga) different from its
   treatment by UEFA-appointed referees (Champions League)? Did it change
   after 2017/18, the last season of the reported payments to José María
   Enríquez Negreira, then vice-president of Spain's referees' committee (CTA)?

## Outcomes (team-match level, from team *i*'s perspective)

| Decision | Against *i* | For *i* |
|---|---|---|
| Yellow cards | `own_yellow` | `opp_yellow` |
| Red cards | `own_red` | `opp_red` |
| Fouls called | `own_fouls` | `opp_fouls` |
| Penalties | `opp_pens` (conceded) | `own_pens` (awarded) |
| Stoppage time | Added time when *i* leads vs. trails by one at 90' | |

`net_*` = for − against. `yellow_per_foul` = cards conditional on a foul being
called, which isolates the referee's discretion over severity.

## Specifications

- **Eq. (1), Table 2.** Club indicators (Barcelona, Real Madrid, other elite)
  plus home, opponent fixed effects (FE), league × season FE, and pre-match
  win-probability ventile FE (from bookmaker odds). Panel B adds possession
  and shots.
- **Eq. (2), Figure 2.** Club FE for every club with 150+ matches. Barcelona's
  rank in this distribution is a permutation-style benchmark: it asks how
  unusual Barcelona's estimate is relative to the estimate for every other club.
  With one treated club, this is more informative than a cluster-robust
  *t*-test.
- **Eq. (3), Table 3.** Within-club triple difference among Champions League
  regulars (40+ matches): Barcelona × Domestic × period, with club × period
  FE, home-league × domestic × period FE, competition × season FE, and Elo
  ventile FE.
- **Eq. (4), Figure 3.** Season-by-season Barcelona and Real Madrid gaps in
  La Liga.
- **Eq. (5), Table 4.** Stoppage-time favoritism in close matches, in the
  spirit of Garicano, Palacios-Huerta and Prendergast (2005).

## Identification and threats

The parameter of interest is the gap in refereeing decisions for a given club
relative to a comparable club in the same situation. The identifying
assumption for eq. (1) is that, conditional on home status, opponent identity,
league-season, and pre-match expected strength, a club's *true* rate of
card-worthy, foul-worthy and penalty-worthy events does not differ from the
comparison clubs'. This assumption is strong. The main threats:

1. **Playing style (omitted variable).** Possession-dominant clubs commit fewer
   fouls mechanically: they have the ball, so their opponents commit more fouls
   against them. This biases the raw foul and card gaps toward "favorable" for
   Barcelona. Possession and shots partly absorb this (Panel B), but they are
   *bad controls* if referee decisions shape possession (for example, a red
   card shifts possession). The Champions League comparison (eq. 3) nets out
   club-level style that is common to both competitions.
2. **Strength / match state.** Strong clubs lead more often, and trailing
   teams foul more. Pre-match odds and Elo control for expected strength, not
   realized match state. A within-match analysis (cards by score state) is a
   natural extension; ESPN key events record card minutes from roughly
   2015/16.
3. **Competition differences.** UEFA referees, opponents and stakes differ from
   La Liga. Eq. (3) compares Barcelona's domestic-UCL gap with the same gap for
   other Spanish Champions League regulars, so league-wide refereeing
   differences are differenced out.
4. **Confounded timing of the 2018 break.** The end of the Negreira payments
   (2017/18) coincides with (i) the introduction of VAR in La Liga (2018/19),
   (ii) the decline of Barcelona's on-pitch dominance (Messi left in 2021), and
   (iii) Covid-19 ghost games (2019/20–2020/21). VAR affects all La Liga clubs
   and is absorbed by season FE only if its effect is homogeneous. VAR may
   matter more for possession-dominant clubs, for example through penalty
   reviews in the box. Real Madrid, the closest stylistic and financial
   comparison, is the natural control. The Champions League introduced VAR
   at almost the same time (2018/19 knockout stage), which helps in eq. (3).
5. **Measurement.** Fouls and cards come from ESPN box scores and
   football-data.co.uk. The two sources agree in 92–98% of matches, with
   correlations above 0.97. Penalties come from ESPN key events. League-seasons
   with implausibly low penalty rates (< 0.15 per match) are treated as
   incomplete and dropped. Referee identities are missing for most La Liga
   seasons after 2011/12, so referee FE are not used in the main
   specifications.

## Inference

Standard errors are clustered at the team-season level (eqs. 1, 3, 4). With
a single treated club, conventional inference is fragile. The cross-club
rank (eq. 2) provides a randomization-inference benchmark: the share of clubs
with an estimate at least as favorable as Barcelona's. Wild cluster bootstrap
(`fwildclusterboot`) is a robustness check worth adding for the Barcelona
coefficients.

## Extensions (not yet implemented)

- Referee FE and referee-specific Barcelona gaps for seasons with referee
  identities (La Liga 2001/02–2011/12; Premier League throughout). Transfermarkt
  or BDFutbol could fill La Liga referee names after 2011/12.
- Card timing by score state (minute-level ESPN key events, 2015/16+).
- VAR interventions by team (ESPN "VAR - ..." key events, 2018/19+).
- Ghost games (2019/20–2020/21) as a test of crowd pressure versus
  club-specific favoritism.

## October 2026 update

Current evidence is generated by programs 17–20 and verified by program 94.
Programs 06–16 remain opt-in exploratory analyses. The original manuscript
is preserved; the current audit is a separate `my_paper/analysis-update.pdf`
supplement. Known unresolved issues and proposed extensions are listed in
[next-step recommendations](next-steps.md).

### What is being estimated

The estimand is a difference in recorded decisions between clubs conditional
on observable match characteristics. It is not a difference in incorrect
calls. Identifying favoritism would require comparable incident opportunities
and independent assessments of whether both calls and no-calls were correct.
These sources do not contain that information.

Positive net outcomes are favorable to the target club: opponent minus own
cards or fouls, and own minus opponent penalties. Yellow cards received are
sign-reversed in comparison figures. Tables state whether units are per match
or per ten matches. Extra-time matches count once, not as 90-minute matches.

### Barcelona and playing style

Program 17 uses La Liga, with Barcelona, Real Madrid and Atletico Madrid
indicators. The omitted category is the non-elite La Liga clubs, not an
unconditional average over all clubs. Direct Barcelona-minus-Madrid contrasts
use the covariance of both coefficients.

Each outcome uses a fixed sample across specifications. Cards and fouls share
a sample with valid possession, shots, called fouls, odds and prior style for
both teams. Penalties additionally require independent event-log eligibility.
Both perspectives of a match must pass the main sample rules.

- L0: raw club indicators.
- L1: home, season, opponent and pre-match win-probability ventile fixed effects.
- L2: L1 plus splines in both teams' prior season-to-date possession and shots.
  At least three earlier valid matches are required. An assertion verifies
  that their dates precede the current match.
- L3: L1 plus flexible same-match possession and both teams' shots, instead of
  the lagged-style controls. This alternative avoids carrying poor lagged-style
  overlap into every model, but is descriptive because decisions affect style.
- L4: L3 plus splines in both teams' called fouls, for card outcomes.

L2 and L3 answer different conditional questions. Neither establishes that
unobserved tackle severity, pressing or tactical misconduct is comparable.
Called fouls are themselves decisions, so L4 is not a causal measure of
leniency and does not identify the probability of a card after a true foul.
Cards for dissent and time-wasting make a yellow/foul binomial inappropriate.

The overlap manifest compares target-club style distributions with non-elite
clubs and with Madrid. The same-match possession support check restricts rows
to the intersection of the groups' first-to-99th percentile ranges. It reports
how many Barcelona matches are lost. It does not make the full Barcelona
sample identifiable and does not balance every other characteristic.

For fouls, Poisson models compare no possession normalization, an offset that
imposes proportionality, and a freely estimated possession elasticity. Nominal
possession minutes are not actual time at risk, and off-ball fouls exist.
Rejecting elasticity one is a reason not to divide foul counts mechanically
by possession and interpret the resulting ranking as bias.

The 2018 split is descriptive. It coincides with VAR and changing squads and
performance. It is not a causal event study; no treatment-effect interpretation
or claim about payments is attached to it.

### Champions League precision

Program 18 estimates pooled Real Madrid gaps relative to non-elite clubs,
the other elite clubs excluding Barcelona, and Barcelona itself. Pooling
estimates an average over the observed seasons, not a claim about every year.
No domestic referee effect is transferred into the UEFA competition.

The same-sample ladder compares venue-adjusted raw gaps, pre-match adjustments
for season, stage, opponent and Elo expected-score bins, and same-match
possession bins plus both teams' shots. A separate outcome conditions net
yellows on both teams' called fouls. Complete-case raw and pre-match estimates
and a no-extra-time restriction are exported as sensitivity analyses.

Headline inference clusters entire seasons, containing both perspectives of
every match and all within-season dependence. Critical values use a Student
t distribution with the number of target/comparator seasons minus one.
Independence across seasons remains an assumption. Match-cluster,
team-season-cluster and heteroskedasticity-robust standard errors are exported
as alternatives, not substituted to obtain statistical significance.

Minimum detectable effects solve the noncentral-t power equation at
80 percent power and 5 percent two-sided size using the estimated clustered
standard error. They are design approximations, not observed power or a
promise about a future sample. Equivalence uses TOST at explicit illustrative
bounds and a 90 percent interval. A large p-value against zero does not imply
equivalence to an economically small effect.

The seasonal display retains raw season estimates alongside empirical-Bayes
partial pooling. The correlated normal model retains the full covariance
matrix of the jointly estimated season coefficients. Heterogeneity is fitted
by REML, with a Q-profile interval and sensitivity at its upper endpoint.
The displayed shrinkage intervals condition on estimated heterogeneity and
can be too narrow, particularly near zero heterogeneity. They are not the
headline evidence. Leave-one-season-out refits and cumulative precision
curves expose dependence on particular seasons. Title seasons are not selected
as a comparison group.

### Card timing

Program 19 compares first-30-minute and full-match net yellows on the same
reconciled event-log sample. Both teams' yellow totals must match the box
scores, goal totals must reconcile, and a regulation-end marker must exist.
Extra time is excluded. Controls use pre-match strength and the preceding
five matches' style for each team, within competition and season.

The two windows have different exposure and are not rate-normalized to look
comparable. First-30-minute cards can still respond to score state. The
selected timeline sample need not represent all matches.

### Multiplicity and interpretation

The generated headline table applies Holm correction jointly to six
Barcelona L3 endpoints versus Madrid and five pooled Madrid style endpoints
versus the other elite clubs. Pointwise intervals remain explicitly labeled.
Other specifications and era splits are sensitivity analyses, not independent
discoveries. Outcomes are retained regardless of sign or significance.

Cross-club ranks are descriptive, not permutation p-values: club labels are
not exchangeable. The final-whistle clock is not the announced minimum added
time, and the old stoppage models omit major sources of time lost. Their
associations are not evidence of incorrect added-time decisions.

### Data audit and verification

The cleaner masks impossible possession pairs and excludes abandoned fixtures.
Penalty eligibility uses an end marker and goal reconciliation rather than
selecting seasons with high recorded penalty rates. Extra-time goals enter
final-score reconciliation but do not enter the reconstructed regulation
score. None of these checks proves penalty-log completeness or correct calls.

Program 94 checks unique team-match keys, reciprocal net outcomes, valid
possession pairs, completed fixtures, goal reconciliation, constant samples
across specification ladders, interval ordering, MDE calibration and unit
conversion. The runner writes logs and package versions; numerical reports
are generated from the same CSV manifests as the figures.
