#!/usr/bin/env python3
"""
generate_figures.py

Genera las figuras comparativas entre condiciones experimentales
(TBANA/TBOC por condicion, IDR-CPU/RAM, distribucion de latencia SBI)
a 300 DPI, en el estilo utilizado en el capitulo de resultados.

Requiere: matplotlib, seaborn, pandas

Uso:
    python3 generate_figures.py --csv idr_c0_c1.csv --kind idr --output figura_idr.png
"""

import argparse
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_theme(style="whitegrid")


def plot_idr(df: pd.DataFrame, output: str) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))

    sns.boxplot(data=df, x="condicion", y="cpu_millicores", ax=axes[0])
    axes[0].set_title("IDR-CPU del AMF por condicion")
    axes[0].set_ylabel("CPU (millicores)")

    sns.boxplot(data=df, x="condicion", y="ram_mib", ax=axes[1])
    axes[1].set_title("IDR-RAM del AMF por condicion")
    axes[1].set_ylabel("RAM (MiB)")

    fig.tight_layout()
    fig.savefig(output, dpi=300)
    print(f"Figura guardada en {output}")


def plot_latency_distribution(df: pd.DataFrame, output: str) -> None:
    fig, ax = plt.subplots(figsize=(6, 4))
    sns.histplot(data=df, x="latency_ms", hue="condicion",
                 kde=True, element="step", ax=ax)
    ax.set_title("Distribucion de latencia SBI por condicion")
    ax.set_xlabel("Latencia (ms)")
    fig.tight_layout()
    fig.savefig(output, dpi=300)
    print(f"Figura guardada en {output}")


def plot_block_rate(df: pd.DataFrame, output: str) -> None:
    fig, ax = plt.subplots(figsize=(6, 4))
    summary = df.groupby("condicion")["bloqueado"].mean().reset_index()
    summary["porcentaje"] = summary["bloqueado"] * 100
    sns.barplot(data=summary, x="condicion", y="porcentaje", ax=ax)
    ax.set_title("Tasa de bloqueo por condicion")
    ax.set_ylabel("% bloqueado")
    ax.set_ylim(0, 100)
    fig.tight_layout()
    fig.savefig(output, dpi=300)
    print(f"Figura guardada en {output}")


PLOTTERS = {
    "idr": plot_idr,
    "latencia": plot_latency_distribution,
    "bloqueo": plot_block_rate,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, help="CSV consolidado de entrada")
    parser.add_argument("--kind", required=True, choices=PLOTTERS.keys())
    parser.add_argument("--output", required=True, help="Ruta de la imagen PNG de salida")
    args = parser.parse_args()

    df = pd.read_csv(args.csv)
    PLOTTERS[args.kind](df, args.output)


if __name__ == "__main__":
    main()
