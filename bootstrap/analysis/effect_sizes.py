#!/usr/bin/env python3
"""
effect_sizes.py — RM-03: tamaños de efecto CONGRUENTES con Mann-Whitney U.

El script original (data-processing/statistical_analysis.py) reporta d de Cohen,
que asume normalidad/homocedasticidad, junto a una prueba no paramétrica. Este
módulo provee tamaños de efecto basados en rangos, apropiados para Mann-Whitney:

  - rank_biserial(U, n1, n2): correlación rango-biserial, r = 1 - 2U/(n1*n2).
    Rango [-1, 1]; magnitud interpretable como la de una correlación.
  - cliffs_delta(a, b): delta de Cliff, robusto y con interpretación directa
    (proporción de pares en que b>a menos aquellos en que a>b).
  - common_language(U, n1, n2): efecto del lenguaje común (AUC) = U/(n1*n2),
    P(una obs. de B supera a una de A).

Puede usarse como librería o CLI:
    python3 effect_sizes.py <csv> <columna_valor> <columna_condicion>
"""
from __future__ import annotations
import sys
import numpy as np
import pandas as pd
from scipy import stats


def rank_biserial(u_stat: float, n1: int, n2: int) -> float:
    return 1.0 - (2.0 * u_stat) / (n1 * n2)


def common_language(u_stat: float, n1: int, n2: int) -> float:
    return u_stat / (n1 * n2)


def cliffs_delta(a: np.ndarray, b: np.ndarray) -> float:
    # Convención alineada con rank_biserial: positivo => B tiende a ser mayor.
    a = np.asarray(a); b = np.asarray(b)
    b_gt_a = sum((b > x).sum() for x in a)
    b_lt_a = sum((b < x).sum() for x in a)
    return (b_gt_a - b_lt_a) / (len(a) * len(b))


def interpret_cliff(d: float) -> str:
    ad = abs(d)
    if ad < 0.147: return "insignificante"
    if ad < 0.33:  return "pequeño"
    if ad < 0.474: return "mediano"
    return "grande"


def compare(a: pd.Series, b: pd.Series, la: str, lb: str) -> dict:
    a = a.dropna().to_numpy(); b = b.dropna().to_numpy()
    n1, n2 = len(a), len(b)
    # U tomando A como referencia (alternative two-sided para el p-valor).
    u_ab, p = stats.mannwhitneyu(a, b, alternative="two-sided")
    delta = cliffs_delta(a, b)
    return {
        "comparacion": f"{la} vs {lb}",
        "n1": n1, "n2": n2,
        "mann_whitney_u": float(u_ab),
        "p_value": float(p),
        "rank_biserial_r": float(rank_biserial(u_ab, n1, n2)),
        "common_language_auc": float(common_language(u_ab, n1, n2)),
        "cliffs_delta": float(delta),
        "cliff_magnitud": interpret_cliff(delta),
    }


def main() -> None:
    if len(sys.argv) != 4:
        print("Uso: effect_sizes.py <csv> <columna_valor> <columna_condicion>")
        sys.exit(1)
    csv_path, value_col, cond_col = sys.argv[1:4]
    df = pd.read_csv(csv_path)
    conds = sorted(df[cond_col].unique())
    print(f"Condiciones: {conds}")
    # Todas las comparaciones relevantes: adyacentes + total C0 vs Cmax.
    pairs = [(conds[i], conds[i + 1]) for i in range(len(conds) - 1)]
    if len(conds) > 2:
        pairs.append((conds[0], conds[-1]))
    for la, lb in pairs:
        res = compare(df[df[cond_col] == la][value_col],
                      df[df[cond_col] == lb][value_col], la, lb)
        print("\n=== " + res["comparacion"] + " ===")
        for k, v in res.items():
            print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
