# Revisión del refutador, WS-K8 (el harness la marca como ronda 1; el reporte ya trae la ronda 3 del coordinador)

Revisión de solo lectura: no corrí make, mpirun ni simulaciones; solo python sobre datos existentes.

**Qué leí**
- El reporte, `research/README.md` y `status.json`.
- Las afirmaciones C-106..C-109, C-125, C-152 y C-181..C-186.
- `.claude/rules/acople-pv.md` (secciones del 22-oct, J-B y M12-E1) y el párrafo WS-K8 de `.claude/rules/transporte-energia.md`.
- Mi propia r2 (no leí las revisiones de otros revisores).

**Qué verifiqué**
- `barrido_outer.py` sobre k8s_mo{5,10,20,40,80}, k8_base y k8_cg1000, y `--identidad` entre k8_cg1000 y k8s_mo20.
- `check_audit.py` sobre los seis bancos.
- Las líneas [STEP] de `run.log`.
- Las horas: el commit 34be842 es de las 15:17:52 y el primer banco arranca a las 15:18:02, así que el pre-registro es anterior a las corridas.

**Estado de mis objeciones de la r2**
- O1: resuelta con el barrido pre-registrado C-182/C-184.
- O2: resuelta; el 0.93 está retirado en el reporte y en la regla.
- O3: resuelta; «piso de conversión» figura como hipótesis.

## 1. Conclusiones, alternativa y dato que las separa

| Conclusión | Mejor alternativa | Dato que separa | ¿Está en los datos? Qué dice |
|---|---|---|---|
| C-182 SOPORTADA: D es estructural desde ~20 externas (D1 −2.105/−2.078/−2.085e-5) | (a) Meseta del residuo estancado del lazo. (b) Enganche de fase de un ciclo entre outers: N = 20/40/80 son todos múltiplos de 20 | (a) D frente a res por paso y extrapolación a res → 0. (b) N impar (21, 41) o D por outer | (a) Sí, y favorece al reporte: corr(D, res) por paso entre −0.20 y 0.30 con ≥ 20 externas; la extrapolación de D1 frente a res_cont da entre −1.8e-5 y −2.07e-5 en res = 0. (b) No hay datos. Indicio: corr de D por paso entre mo40 y mo80 = 0.20 (0.67 entre mo20 y mo40) con trayectoria física idéntica |
| «Con 5 externas, la config de B1, D vale el doble; en B1 la mitad es truncamiento» | El «doble» y la «mitad» son con CG 1000, que no es B1 | k8_base (5 externas, CG 20) | Sí, y contradice el texto: D1 −3.60e-5 (1.71×), media −3.28e-5 (1.51×); el truncamiento es el 42 % / 34 %, no el 50 %. Con 5 externas, converger el CG SUBE \|D\| un 16 % (no aditivo) |
| El CG truncado aporta ~60 % del error del gas libre con 5 externas; de 5 a 20 externas el resto baja ~40× | — | — | Se verifica: 9.20e-3 → 3.63e-3 (60.5 %); 3.63e-3/9.20e-5 = 39 |
| Multifase y C-110 en meseta de 20 a 80 externas | Las mismas (a)/(b) | Las mismas | Medias estables (0.3156/0.3154/0.3145) |
| C-169 refutada por la letra, C-170 sin decidir, art despreciable, neto ≠ outlet | — (acotadas en la r2) | — | Sí |

## 2. Repeticiones de lo registrado

- Ningún arreglo numérico: no repite D2.2, las reglas D/E/F/G, F2.31 por paso ni n_pc_max.
- C-184 vuelve a medir el piso «estructural, independiente de las externas» de C-109 y la proporción de C-107. En k8s_mo20 la EOS reescribe 1.48e-5 kg/paso (C-109: ~1.5e-5), y EOS(mo10)/EOS(mo5) = 0.40 (C-107: 0.40).
- C-125 ya había advertido que esa lectura no medía la convergencia del lazo. K8 la mide y encuentra que el lazo no converge ni con 80 externas, así que hereda el mismo hueco. El reporte no lo dice (O3).
- Las salvedades de Plan D/E sobre los bancos de pocas celdas no aplican: el banco que decide es el estado de B1 a 280 s.

## 3. Objeciones

1. **O1 (bloqueante): B1 mal atribuido.**
   - Qué dice el texto: «con 5 externas, la config de B1, vale el doble (−4.18e-5); en B1 la mitad es truncamiento». Aparece en el reporte (líneas 41-42 y 307-311), en C-183 y en el párrafo persistente de `transporte-energia.md`.
   - Por qué está mal: −4.18e-5 es de k8s_mo5, con CG 1000. B1 corre con CG 20.
   - Qué da la config real de B1 (k8_base): D1 −3.60e-5 y media −3.28e-5, es decir 1.71× / 1.51× la meseta. El truncamiento es el 42 % (paso 1) / 34 % (media).
   - Además los efectos no se suman: con 5 externas, converger el CG sube \|D\| un 16 % y baja un 60 % el error del gas libre.
   - Resolución: el dato ya existe (`barrido_outer.py campaigns/b1/k8_base`). Corregir el texto, la regla y C-183 con un evento nuevo con ref.
2. **O2 (no bloqueante): posible enganche de fase.**
   - Los N que deciden son todos múltiplos de 20, y el lazo está estancado sin converger.
   - Un ciclo entre outers de periodo que divida a 20 daría una «meseta» artificial. Hay antecedentes en acople-pv.md: M12-E1 y el ciclo entre outers de J-B.
   - Resolución: correr N = 21 y 41 (o N impares), o registrar D/res por outer en el paso 1; tolerancia del 10 %. Mientras tanto, declarar la limitación en el reporte.
3. **O3 (no bloqueante): falta la relación con C-107/C-109/C-125.**
   - Decir en qué difiere K8: CG convergido, métrica rem2, 80 externas, residuos registrados.
   - Decir que la salvedad de C-125 sigue vigente.
   - Datos ya existentes: check_audit sobre k8s_mo{5,10,20}.
4. **O4 (no bloqueante): falta el dato que sostiene la salvedad.**
   - Añadir como lectura, no como veredicto, la correlación por paso D–res (entre −0.20 y 0.30) y la extrapolación de D1 a res_cont → 0 (entre −1.8e-5 y −2.07e-5).
   - Ese dato sostiene que la meseta no sigue al residuo estancado. La prueba definitiva sigue siendo un lazo que converja.

VEREDICTO: rechaza