#!/usr/bin/env python3
"""
omnibus_posthoc.py — RM-07/RM-08: flujo estadístico correcto para comparar las
cuatro condiciones (C0..C3) en una métrica continua.

Flujo:
  1) Test ÓMNIBUS de Kruskal-Wallis sobre los >=3 grupos (¿hay alguna
     diferencia?). No paramétrico, apto para no-normalidad y n pequeños.
  2) Si es significativo, POST-HOC de Dunn con corrección por comparaciones
     múltiples (Holm por defecto; alternativa Benjamini-Hochberg/FDR).
  3) Para cada par: tamaño de efecto rango-biserial + IC bootstrap del 95%
     de la diferencia de medianas.

Esto sustituye el enfoque del script original (solo pares adyacentes, sin
corrección, sin ómnibus, con d de Cohen). Complementa —no borra—
data-processing/statistical_analysis.py.

Requiere: pandas, numpy, scipy. (scikit-posthocs es opcional; si no está, se
usa una implementación propia del test de Dunn.)

Uso:
    python3 omnibus_posthoc.py <csv> <columna_valor> <columna_condicion> \
        [--correction holm|fdr_bh] [--boot 5000]
"""
from __future__ import annotations
import argparse
import itertools
import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.stats.multitest import multipletests


def dunn_pairwise(df: pd.DataFrame, value_col: str, group_col: str):
    """Test de Dunn: z y p sin corregir por par, usando rangos globales."""
    d = df[[value_col, group_col]].dropna()
    d = d.assign(_rank=d[value_col].rank())
    N = len(d)
    groups = sorted(d[group_col].unique())
    n = d.groupby(group_col)[value_col].count()
    rbar = d.groupby(group_col)["_rank"].mean()

    # Corrección por empates para la varianza.
    _, counts = np.unique(d[value_col].to_numpy(), return_counts=True)
    ties = (counts**3 - counts).sum()
    sigma2 = (N * (N + 1) / 12.0) - ties / (12.0 * (N - 1))

    rows = []
    for a, b in itertools.combinations(groups, 2):
        se = np.sqrt(sigma2 * (1.0 / n[a] + 1.0 / n[b]))
        z = (rbar[a] - rbar[b]) / se
        p = 2 * (1 - stats.norm.cdf(abs(z)))
        rows.append({"a": a, "b": b, "z": z, "p_raw": p})
    return pd.DataFrame(rows)


def rank_biserial(a: np.ndarray, b: np.ndarray) -> float:
    u, _ = stats.mannwhitneyu(a, b, alternative="two-sided")
    return 1.0 - (2.0 * u) / (len(a) * len(b))


def boot_ci_median_diff(a, b, n_boot=5000, seed=42):
    rng = np.random.default_rng(seed)
    a = np.asarray(a); b = np.asarray(b)
    diffs = np.empty(n_boot)
    for i in range(n_boot):
        diffs[i] = (np.median(rng.choice(b, len(b), replace=True))
                    - np.median(rng.choice(a, len(a), replace=True)))
    return float(np.percentile(diffs, 2.5)), float(np.percentile(diffs, 97.5))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("csv"); ap.add_argument("value_col"); ap.add_argument("group_col")
    ap.add_argument("--correction", default="holm", choices=["holm", "fdr_bh"])
    ap.add_argument("--boot", type=int, default=5000)
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    groups = sorted(df[args.group_col].unique())
    samples = [df[df[args.group_col] == g][args.value_col].dropna().to_numpy()
               for g in groups]

    print(f"Grupos: {groups}  (n = {[len(s) for s in samples]})")
    if any(len(s) < 3 for s in samples):
        print("AVISO: algún grupo tiene n<3; la inferencia es muy poco potente "
              "(ver RM-06). Trata los resultados como exploratorios.")

    # 1) Ómnibus
    h, p_omni = stats.kruskal(*samples)
    print(f"\n[Ómnibus] Kruskal-Wallis: H={h:.4f}  p={p_omni:.4g}")
    if p_omni >= 0.05:
        print("No significativo: no se justifica post-hoc.")
        return

    # 2) Post-hoc Dunn + corrección
    dunn = dunn_pairwise(df, args.value_col, args.group_col)
    dunn["p_adj"] = multipletests(dunn["p_raw"], method=args.correction)[1]

    # 3) Efecto + IC por par
    print(f"\n[Post-hoc] Dunn con corrección {args.correction}:")
    for _, r in dunn.iterrows():
        a = df[df[args.group_col] == r["a"]][args.value_col].dropna().to_numpy()
        b = df[df[args.group_col] == r["b"]][args.value_col].dropna().to_numpy()
        rb = rank_biserial(a, b)
        lo, hi = boot_ci_median_diff(a, b, args.boot)
        sig = "*" if r["p_adj"] < 0.05 else " "
        print(f"  {r['a']} vs {r['b']}: p_adj={r['p_adj']:.4g}{sig}  "
              f"rank_biserial={rb:+.3f}  "
              f"IC95%(mediana_b - mediana_a)=[{lo:.3f}, {hi:.3f}]")


if __name__ == "__main__":
    main()
