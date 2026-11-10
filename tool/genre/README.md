# Local genre-model experiments

These tools train and measure the **genre LSTM**, independently of the frozen
B9 symbol detector. They never install packages, change the source data project,
copy a candidate into the app, or change the three displayed genre labels.

The mobile contract is fixed: 22 features, 64-event windows, stride 32, a
320-event cap **before key estimation**, at least 16 sounding notes, four output
probabilities. Evaluation includes the app's existing .7 confidence and .4
Kundiman fallback gates. Metrics count source excerpts, not overlapping windows.

## Runtime and inputs

Use Python 3.12 with NumPy, PyTorch, music21 and ai-edge-litert. Export additionally
needs litert-torch. The local data project's installed packages work with
`/usr/bin/python3.12`; its `venv/bin/python3` currently points at an incompatible
system Python. No Colab or CUDA is needed. The experiment used Torch 2.13.0+cu130
on CPU, LiteRT 2.2.0 and litert-torch 0.9.4, with two compute threads.

Required existing data-project inputs:

- `out/genre/{pieces,more,pdmx,extra}.json`
- `scripts/{genre_train,genre_prep,kundiman_gen}.py`
- `out/genre_cv_{all,0,1,2,3}/genre_lstm.pt`

Example, from the app repository (adjust the paths):

```bash
export GENRE_DATA=/home/ken/Workspace/note-vision-data
export GENRE_RUN="$PWD/.dart_tool/genre_runs/new-experiment"
export PYTHONPATH="$GENRE_DATA/venv/lib/python3.12/site-packages"
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2 MKL_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2
mkdir -p .dart_tool/genre_tmp
export TMPDIR="$PWD/.dart_tool/genre_tmp"

/usr/bin/python3.12 -B tool/genre/prepare.py "$GENRE_DATA" "$GENRE_RUN"
/usr/bin/python3.12 -B tool/genre/train.py "$GENRE_DATA" "$GENRE_RUN" --fold all
/usr/bin/python3.12 -B tool/genre/calibrate.py "$GENRE_DATA" "$GENRE_RUN" --fold all
```

Repeat the last two commands for folds `0`, `1`, `2`, `3`. Each fold starts from
its corresponding original checkpoint, which excluded that fold's Kundiman
works. Never start a held-out evaluation from the all-data checkpoint. All
passages of a composition must use the same `work_id` and partition.

The schedule is fixed at 200 steps per member, four original seeds, batch 64,
Adam 1e-4. Kundiman draws are 70% real and 30% synthetic, rather than the old
30%/70%. Half the Waltz draws use minor-key hard negatives. Keys are recomputed
from realistic short/capped contexts, with duration scaling applied to all
genres. A distillation loss retains the old member's distinctions on negatives.
Calibration uses **validation only**: choose the largest fixed-grid Kundiman
scale preserving validation Kundiman recognition, false-Kundiman counts and
combined Waltz/Jazz display accuracy at every prefix. It acts before averaging
window probabilities. No admissible scale means rejection.

`prepare.py` freezes original splits before filtering, records input hashes,
and quarantines compositions carrying contradictory labels. The supplied PDMX
data contains **13 IDs tagged both Jazz and Waltz** (9 train, 2 valid, 2 test),
so 26 rows are excluded. Original files remain unchanged. It also rejects
cross-partition source IDs. This does not establish that all compositions
across the older source collections are independent: title/composer-level
deduplication remains an audit limitation.

## Real Kundiman additions

The original corpus had 18 real works: 14 training, 4 validation. The first
trial added two excerpts. The November 10 collection adds **three more works**,
for **17 training / 4 validation / 2 fresh test works**. These are composition
excerpts, not full songs or thousands of independent examples. Synthetic and
augmented windows never count as additional works. `data/manifest.json` records
sources, PDF hashes, notation pages, genre evidence, partitions and excerpt sizes.

| File | Source and attribution | Partition |
| --- | --- | --- |
| `data/sa_silong_ng_langit.abc` | Nicanor Abelardo, *Sa Silong ng Langit*, vocal bars 5–19 (15 bars, 55 events). Paul Earvin Bibal's 2021 engraving, IMSLP671053, explicitly titled Kundiman; [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). [Source](https://imslp.org/wiki/Dakilang_Punglo_(Abelardo,_Nicanor)). Melody transcribed; lyrics/accompaniment omitted. | New training work |
| `data/kundiman_1800.abc` | Anonymous traditional *Kundiman*, first 14 bars (47 sounding events), printed page 28/PDF page 33 in Rodolfo R. Cornejo's 1933 thesis *The Philippines, her native instruments and music*. The source dates the composition to 1800. [Archived primary source](https://collections.carli.illinois.edu/digital/api/collection/rou_cmct/id/49/download). Melody transcribed; no lyrics/accompaniment. | Fresh test work; never sampled |
| `data/kung_hindi_man.abc` | Abelardo, *Kung Hindi Man*, vocal bars 5–20 (16 bars, 56 events). Joseph David S. Legaspi, *Filipino Diction for Singers* (Indiana University, 2014), printed 70/PDF 79; Kundiman attribution on printed 66. [University source](https://scholarworks.iu.edu/dspace/bitstreams/313039f0-edd6-40db-8c84-8c19e6c0ca44/download). | New training work |
| `data/jocelynang_baliwag.abc` | Anonymous traditional melody (ca. 1896), first 12 vocal bars (45 events). Isidora Kabigting Miranda, *Dissonant Voices* (Wisconsin-Madison, 2020), Example 2 lower staff, printed 58/PDF 70. [University source](https://asset.library.wisc.edu/1711.dl/NPUGSNNBQOLWU84/R/file-1109e.pdf). | New training work; related 1902 Cundiman must share its partition if later admitted |
| `data/bituing_marikit.abc` | Abelardo, *Bituing Marikit*, vocal bars 9–24 (16 bars, 53 events). Legaspi (2014), printed 87–88/PDF 96–97, with explicit Kundiman attribution on printed 66. [University source](https://scholarworks.iu.edu/dspace/bitstreams/313039f0-edd6-40db-8c84-8c19e6c0ca44/download). Retains the printed C minor, **2/4** and exact triplets. | Fresh test work; never sampled |

The modern theses are copyrighted, **not CC licensed**; only the underlying
historical melody excerpts were transcribed. No thesis prose, lyrics, IPA,
translations, accompaniment or PDF pages are redistributed. Engraving-specific
rights are not represented as a blanket license for the theses.

Transcriptions were visually checked and every bar must match its own meter.
Explicit naturals are repeated in the ABC where the installed parser otherwise
reverts a repeated note to its key-signature pitch. Source-based pitch, tie and
triplet tests cover those notes. A second independent pitch-by-pitch review is
still desirable. The 2/4 repertoire example is deliberate: the existing corpus
already includes *Ikaw Rin* in 2/4. Never force these pieces into 3/4 to match a
rule. Report duple-meter examples separately when evaluating genre recognition.
Do not label a piece Kundiman solely because its composer is Filipino, its title
contains that word, or it is in minor triple meter. *Mutya ng Pasig* was not added:
the available score identifies it as Kumintang. Public score pages requiring a
CAPTCHA were left alone. Large local symbolic collections yielded no additional
verified Kundiman works. Broader real-work coverage remains necessary.

`data/research_leads.json` separates acquired, pending, ambiguous and duplicate
sources. Santiago's *Kundiman / Cancion Filipina* is already present as *Anak
Dalita*. The 1902 *Cundiman* from *Ang Pagcacatiuala* remains a source/rights lead;
it is not included in model inputs. Known related melodies use a shared
`group_id`, so different work IDs cannot place them across training/evaluation.
A transposition/rhythm-scale-invariant 16-note phrase check found no matches
between the three new excerpts and the prior 20 works; this is a heuristic,
not proof of complete composition-level deduplication.

To reproduce the first trial's **same note lists and frozen partitions**, add
`--through 2026-11-09` to `prepare.py`. The default includes all verified
manifest records. Each run records its manifest hash, cutoff and included IDs
in `curation.json`. The historical `results.json` describes the first trial;
the three later works were not used in that rejected experiment.

## Evaluation and promotion

```bash
/usr/bin/python3.12 -B -m unittest discover -s tool/genre -p 'test_*.py' -v
/usr/bin/python3.12 -B tool/genre/export.py \
  "$GENRE_RUN/candidate_all/genre_lstm.pt" "$GENRE_RUN/baseline-corpus.json"
/usr/bin/python3.12 -B tool/genre/benchmark.py \
  "$GENRE_RUN/candidate_all/genre_lstm.tflite" \
  "$GENRE_RUN/baseline-corpus.json" "$GENRE_RUN/tflite-report.json"
```

Eight standard-library tests cover the existing Dart feature fixture, mobile
cap, padding/stride and display gates, work/group splits and label conflicts.
Four additional tests require the documented music21 runtime and verify the
manifest lengths plus source pitches, accidentals, meter, triplets and ties.
Export checks tensor shapes and Torch/LiteRT agreement to 1e-4 on up to 128
prefixes. Benchmark the actual exported model before promotion.

Check 40/80/320-event prefixes separately. Known training works are diagnostics;
only the 14 song-held-out fold results and the new traditional excerpt can support
a Kundiman generalization claim. Four validation works and one fresh test work
are a small evidence base. The frozen non-Kundiman test and external sources
measure false Kundiman labels and regressions in the other classes.

Promotion requires more correct held-out Kundiman prefixes, no reduced fold
recognition at any prefix, no additional false Kundiman calls on the non-Kundiman
test or external sources at any prefix, preserved Waltz/Jazz accuracy within one
percentage point per class/prefix, and successful export/device QA. A failed
candidate stays in the experiment directory; the shipped model stays in place.

If `/tmp` has insufficient user quota, put `GENRE_RUN` under
`.dart_tool/genre_runs/` too. Existing interrupted JSON files are not results;
new outputs use atomic replacement, with a training manifest saved before
evaluation starts.

See `results.json` for the recorded run and decision. Physical phone QA is
required only if a replacement model is actually proposed for the app.

The November 9–10 trial was rejected. The uncalibrated exploratory model made
more false Kundiman calls. Calibration of the cleaned all-data run reduced
non-Kundiman test errors, but known-training Kundiman recognition fell from
11/14 to 9/14 at 40 events and 13/14 to 11/14 at 80. Those are training diagnostics,
not claims about unseen songs. Clean fold 0 admitted no calibration satisfying
the validation constraints; further fold runs were stopped. No completed new
four-fold result or phone accuracy improvement is claimed. The original app
model remains installed and committed unchanged.
