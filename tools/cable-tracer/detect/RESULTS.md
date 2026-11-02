# Results: loop proposal vs hand trace

## With the mast net (2026-11-02, night)

Same input as below, plus the mast net (`--masts`, each park scored by the fold model that never
saw it). Mast detections enter the fit as vertex evidence (weight 3 x probability), both as hull
points and as pure vertex support; the best score of the pooled candidates wins.

- 24 of 25 parks get a proposal; median IoU 0.77 (was 0.71); IoU >= 0.7 for 15 parks (was 13); median mean bend error 30 m (was 36 m); 9 proposals flagged weak (score < 9).
- Mast net alone: 93 of the 126 traced bends get a peak with p >= 0.5 within 20 m; 224 false peaks over the 25 parks (mostly obstacles, boats and shore clutter), which is why masts also shape the hull only as one of two strategies.
- Big wins: Stroombroek 0.85 -> 0.94, Aquabest 0.69 -> 0.88, Breakout 0.54 -> 0.77 (the 150-degree knee is gone), Burnside 0.84 -> 0.92, Beavercreek 0.22 -> 0.56, Wet'n'Wild 0.71 -> 0.83.
- Losses: Kempervennen 0.70 -> 0.49 and Antwerp 0.37 -> 0.12, both flagged weak (8.2 and 4.3). Zwolle now gets a proposal from six false peaks in the glint; its score of -15.8 flags it.
- Still open: Ermerstrand (no masts found in brown water), Project 7 (masts missing from the imagery), Knokke (two loops), Betuwestrand (glint, nothing found).
- First mast net (trained on bends vs water/objects/shore only) found 82% of the bends but fired on 382 non-bend spots; mining those as negatives (`mastmine.py`) and retraining gave the net used here (AUC 0.91 leave-parks-out).

### With the park's other cables given (`--given-others`)

The app hands the detector the cables already traced in the park (the ones on the 600 m image).
Evidence within 25 m of such a cable, and every object inside a traced loop, belongs to that cable;
a proposal that crosses or touches one (20 m) loses 10 points per conflict and is noted.
Parks with two loops get one row per loop, the other loop given.

- 26 targets: median IoU 0.77, IoU >= 0.7 for 16, 8 weak. Knokke's big loop 0.48 -> 0.61 (score 5 -> 12), Veendam 0.53 -> 0.71 with its 2.0 given.
- Knokke's small loop stays at 0.27, flagged weak (score -1): the hull start still spans a few masts in the other basin and the refinement cannot shrink to it. Starts from the mast detections alone did not help (they broke Down Under), so that is left for the reviewer.
- 2.0 cables are not detected (decision 2026-11-02): the mast net finds the water-side 2.0 mast in 6 of 8 parks but the shore-side one almost never.

| park | floating objects | mast peaks | bends found | IoU | before | mean bend error (m) | perimeter (m) | vertices | score | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| stroombroek-braamt | 10 | 7 | 5/5 | 0.94 | 0.85 | 6.2 | 1039 | 5 | 9.6 |  |
| beavercreek-roermond | 52 | 23 | 5/5 | 0.56 | 0.22 | 34.9 | 775 | 5 | 2.7 |  |
| betuwestrand-beesd | 0 | 0 | 0/5 | - | - | - | - | - | - |  |
| breakout-harkstede | 10 | 13 | 3/4 | 0.77 | 0.54 | 27.4 | 854 | 5 | 11.7 |  |
| burnside-emst | 41 | 28 | 5/5 | 0.92 | 0.84 | 10.4 | 988 | 5 | 9.1 |  |
| downunder-nieuwegein | 21 | 5 | 1/5 | 0.86 | 0.8 | 12.3 | 715 | 5 | 11.7 |  |
| aquabest-best | 18 | 7 | 3/4 | 0.88 | 0.69 | 6.9 | 842 | 5 | 12.7 | edges over land: 3% |
| view-almere | 31 | 6 | 2/5 | 0.82 | 0.83 | 27.0 | 812 | 5 | 12.9 |  |
| deberendonck-wijchen | 25 | 9 | 4/5 | 0.89 | 0.83 | 6.4 | 821 | 5 | 13.4 |  |
| ermerstrand-erm | 11 | 0 | 0/4 | 0.33 | 0.33 | 87.5 | 543 | 6 | 9.2 |  |
| goodlife-hoogstraten | 26 | 13 | 5/5 | 0.88 | 0.8 | 20.6 | 668 | 5 | 13.6 |  |
| lakeside-paradise-knokke | 43 | 19 | 10/10 | 0.48 | 0.34 | 68.5 | 786 | 5 | 5.1 |  |
| lakeside-zwolle | 0 | 6 | 0/5 | 0.0 | - | 177.0 | 459 | 4 | -15.8 | corner of 151 degrees |
| lunalake-heerhugowaard | 34 | 7 | 4/5 | 0.88 | 0.88 | 11.1 | 720 | 5 | 13.4 |  |
| project7-rotterdam | 21 | 15 | 1/5 | 0.52 | 0.48 | 57.5 | 545 | 6 | 8.7 |  |
| schotsman-kamperland | 12 | 31 | 4/4 | 0.7 | 0.64 | 32.9 | 923 | 5 | 4.7 |  |
| seven-twenty-sevenum | 15 | 9 | 5/5 | 0.96 | 0.96 | 4.2 | 790 | 5 | 13.4 |  |
| wakeup-antwerp | 16 | 14 | 5/6 | 0.12 | 0.37 | 71.9 | 867 | 5 | 4.3 |  |
| waterskitwente-enschede | 21 | 17 | 2/4 | 0.66 | 0.61 | 42.7 | 657 | 5 | 9.7 |  |
| waterskibaan-sneek | 25 | 24 | 5/5 | 0.77 | 0.71 | 35.9 | 914 | 5 | 6.8 |  |
| kempervennen-westerhoven | 10 | 14 | 4/5 | 0.49 | 0.7 | 68.3 | 555 | 4 | 8.2 |  |
| watersportcentre-veendam | 21 | 14 | 5/5 | 0.53 | 0.53 | 38.2 | 744 | 6 | 7.5 |  |
| wetnwild-alphen | 22 | 12 | 5/5 | 0.83 | 0.71 | 13.8 | 794 | 6 | 12.9 |  |
| wollebrand-honselersdijk | 19 | 11 | 5/5 | 0.76 | 0.75 | 18.5 | 668 | 5 | 13.0 |  |
| zeumeren-voorthuizen | 31 | 22 | 5/5 | 0.8 | 0.81 | 36.7 | 831 | 5 | 9.7 |  |

## Floating objects only (2026-11-02, evening)

Input: the 600 m / 0.29 m px close-up per park from the training-set export; the only park-specific input is the park location. Ground truth: the loop traced by hand in the park YAML.

- 23 of 25 parks get a proposal; median IoU 0.71; median mean bend error 36 m; IoU >= 0.7 for 13 parks.
- Corner rule (added after the Project 7 review): a cable turns at most ~95 degrees around one mast. On the 126 hand-traced bends the turn is 36-94 degrees, on the GPS-fitted masts 36-91. Sharper knees are penalised in the fit, the knee vertex is dropped and refitted, and `CableLint` reports them (warning > 95, error > 120).
- Project 7: the right-hand masts are not on the imagery (older photo), so the fit now shrinks to a plausible loop of 527 m instead of inventing a 150-degree knee. The GPS-fitted masts (`towers_apex.csv`) are 3-22 m from the hand trace, so the trace itself is fine; the imagery is the problem. This is the case the reviewer has to finish by hand.
- Plausibility score: proposals under 9 are the ones to distrust (floating objects only) (Beavercreek 3.7, Breakout -3.2 with an unresolved knee, Schotsman 4.4, Antwerp -8.3, Knokke 6.5, Kempervennen 6.0, Veendam 8.3, Twente 8.5). Stroombroek (8.5, IoU 0.85) and Sneek (9.0, 0.71) are the borderline exceptions.
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

1. Mast cue: done, see the top section. Next for it: more parks in the training set, and the two-loop case.
2. Faint-line evidence: the cable itself is a 1 px line in the close-up; a ridge filter along candidate edges would pin edges that have no obstacles, and would give the template strategy its evidence term.
3. Glint: median-filter the image before segmentation, or fall back to the overview snapshot for the water mask.
4. Several loops per lake (Knokke, Terhills): run the fit again with the first loop's objects removed.
5. 2.0 cables: a straight 100-250 m line of 2 masts next to the loop; not attempted yet.
6. Ported to `RpplCore/CableDetection` (the app's "Detect cable" button, behind a Debug toggle); the score is the plausibility flag there too. The tracer tool could call the same code behind `Add full size`.
