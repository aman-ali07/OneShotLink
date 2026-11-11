# Reference screenshots

No screenshots are stored yet. This environment has no browser-capture tool, and recon
was done from public pages (homepage, pricing, about/FAQ, docs) with `curl` at human
speed, not from the original's JavaScript bundles.

To add them:

1. With the user present, open the original in their own browser and capture S01–S06
   (and any state that matters: passphrase prompt, gone state, mobile width).
2. Save as `replica/screens/S01.png`, `S02.png`, ... (PNG, one screen per file).
3. Never ship these files, never use them as assets, and never copy their visual
   identity. They are layout references for parity only.
4. Re-run `/replica-diff` with `imgdiff.py` once corresponding clone screenshots exist.

`*.png` in this folder is git-ignored by the repository to reduce the chance of shipping
reference material.
