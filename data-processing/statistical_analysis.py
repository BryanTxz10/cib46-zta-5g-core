#!/usr/bin/env python3
"""
statistical_analysis.py

Procesamiento estadistico inferencial de las mediciones continuas del
experimento (IDR-CPU, IDR-RAM, IDR-RTT, OVERHEAD-L7). Implementa las
cuatro etapas descritas en la seccion de Analisis y procesamiento de
datos (Capitulo IV):

  1. Verificacion de normalidad (Shapiro-Wilk, alfa = 0.05)
  2. Prueba de comparacion entre condiciones (Mann-Whitney U, no
     parametrica, aplicada cuando no se cumple el supuesto de
     normalidad)
  3. Tamano del efecto (d de Cohen)
  4. Estadisticos descriptivos (media, mediana, desviacion estandar,
     P95, P99)

Requiere: pandas, numpy, scipy, statsmodels
"""

import sys
import numpy as np
import pandas as pd
from scipy import stats


def cohens_d(a: np.ndarray, b: np.ndarray) -> float:
    """Calcula la d de Cohen (tamano del efecto) para dos muestras
    independientes, usando la desviacion estandar combinada (pooled)."""
    na, nb = len(a), len(b)
    pooled_std = np.sqrt(
        ((na - 1) * np.var(a, ddof=1) + (nb - 1) * np.var(b, ddof=1))
        / (na + nb - 2)
    )
    return (np.mean(b) - np.mean(a)) / pooled_std


def descriptive_stats(series: pd.Series) -> dict:
    return {
        "n": len(series),
        "media": series.mean(),
        "mediana": series.median(),
        "desv_std": series.std(),
        "minimo": series.min(),
        "maximo": series.max(),
        "p95": series.quantile(0.95),
        "p99": series.quantile(0.99),
    }


def compare_conditions(sample_a: pd.Series, sample_b: pd.Series,
                        label_a: str, label_b: str, alpha: float = 0.05) -> dict:
    """Ejecuta el flujo completo: Shapiro-Wilk -> Mann-Whitney U -> d de Cohen."""
    shapiro_a = stats.shapiro(sample_a)
    shapiro_b = stats.shapiro(sample_b)

    normal_a = shapiro_a.pvalue > alpha
    normal_b = shapiro_b.pvalue > alpha

    u_stat, p_value = stats.mannwhitneyu(
        sample_a, sample_b, alternative="two-sided"
    )
    effect_size = cohens_d(sample_a.to_numpy(), sample_b.to_numpy())

    return {
        "condicion_a": label_a,
        "condicion_b": label_b,
        "shapiro_a_stat": shapiro_a.statistic,
        "shapiro_a_p": shapiro_a.pvalue,
        "shapiro_a_normal": normal_a,
        "shapiro_b_stat": shapiro_b.statistic,
        "shapiro_b_p": shapiro_b.pvalue,
        "shapiro_b_normal": normal_b,
        "mann_whitney_u": u_stat,
        "mann_whitney_p": p_value,
        "significativo": p_value < alpha,
        "cohens_d": effect_size,
    }


def main():
    if len(sys.argv) != 4:
        print("Uso: statistical_analysis.py <archivo.csv> <columna> <columna_condicion>")
        sys.exit(1)

    csv_path, value_col, condition_col = sys.argv[1], sys.argv[2], sys.argv[3]
    df = pd.read_csv(csv_path)

    conditions = sorted(df[condition_col].unique())
    print(f"Condiciones encontradas: {conditions}")

    for i in range(len(conditions) - 1):
        label_a, label_b = conditions[i], conditions[i + 1]
        sample_a = df[df[condition_col] == label_a][value_col]
        sample_b = df[df[condition_col] == label_b][value_col]

        print(f"\n=== {label_a} vs {label_b} ===")
        print("Descriptivos", label_a, descriptive_stats(sample_a))
        print("Descriptivos", label_b, descriptive_stats(sample_b))

        result = compare_conditions(sample_a, sample_b, label_a, label_b)
        for k, v in result.items():
            print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
