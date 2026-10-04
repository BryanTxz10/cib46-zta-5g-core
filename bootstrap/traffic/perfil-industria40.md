# Perfil de tráfico de fondo — red privada 5G industrial (Industria 4.0)

> Define el **punto de operación** bajo el que se miden OVERHEAD-L7 e IDR
> (punto 3 / §6.5 del protocolo). "Tráfico aceptable" NO es un número: es un
> perfil justificado con estándares y barrido en varios niveles de carga.
>
> **Fuentes para citar:** 3GPP **TS 22.104** (tráfico de aplicaciones
> ciberfísicas en verticales — payloads, ciclos, latencia, fiabilidad), 5G-ACIA
> (modelos de tráfico industrial), 3GPP TS 22.261, ITU-R M.2410 (presupuesto de
> latencia de plano de control: 20 ms; 10 ms deseable). *Verifica las celdas
> exactas de TS 22.104 antes de citar cifras concretas.*

## 1. Principio: dos capas de carga

| Capa | Qué estresa | Por qué importa aquí |
|---|---|---|
| **Señalización SBI** (attach, registro periódico, movilidad/handover, discovery/token) | NRF, SCP, cadena AMF↔AUSF↔UDM↔SMF | **Es la carga que interactúa con tu L7/RBAC** → afecta directamente OVERHEAD-L7 |
| **Plano de usuario** (telemetría, vídeo) | UPF, CPU/RAM del nodo | Crea contención realista → afecta IDR del AMF |

> Matiz clave: medir solo megabits de plano de usuario NO estresa tus políticas
> (viven en el plano de control). Prioriza la **tasa de señalización SBI**.

## 2. Clases de tráfico (perfil minería / Industria 4.0)

Valores **representativos** de TS 22.104 / 5G-ACIA (verificar celda exacta):

| Clase | Caso de uso (minería) | Payload | Periodo/ciclo | Dirección | Latencia objetivo |
|---|---|---|---|---|---|
| A — Telemetría periódica | Sensores de galería (gas, vibración, estructura) | 20–100 B | 100 ms – 1 s | UL | 50–100 ms |
| B — Máquina móvil | AGV / camiones / perforadoras (telemetría + control) | 40–250 B | 10–50 ms | UL+DL | 10–20 ms; **genera handovers** |
| C — Vídeo / tele-operación | Cámaras, tele-remoto de maquinaria | 2–20 Mbps | continuo | DL/UL | 20–100 ms |
| D — Voz / MCPTT | Push-to-talk de cuadrillas | ráfaga | eventual | UL+DL | < 100 ms |

## 3. Puntos de operación (factor controlado, se barren)

| Nivel | Descripción | UEs | Mezcla | Señalización SBI objetivo* |
|---|---|---|---|---|
| **L0** | Baseline (referencia) | 1 | — | solo heartbeats NF |
| **L1** | Nominal | ~50 | A+B + 2×C | p. ej. R1 req/s de discovery |
| **L2** | Exigente | ~150–200 | A+B + 4–5×C | p. ej. R2 req/s (R2 ≈ 3–4×R1) |

\* La tasa SBI objetivo (R1, R2) se **deriva del nº de dispositivos y su churn**
(attach rate, periodo de registro, handovers de las clases móviles). Fíjala,
justifícala y **caracteriza el generador** (RM-20) antes de medir.

**Reporte:** OVERHEAD-L7 e IDR en **L0, L1 y L2** → "aceptable" se vuelve una
curva medida, no una afirmación. Criterio de aceptación: OVERHEAD-L7 bajo L2 <
umbral ITU-R M.2410 (y el que fijes para edge industrial).

## 4. Cómo se genera (herramientas y fidelidad)

- **UERANSIM multi-UE:** N × `nr-ue`; attach/registro y sesión PDU = **señalización
  SBI real**. Plano de usuario por `uesimtunX` (iperf3 para C; script de paquetes
  pequeños periódicos para A/B).
- **Generador de carga SBI** (`sbi-load-generator.sh`): emite discovery/token a una
  **tasa objetivo** desde una NF legítima (tráfico que pasa C2/C3) → fija el punto
  de operación del NRF/L7 de forma reproducible, sin depender de simular 200 UEs.
- **Movilidad/handover (clase B):** si no emulas varios gNB, aproxima el efecto con
  churn de registro (deregister/reregister) a tasa controlada.

**Declaración de fidelidad (ponla en Limitaciones):** UERANSIM + generador SBI son
una **aproximación** de la señalización y la carga industrial, suficiente para medir
el **overhead relativo entre condiciones** (el objetivo), no para reproducir un piso
de planta real al milisegundo.

## 5. Checklist
- [ ] Elegir R1/R2 y justificarlos desde el modelo de dispositivos (TS 22.104).
- [ ] Caracterizar el generador (sostiene la tasa; el core es el cuello de botella).
- [ ] Medir en L0/L1/L2, con y sin ataque, media por run (RM-08).
- [ ] Declarar fidelidad y herramienta en Limitaciones.
