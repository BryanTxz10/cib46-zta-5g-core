#!/usr/bin/env python3
"""
clean_and_consolidate.py

Primera etapa del procesamiento de datos: depuracion y normalizacion.
Lee los archivos de log crudos generados por los scripts de
attack-scripts/ y monitoring/ (formato texto con salidas de kubectl,
curl y Hubble mezcladas) y extrae los campos relevantes hacia un
dataset tabular por vector y condicion, listo para el analisis
estadistico de statistical_analysis.py.

Uso:
    python3 clean_and_consolidate.py --vector a3 --input a3_C0.txt a3_C1.txt \
        --output a3_consolidado.csv
"""

import argparse
import csv
import re
import sys
from pathlib import Path


def parse_amf_top_lines(text: str) -> list[dict]:
    """Extrae lineas de 'kubectl top pod' del AMF (formato:
    NAME  CPU(cores)  MEMORY(bytes)) y las convierte en registros."""
    pattern = re.compile(
        r"(open5gs-cp-amf\S+)\s+(\d+)m\s+(\d+)Mi"
    )
    records = []
    for match in pattern.finditer(text):
        pod_name, cpu_m, ram_mi = match.groups()
        records.append({
            "pod": pod_name,
            "cpu_millicores": int(cpu_m),
            "ram_mib": int(ram_mi),
        })
    return records


def parse_http_codes(text: str) -> list[dict]:
    """Extrae codigos de respuesta HTTP de las lineas 'HTTP %{http_code}'
    generadas por los scripts run_a2*.sh."""
    pattern = re.compile(r"HTTP\s+(\d{3})")
    return [{"http_code": int(m.group(1))} for m in pattern.finditer(text)]


def parse_hubble_drops(text: str) -> int:
    """Cuenta las lineas de veredicto DROPPED registradas por Hubble."""
    return len(re.findall(r"DROPPED", text))


PARSERS = {
    "a1": lambda t: {"hubble_drops": parse_hubble_drops(t)},
    "a2": lambda t: {"http_responses": parse_http_codes(t)},
    "a2p": lambda t: {"http_responses": parse_http_codes(t)},
    "a2pp": lambda t: {"http_responses": parse_http_codes(t)},
    "a3": lambda t: {"amf_samples": parse_amf_top_lines(t)},
}


def infer_condition(filename: str) -> str:
    """Infiere la condicion (C0, C1, C2, C3) a partir del nombre del
    archivo de log, siguiendo la convencion <vector>_<condicion>.txt."""
    match = re.search(r"_(C[0-3])", filename, re.IGNORECASE)
    return match.group(1).upper() if match else "DESCONOCIDA"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vector", required=True, choices=PARSERS.keys())
    parser.add_argument("--input", nargs="+", required=True,
                         help="Archivos de log crudos a consolidar")
    parser.add_argument("--output", required=True,
                         help="Ruta del CSV consolidado de salida")
    args = parser.parse_args()

    parse_fn = PARSERS[args.vector]
    rows: list[dict] = []

    for path_str in args.input:
        path = Path(path_str)
        if not path.exists():
            print(f"AVISO: no se encontro {path}, se omite.", file=sys.stderr)
            continue

        condicion = infer_condition(path.name)
        text = path.read_text(encoding="utf-8", errors="ignore")
        parsed = parse_fn(text)

        if isinstance(parsed.get("amf_samples"), list):
            for sample in parsed["amf_samples"]:
                rows.append({"condicion": condicion, **sample})
        elif isinstance(parsed.get("http_responses"), list):
            for resp in parsed["http_responses"]:
                rows.append({"condicion": condicion, **resp})
        else:
            rows.append({"condicion": condicion, **parsed})

    if not rows:
        print("No se extrajeron registros. Verifica los archivos de entrada.",
              file=sys.stderr)
        sys.exit(1)

    fieldnames = sorted({key for row in rows for key in row.keys()})
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Consolidado escrito en {args.output} ({len(rows)} registros).")


if __name__ == "__main__":
    main()
