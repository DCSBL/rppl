# Results: loop proposal vs hand trace (2026-11-02)

Input: the 600 m / 0.29 m px close-up per park from the training-set export; the only park-specific input is the park location. Ground truth: the loop traced by hand in the park YAML.

- 23 of 25 parks get a proposal; median IoU 0.71; median mean bend error 32 m; IoU >= 0.7 for 12 parks.
- Proposals with a plausibility score under 9 are the bad ones (Schotsman 3.6, Wakeup Antwerp 5.9, Beavercreek 6.4, Knokke 8.7), so the score is usable as the reviewer's "check this" flag; Stroombroek (8.6, IoU 0.85) is the exception.
- No proposal: Betuwestrand and Lakeside Zwolle (sun glint turns the water into speckle; no floating object survives). Ermerstrand (brown water, few obstacles) and Knokke (two loops in one lake) are wrong.

| park | floating objects | IoU | mean bend error (m) | max (m) | perimeter (m) | vertices | score |
|---|---|---|---|---|---|---|---|
| stroombroek-braamt | 10 | 0.85 | 32.1 | 70.4 | 979 | 6 | 8.6 |
| beavercreek-roermond | 52 | 0.18 | 81.7 | 118.7 | 773 | 4 | 6.4 |
| betuwestrand-beesd | 0 | - | - | - | - | - | - |
| breakout-harkstede | 10 | 0.54 | 56.2 | 122.1 | 739 | 5 | 12.6 |
| burnside-emst | 41 | 0.84 | 22.9 | 73.7 | 893 | 5 | 11.0 |
| downunder-nieuwegein | 21 | 0.8 | 17.4 | 50.7 | 691 | 5 | 11.5 |
| aquabest-best | 18 | 0.76 | 35.1 | 90.6 | 756 | 5 | 13.6 |
| view-almere | 31 | 0.84 | 19.1 | 52.3 | 908 | 5 | 12.5 |
| deberendonck-wijchen | 25 | 0.83 | 14.3 | 31.4 | 820 | 5 | 13.4 |
| ermerstrand-erm | 11 | 0.34 | 97.9 | 131.1 | 692 | 5 | 11.5 |
| goodlife-hoogstraten | 26 | 0.8 | 25.1 | 50.7 | 674 | 5 | 13.8 |
| lakeside-paradise-knokke | 43 | 0.4 | 82.4 | 122.4 | 761 | 5 | 8.7 |
| lakeside-zwolle | 0 | - | - | - | - | - | - |
| lunalake-heerhugowaard | 34 | 0.86 | 20.5 | 55.4 | 695 | 6 | 14.3 |
| project7-rotterdam | 21 | 0.55 | 43.6 | 118.0 | 646 | 5 | 12.5 |
| schotsman-kamperland | 12 | 0.66 | 35.9 | 72.0 | 1010 | 5 | 3.6 |
| seven-twenty-sevenum | 15 | 0.96 | 3.7 | 6.1 | 790 | 5 | 11.9 |
| wakeup-antwerp | 16 | 0.42 | 28.4 | 47.0 | 621 | 5 | 5.9 |
| waterskitwente-enschede | 21 | 0.69 | 32.2 | 74.6 | 709 | 5 | 13.8 |
| waterskibaan-sneek | 25 | 0.71 | 36.5 | 95.9 | 927 | 5 | 11.0 |
| kempervennen-westerhoven | 10 | 0.61 | 52.7 | 91.2 | 695 | 5 | 10.7 |
| watersportcentre-veendam | 21 | 0.55 | 58.1 | 99.4 | 724 | 5 | 11.4 |
| wetnwild-alphen | 22 | 0.78 | 26.4 | 50.7 | 785 | 5 | 14.0 |
| wollebrand-honselersdijk | 19 | 0.69 | 29.6 | 56.0 | 718 | 5 | 13.2 |
| zeumeren-voorthuizen | 31 | 0.9 | 21.0 | 69.3 | 822 | 5 | 12.0 |

## What to do next

1. Mast cue: a mast is a dark pole with a bright platform and a thin shadow line; a dedicated detector at the vertices would fix the sparse parks (Stroombroek, Ermerstrand, Beavercreek).
2. Faint-line evidence: the cable itself is a 1 px line in the close-up; a ridge filter along candidate edges would pin edges that have no obstacles.
3. Glint: median-filter the image before segmentation, or fall back to the overview snapshot for the water mask.
4. Several loops per lake (Knokke, Terhills): run the fit again with the first loop's objects removed.
5. 2.0 cables: a straight 100-250 m line of 2 masts next to the loop; not attempted yet.
6. Port the winner into `CableTracerCore` as a proposal step behind the `Add full size` button, keeping the score as the plausibility flag.
