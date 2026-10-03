# Findings memo: Barcelona and refereeing, 2001/02–2025/26

*2026-10-02. All numbers from `output/tables/*.csv`. Preliminary; not peer-reviewed.*

## Data

- 48,478 matches (96,956 team-matches), 313 clubs: Premier League, La Liga,
  Serie A, Bundesliga, Ligue 1 (2001/02–2025/26) and the Champions League
  (group/league phase and knockouts).
- Barcelona: 950 La Liga and 263 Champions League matches.
- Cards and fouls from 2005/06; penalties from 2001/02 where event logs are
  complete; pre-match odds for every domestic match.

## Headline results

**1. Raw gaps are large and mostly reflect style.** In La Liga, Barcelona
receives 1.86 yellow cards per match vs. 2.53 for other clubs, commits 11.6
fouls vs. 14.8, and is awarded 0.19 penalties vs. 0.15. It also averages 66.8%
possession and a 65% pre-match win probability. Its Champions League numbers,
under non-Spanish referees, are almost identical (1.71 cards, 15.3 fouls
suffered, 0.20 penalties). The raw advantage travels with the club.

**2. Conditional gaps (Table 2, domestic leagues).** Estimates control for
opponent, home status, league-season and pre-match odds; Panel B adds
possession bins and shots.

| Barcelona vs. average club | Pre-match controls | + possession bins, shots |
|---|---|---|
| Yellow cards received | −0.23 (0.06) | −0.17 (0.06) |
| Yellow cards to opponent | 0.03 (0.08) | 0.09 (0.06) |
| Fouls called against | −1.73 (0.21) | −1.28 (0.21) |
| Fouls called for | 0.88 (0.24) | 0.94 (0.25) |
| Penalties awarded | −0.02 (0.02) | 0.00 (0.02) |
| Penalties conceded | −0.01 (0.01) | −0.02 (0.02) |
| Yellow received, given fouls committed | −0.06 (0.05) | −0.04 (0.05) |
| Opponent yellow, given opponent fouls | −0.06 (0.07) | −0.01 (0.06) |

Conditional on fouls called, referees are **not** more lenient with Barcelona's
players or harsher with its opponents. The card gap comes from fewer fouls
called against Barcelona. Real Madrid's fouls-for gap (0.93) is the same as
Barcelona's.

**3. Fouls per possession (Table 5).** Your suggestion. Treating possession as
exposure flips the sign: Barcelona suffers 0.17 *fewer* fouls per 10 minutes of
own possession and commits 0.25 *more* per 10 minutes of opponent possession.
But fouls are far from proportional to possession: the estimated elasticity is
0.17. Using that elasticity, Barcelona suffers about 5% more fouls and commits
about 9% fewer than predicted. Per 100 passes there is no difference. The
residual foul advantage is small and its sign depends on the normalization.

**4. Barcelona in the cross-club distribution (Figure 2, 144 clubs with 150+
matches).**

| Measure | Barcelona's rank |
|---|---|
| Net yellow cards | 11th (13th with style controls), top ~8% |
| Net fouls | 2nd (4th) |
| Net red cards | 56th (125th) |
| Net penalties | 93rd of 150 (31st of 139) |

The clubs that rank near Barcelona on cards and fouls are possession or
technical sides, mostly small: Swansea, Real Sociedad, Las Palmas, Girona,
Celta, Lorient, Guingamp, Sassuolo. That pattern is style, not favoritism. On
penalties, Barcelona is unremarkable.

**5. Spanish vs. UEFA referees (Table 3, 30 Champions League regulars).**
Before 2018/19, Barcelona received 0.38–0.50 fewer yellow cards in La Liga
than its Champions League baseline implies, relative to other Spanish
regulars. That gap closes after 2017/18 (change +0.43 (0.26) / +0.61 (0.27)).
But its *opponents* also got fewer cards in La Liga in that period (−0.20 /
−0.29), so this looks like lenient refereeing of Barcelona's matches rather
than one-sided favoritism. Penalties show no domestic premium in either
period.

**6. Timing (Figure 3, La Liga).** Barcelona's net yellow-card advantage
falls by 0.68 per match after 2017/18; Real Madrid's falls by 0.11. The
difference-in-differences is −0.57 (0.18). However:

- the drop is concentrated in 2019/20–2023/24 (the crisis years) and reverses
  in 2024/25–2025/26;
- net fouls do not break in 2018; they collapse in 2021/22, the first season
  without Messi;
- penalties show no break;
- VAR (2018/19) cannot review yellow cards, so it does not directly explain
  the card change.

**7. Stoppage time (Table 4).** This is the clearest favoritism signal.
Referees add 0.71 (0.24) more minutes when Barcelona trails by one than when
it leads by one, about 3.5× the generic home-team effect (0.20). But Real
Madrid gets exactly the same (0.70). Within La Liga, the effect is small
before 2018 (0.20, n.s.) and larger after (1.06). That pattern fits
status-based social pressure on referees toward big clubs, not a
Barcelona-specific arrangement tied to the Negreira period.

## Real Madrid in the Champions League (Tables 6–8, Figure 8)

- **Raw (285 matches, 7 titles):** per match, Real Madrid receives 1.85 yellow
  cards and its opponents 1.96. It is awarded 0.17 penalties and concedes 0.13.
  That is in line with the other elite clubs (1.76 / 1.89 yellows; 0.19 / 0.13
  penalties) and below Barcelona's 0.20 penalties awarded.
- **Conditional (vs. non-elite teams; same season, stage, opponent, Elo and
  possession):**
  - Real Madrid gets 0.14 *more* yellow cards (significantly more than the
    other elite clubs, p = 0.005).
  - Its opponents get 0.10 fewer; neither difference is significant.
  - It has 0.88 fewer fouls called against it, but no more called on its
    opponents.
  - Penalties show no difference (−0.02 awarded, −0.02 conceded).
- **Knockouts:** no favorable gap. Real Madrid gets 0.21 more yellow cards, and
  its penalty gaps are small and negative.
- **Eras:**
  - In 2013/14–2017/18 (four titles), fouls called against Real Madrid were
    2.5 per match lower, but there was no card or penalty advantage.
  - Since 2018/19, its opponents receive 0.36 *fewer* yellow cards, which
    works against Real Madrid.
- **Title seasons:** the net yellow-card gap is never significant (−0.35 to
  0.57). Net fouls were significantly favorable in 2016/17 and 2021/22.
  Penalties went one way in 2016/17 (−0.41) and the other in 2017/18 (+0.28).
- **Stoppage time:** referees add +0.55 minutes when Real Madrid trails vs.
  leads (n.s.). That is +1.47 in the group/league phase and **−0.86 in
  knockouts** (20 leads, 14 trails). Barcelona gets +0.94 and the other elite
  clubs +0.29. The data show no "extra time for Madrid comebacks" effect where
  it would matter.

Data fixes made for this analysis:

- Pre-group play-offs and the 2001/02–2002/03 second group stage were being
  coded as knockouts.
- Finals and the 2020 Lisbon matches are now coded as neutral venues.
- The 2002/03 semi-finals, mislabeled by ESPN as quarter-finals, are corrected.
- Winner and shoot-out flags were added.

## Bottom line

Measured against every other club in Europe's top leagues, Barcelona gets
favorable *raw* numbers, but those mostly reflect how it plays. On the
decisions that matter most (penalties, cards per foul), it is not an outlier.
There is a statistically significant decline in its La Liga card advantage
after 2017/18 relative to Real Madrid. Its timing and its two-sidedness make
it weak evidence that the payments bought on-pitch favoritism. The data
cannot rule out favoritism concentrated in a few high-stakes decisions or in
referee assignments.

## Threats and next steps

1. Referee identities for La Liga after 2011/12 (Transfermarkt/BDFutbol):
   referee fixed effects, and Negreira-era referees vs. others.
2. Card timing by score state (ESPN key events, 2015/16+).
3. VAR interventions by team (ESPN "VAR - ..." events, 2018/19+).
4. Pressing intensity: tactical fouls by high-pressing sides are not captured
   by possession bins (relevant under Guardiola, Xavi and Flick).
5. Verify the reported payment amounts and dates for the introduction
   (marked XX in `my_paper/fragments/introduction.tex`).
