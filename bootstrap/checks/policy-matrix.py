#!/usr/bin/env python3
"""policy-matrix.py — matriz de flujos del testbed por condición, SIN clúster.

Lee los overlays de cilium-policies/conditions/ y evalúa, para cada condición
(C0-C3), si un conjunto de flujos legítimos y de ataque quedaría permitido o
descartado, y en qué sentido (egress del origen o ingress del destino).

ES UNA APROXIMACIÓN, no Cilium:
  - Solo L3/L4 (selectores de endpoints, entidades all/world y puertos).
  - No evalúa las reglas L7 (HTTP) de C2/C3, ni conntrack, ni autenticación.
  - Los labels de los pods están escritos a mano más abajo (función eps).
Sirve para detectar errores de selectores antes de aplicar y para rellenar el
mapa de radio de impacto. La verdad la da Hubble en el lab.

Uso:  python3 bootstrap/checks/policy-matrix.py [raíz_del_repo]
      make policy-matrix
Sale con código 1 si algún flujo legítimo queda descartado en alguna condición.
"""
import yaml,os,sys
REPO=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..')
base=f'{REPO}/cilium-policies/conditions'
def load(cond):
    k=yaml.safe_load(open(f'{base}/{cond}/kustomization.yaml')); out=[]
    for r in k['resources']:
        path=os.path.normpath(os.path.join(base,cond,r))
        if os.path.isdir(path): out+=load(os.path.basename(path)); continue
        out+=[d for d in yaml.safe_load_all(open(path)) if d]
    return out
def ep(ns,name,**extra):
    l={'io.kubernetes.pod.namespace':ns,'app.kubernetes.io/name':name}; l.update(extra); return l
CORE={'cib46-nf-type':'core-nf'}
def eps(labeled):
    x=CORE if labeled else {}
    E={n:ep('5g-cp',n,**x) for n in ['amf','smf','nrf','scp','udm','udr','ausf','pcf','bsf','nssf']}
    E['mongodb']=ep('5g-cp','mongodb')
    E['populate']=ep('5g-cp','open5gs',**{'app.kubernetes.io/component':'populate'})
    E['impostor']=ep('5g-cp','nf-impostor')            # A2': en 5g-cp sin identidad
    E['upf']=ep('5g-up','upf')
    E['gnb']=ep('5g-ran','ueransim-gnb'); E['ue']=ep('5g-ran','ueransim-ue')
    E['attacker']=ep('5g-ran','attacker-ue-lateral')
    E['dns']={'io.kubernetes.pod.namespace':'kube-system','k8s-app':'kube-dns'}
    E['world']=None; E['apiserver']='kube-apiserver'
    return E
def sel(selector,labels,polns):
    if not isinstance(labels,dict): return False
    selector=selector or {}
    ml=dict(selector.get('matchLabels') or {})
    # en una CNP con namespace, un selector sin namespace es implícitamente del mismo ns
    if not any(k=='io.kubernetes.pod.namespace' for k in ml) and not any(e['key']=='io.kubernetes.pod.namespace' for e in selector.get('matchExpressions',[])):
        ml['io.kubernetes.pod.namespace']=polns
    for k,v in ml.items():
        if labels.get(k)!=v: return False
    for e in selector.get('matchExpressions',[]) or []:
        v=labels.get(e['key'])
        if e['operator']=='NotIn' and v in e['values']: return False
        if e['operator']=='In' and v not in e['values']: return False
    return True
def ports_ok(rule,port,proto):
    tp=rule.get('toPorts')
    if not tp: return True
    return any(str(p['port'])==str(port) and p.get('protocol','ANY') in (proto,'ANY') for t in tp for p in t['ports'])
def peer_ok(rule,peer,polns,direction):
    key='fromEndpoints' if direction=='ingress' else 'toEndpoints'
    ent='fromEntities' if direction=='ingress' else 'toEntities'
    if not rule: return False                      # regla vacía: no permite nada
    for e in rule.get(ent,[]) or []:
        if e=='all': return True
        if e=='world' and peer is None: return True
        if e==peer: return True
    return any(sel(s,peer,polns) for s in rule.get(key,[]) or [])
def verdict(pols,E,s,d,port,proto):
    src,dst=E[s],E[d]
    for direction,me,peer in (('egress',src,dst),('ingress',dst,src)):
        if not isinstance(me,dict): continue
        ps=[p for p in pols if direction in p['spec'] and sel(p['spec'].get('endpointSelector'),me,p['metadata']['namespace'])]
        if not ps: continue                        # sin política en esa dirección: permitido
        if not any(peer_ok(r,peer,p['metadata']['namespace'],direction) and ports_ok(r,port,proto) for p in ps for r in p['spec'][direction]):
            return f'DROP({direction})'
    return 'ok'
LEGIT=[('amf','scp',7777,'TCP'),('scp','nrf',7777,'TCP'),('scp','udm',7777,'TCP'),('scp','ausf',7777,'TCP'),('scp','smf',7777,'TCP'),
 ('scp','pcf',7777,'TCP'),('nrf','amf',7777,'TCP'),('nssf','scp',7777,'TCP'),('amf','nrf',7777,'TCP'),
 ('udr','mongodb',27017,'TCP'),('pcf','mongodb',27017,'TCP'),('populate','mongodb',27017,'TCP'),
 ('gnb','amf',38412,'SCTP'),('gnb','upf',2152,'UDP'),('upf','gnb',2152,'UDP'),('smf','upf',8805,'UDP'),
 ('ue','gnb',4997,'UDP'),('upf','world',443,'TCP'),('smf','dns',53,'UDP'),('gnb','dns',53,'UDP'),('ue','dns',53,'UDP')]
ATTACK=[('attacker','nrf',7777,'TCP'),('attacker','mongodb',27017,'TCP'),('attacker','amf',38412,'SCTP'),('attacker','upf',2152,'UDP'),
 ('attacker','upf',8805,'UDP'),('attacker','world',443,'TCP'),('attacker','apiserver',6443,'TCP'),
 ('impostor','nrf',7777,'TCP'),('impostor','udm',7777,'TCP'),('impostor','mongodb',27017,'TCP'),('impostor','world',443,'TCP'),('impostor','apiserver',6443,'TCP'),
 ('upf','nrf',7777,'TCP'),('upf','mongodb',27017,'TCP'),('upf','smf',8805,'UDP'),('upf','dns',53,'UDP'),('upf','apiserver',6443,'TCP'),
 ('amf','world',443,'TCP'),('amf','apiserver',6443,'TCP'),('amf','upf',8805,'UDP'),('bsf','mongodb',27017,'TCP')]
conds=['c0','c1','c2','c3']
P={c:load(c) for c in conds}
roto=False
for title,flows in (('TRAFICO LEGITIMO (debe ser ok)',LEGIT),('ATAQUES / NO PERMITIDO',ATTACK)):
    print(f'\n== {title} ==\n{"flujo":34}'+''.join(f'{c:15}' for c in conds))
    for f in flows:
        row=[verdict(P[c],eps(c in('c2','c3')),*f) for c in conds]
        if flows is LEGIT and any(r!='ok' for r in row): roto=True
        print(f'{f[0]+" -> "+f[1]+":"+str(f[2])+"/"+f[3]:34}'+''.join(f'{r:15}' for r in row))
if roto:
    print('\nERROR: hay tráfico legítimo descartado en alguna condición.'); sys.exit(1)
print('\nOK: todo el tráfico legítimo listado pasa en C0-C3 (aproximación L3/L4).')
