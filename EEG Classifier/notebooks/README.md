# Precise Models — notebooks

Offline benchmarks of candidate motor-imagery classifiers on
`visionpro-ml.xdf` (~90 trials, 4 channels, 250 Hz, 3-class MI).
Goal: pick the model with the highest per-class F1 to ship through
`eeg_online_classifier.py`.

## Setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r notebooks/requirements.txt
jupyter lab
```

Run notebooks from the project root so the relative path
`../visionpro-ml.xdf` resolves.

## Notebooks

| #  | Notebook                    | Model family                           |
|----|-----------------------------|----------------------------------------|
| 00 | `00_data_exploration.ipynb` | EDA — class balance, PSD, ERPs         |
| 01 | `01_csp_lda.ipynb`          | CSP + LDA (classic MI baseline)        |
| 02 | `02_fbcsp.ipynb`            | Filter-Bank CSP + LDA                  |
| 03 | `03_riemannian.ipynb`       | Riemannian MDM / TangentSpace + LR     |
| 04 | `04_eegnet_sweep.ipynb`     | EEGNet hyperparameter grid             |
| 05 | `05_shallow_convnet.ipynb`  | Schirrmeister ShallowConvNet           |
| 06 | `06_benchmark_summary.ipynb`| Aggregate table + best-model export    |

Every notebook uses the same stratified-5-fold splits (seed=42) via
`utils.eval.cv_score`, so numbers are directly comparable.

## Shared utilities

- `utils/data.py` — `load_xdf_epochs()` mirrors the preprocessing in
  [`eeg_online_classifier.preprocess`](../eeg_online_classifier.py)
  so offline and online pipelines stay aligned.
- `utils/eval.py` — `cv_score()`, `save_result()`, `load_results()`.
- `utils/plot.py` — confusion matrix, ERP, PSD helpers.

## Deployment

Each model writes `results/<model>.pkl` with metrics. The summary
notebook picks the winner and, if it's a PyTorch model, exports
`results/best_model.pt` in the checkpoint format
[`load_model()`](../eeg_online_classifier.py#L205-L249) expects:
`{'state_dict': ..., 'classes': ...}`.

Classical pipelines (CSP, FBCSP, Riemannian) are saved as
`.joblib` — integrating them into the live classifier is out of
scope for this folder and is noted in the summary notebook.
