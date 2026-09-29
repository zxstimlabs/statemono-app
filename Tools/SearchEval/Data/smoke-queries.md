# Smoke queries

Written by Claude on 2026-09-29 to check that SearchEval works end to end. They're not the test set: the owner's queries in docs/search-test-links.md are. Run with `swift run SearchEval eval --queries Data/smoke-queries.md`.

## Queries

| Query | Should find | Kind |
|---|---|---|
| espresso | 17 | exact |
| remote desktop | 63 | exact |
| cookie recipe | 75 | exact |
| photosynth | 21 | start |
| youtub | 37, 38, 39, 40, 41, 42 | start |
| levenshtien | 16 | typo |
| sqlte | 13, 43, 50, 55 | typo |
| telescop spase | 32 | typo |
| coffee drink | 17 | meaning |
| scary tv show with kids | 67 | meaning |
| where to stay on vacation | 79 | meaning |
| first tweet | 33 | meaning |
| note taking app | 86, 87 | meaning |
| learning a language | 81 | meaning |
| apple laptop | 2, 3 | several |
| japan travel | 28, 78 | several |
