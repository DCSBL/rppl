# Results: loop proposal vs hand trace (2026-11-02, evening)

Input: the 600 m / 0.29 m px close-up per park from the training-set export; the only park-specific input is the park location. Ground truth: the loop traced by hand in the park YAML.

- 23 of 25 parks get a proposal; median IoU 0.71; median mean bend error 36 m; IoU >= 0.7 for 13 parks.
- Corner rule (added after the Project 7 review): a cable turns at most ~95 degrees around one mast. On the 126 hand-traced bends the turn is 36-94 degrees, on the GPS-fitted masts 36-91. Sharper knees are penalised in the fit, the knee vertex is dropped and refitted, and `CableLint` reports them (warning > 95, error > 120).
- Project 7: the right-hand masts are not on the imagery (older photo), so the fit now shrinks to a plausible loop of 527 m instead of inventing a 150-degree knee. The GPS-fitted masts (`towers_apex.csv`) are 3-22 m from the hand trace, so the trace itself is fine; the imagery is the problem. This is the case the reviewer has to finish by hand.
- Plausibility score: proposals under 9 are the ones to distrust (Beavercreek 3.7, Breakout -3.2 with an unresolved knee, Schotsman 4.4, Antwerp -8.3, Knokke 6.5, Kempervennen 6.0, Veendam 8.3, Twente 8.5). Stroombroek (8.5, IoU 0.85) and Sneek (9.0, 0.71) are the borderline exceptions.
- No proposal: Betuwestrand and Lakeside Zwolle (sun glint turns the water into speckle; no floating object survives).
- Tried and parked: a water-shaped template (rectangle of the typical size fitted inside the lake) for parks with few objects. It fixed Breakout and Ermerstrand but moved four good parks onto the wrong part of the lake; it stays behind `use_templates=False` until it has an evidence term of its own.

| park | floating objects | IoU | mean bend error (m) | max (m) | perimeter (m) | vertices | score | notes |
|---|---|---|---|---|---|---|---|---|
| stroombroek-braamt | 10 | 0.85 | 32.2 | 70.4 | 980 | 6 | 8.5 |  |
| beavercreek-roermond | 52 | 0.22 | 63.3 | 121.0 | 839 | 4 | 3.7 | edges over land: 3% |
| betuwestrand-beesd | 0 | - | - | - | - | - | - |  |
| breakout-harkstede | 10 | 0.54 | 56.2 | 122.1 | 738 | 5 | -3.2 | corner of 150 degrees |
| burnside-emst | 41 | 0.84 | 22.9 | 73.7 | 893 | 5 | 11.0 |  |
| downunder-nieuwegein | 21 | 0.8 | 18.9 | 56.7 | 689 | 5 | 11.3 |  |
| aquabest-best | 18 | 0.69 | 31.9 | 42.2 | 699 | 5 | 10.2 |  |
| view-almere | 31 | 0.83 | 19.1 | 52.3 | 909 | 6 | 12.0 |  |
| deberendonck-wijchen | 25 | 0.83 | 14.3 | 31.4 | 820 | 5 | 13.4 |  |
| ermerstrand-erm | 11 | 0.33 | 87.5 | 131.1 | 543 | 6 | 9.2 |  |
| goodlife-hoogstraten | 26 | 0.8 | 25.1 | 50.7 | 674 | 5 | 13.8 |  |
| lakeside-paradise-knokke | 43 | 0.34 | 81.1 | 110.8 | 813 | 6 | 6.5 |  |
| lakeside-zwolle | 0 | - | - | - | - | - | - |  |
| lunalake-heerhugowaard | 34 | 0.88 | 20.4 | 55.4 | 697 | 6 | 13.6 |  |
| project7-rotterdam | 21 | 0.48 | 74.7 | 150.4 | 527 | 5 | 10.4 |  |
| schotsman-kamperland | 12 | 0.64 | 41.8 | 77.8 | 836 | 5 | 4.4 | edges over land: 3% |
| seven-twenty-sevenum | 15 | 0.96 | 3.7 | 6.1 | 790 | 5 | 11.9 |  |
| wakeup-antwerp | 16 | 0.37 | 47.2 | 63.5 | 616 | 5 | -8.3 | corner of 164 degrees |
| waterskitwente-enschede | 21 | 0.61 | 48.1 | 82.4 | 709 | 5 | 8.5 |  |
| waterskibaan-sneek | 25 | 0.71 | 50.6 | 90.2 | 950 | 5 | 9.0 |  |
| kempervennen-westerhoven | 10 | 0.7 | 36.0 | 83.1 | 700 | 5 | 6.0 |  |
| watersportcentre-veendam | 21 | 0.53 | 54.4 | 94.6 | 766 | 5 | 8.3 |  |
| wetnwild-alphen | 22 | 0.71 | 36.2 | 55.8 | 711 | 5 | 12.9 |  |
| wollebrand-honselersdijk | 19 | 0.75 | 22.7 | 45.8 | 669 | 5 | 13.2 |  |
| zeumeren-voorthuizen | 31 | 0.81 | 30.9 | 69.3 | 825 | 6 | 11.6 |  |

## What to do next

1. Mast cue: a mast is a dark pole with a bright platform and a thin shadow line; a dedicated detector at the vertices would fix the sparse parks (Stroombroek, Ermerstrand, Beavercreek, Breakout).
2. Faint-line evidence: the cable itself is a 1 px line in the close-up; a ridge filter along candidate edges would pin edges that have no obstacles, and would give the template strategy its evidence term.
3. Glint: median-filter the image before segmentation, or fall back to the overview snapshot for the water mask.
4. Several loops per lake (Knokke, Terhills): run the fit again with the first loop's objects removed.
5. 2.0 cables: a straight 100-250 m line of 2 masts next to the loop; not attempted yet.
6. Port the winner into `CableTracerCore` as a proposal step behind the `Add full size` button, keeping the score as the plausibility flag.
