# Research design notes

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
