## Revisión del refutador: WS-K10, ronda 1

**Veredicto: rechazo.** Hay una objeción bloqueante: los bancos limpios desde 290 s ya existen y el reporte no los usa. Además contradicen el cuadro entre dt que el reporte arma en 280 s.

Fuentes leídas: `research/README.md`, el reporte, C-197 y C-202..C-227 en el registro, la sección WS-K8/K10 de `.claude/rules/transporte-energia.md` y la sección «lo que NO funcionó» de `acople-pv.md`. Todas las cifras de abajo son mías y salen de leer `audit.csv` existentes con python, sin correr nada.

### 1. Conclusiones, hipótesis alternativas y datos que las separan

| Conclusión del reporte | Mejor alternativa | Dato que las separa | ¿Ya existe? ¿Qué dice? |
|---|---|---|---|
| La premisa de C-197 era un artefacto del paso 1 (66 %) | El paso 1 no se debe solo a que se acota el dt: es la referencia Tg_end heredada, venteada con el dt nuevo | Paso 1 de k11_dt025_tgfix y de k11_dt025_s290 | Sí. Con tgfix, err_cc del paso 1 pasa de −1.586e-3 a +5.32e-4 y el resto no cambia. Desde 290 s, con las claves activas, el paso 1 aún pone −1.73e-3. **La conclusión se sostiene, pero el mecanismo está incompleto** (O3). |
| e(0.5)/e(1) = 0.32 (0.353 en pasos tranquilos); no se decide tasa o truncamiento | La caída con dt es el transitorio del cambio de claves de 280 s (C-227). En régimen limpio, e es casi una tasa | Las mismas piezas desde el snapshot de 290 s | **Sí, y no está en el reporte.** Sin el paso 1, r(0.25)/r(1) de e: 0.833 (IC90 0.82-0.85) en 290 s frente a 0.512 (0.46-0.62) en 280 s. Bgq: 0.877 frente a 0.745. err_liq: ×1.040 frente a ×1.135. Bloques 10/40, 4000 réplicas. **O1** |
| Bgq es la pieza de mayor media con cada dt | Que sea un efecto de la ventana o del transitorio | Lo mismo en 290 s | Sí: 1.17 e (1 ms) y 1.24 e (0.25 ms). **Se sostiene** (sujeta a que la contabilidad no es única, como ya dice el reporte). |
| La densidad posterior al último Poisson pesa < 2 % de e | La cancelación Br2/Bgr depende de la ventana | 290 s | Sí: 1.8 % con 1 ms y 0.5 % con 0.25 ms. **Se sostiene, al borde.** |
| Pesos y magnitudes (Bgq 1.55/1.91 e, Br2 −0.68 e, e −1.45e-5) | Son propios de la ventana 280.00-280.06 s | 290 s, misma config | Sí: e vale −4.93e-5 por paso (×3.4), estable en los cinco quintos. Bgq 1.17 e, Br2 −0.30 e, err_liq −0.28 e. **No son representativos de «la meseta»** (O2). |
| Config de B1: store_gas ×130 y gas libre 0.66 | Transitorio del cambio de claves en 280 s | Quintos de k10b_base; banco de B1 en 290 s | Quintos: sí. store_multi va de 4.0 a 4.3e-5 y Bgq es estable; err_free oscila de −1.5e-6 a −3.7e-5. No hay banco de B1 en 290 s (O4). |
| Sin cambio numérico | La base de la suite salió del mismo binario nuevo, así que la comparación sería trivial | k10_* frente a k8s_* (binario viejo, 137 columnas) | Sí. Las 137 columnas comunes son idénticas en 3 bancos de campaña con otro binario: evidencia independiente. **Se sostiene** en campaña; la base de la suite sigue sin procedencia (ya declarado). |

### 2. Repeticiones de fracasos registrados

- **err_liq_lk «por paso»** frente a C-197 (retirada por C-206): el reporte explica la diferencia (una pieza y no e entera, sin el paso 1) y no la adopta. Es aceptable. En 290 s, con dos puntos, k = +1.93e-7 kg/paso, del mismo signo y orden que en 280 s (2.75e-7). Eso la hace falsable (O5).
- **Partir o linealizar Bgq** frente a M6-1 y M7-5 (guardia ALPHA_CUTOFF y `ws_qin_cap`) y frente a Plan D (acople implícito, D2.2): el reporte ya lo declara como riesgo y no propone ningún arreglo.
- No encontré ninguna conclusión que repita un cambio ya refutado: el workstream es diagnóstico y no tiene cambio numérico.

### 3. Objeciones

1. **O1 (bloqueante).** El reporte declara pendiente y «a pre-registrar» la comparación entre dt desde 290 s, pero k11_mo20_s290 y k11_dt025_s290 ya existen, con el binario k10b y las columnas de K10. Dan r(0.25)/r(1) = 0.833 (0.82-0.85), frente a 0.512 en 280 s, sin solape de IC90. El análisis entre dt de 280 s (0.32, 0.353, 0.812, sensibilidades) queda dominado por el transitorio, y la lectura limpia apunta a un error mayormente independiente de dt: ~78 % con ajuste lineal, lectura y no medida. Esos datos ya se vieron, así que no admiten pre-registro.
   *Resolución:* añadir la lectura de 290 s; marcar las cifras entre dt de 280 s como confundidas; pre-registrar solo sobre una corrida nueva, p. ej. 0.5 ms desde eaf3d_00290000.h5 o un snapshot de 300 s con las mismas claves.
2. **O2.** Las magnitudes y los pesos /e dependen de la ventana: en 290 s, e es ×3.4 y los pesos /e cambian a la mitad.
   *Resolución:* tabla con las dos ventanas, o restringir el enunciado a 280.00-280.06 s.
3. **O3.** El paso 1 lo dispara Tg_end con el dt nuevo, y existe con cualquier snapshot (tgfix y s290).
   *Resolución:* citarlo y fijar que se excluye el paso 1 en toda comparación entre dt.
4. **O4.** Las lecturas en la config de B1 solo existen en 280 s, con FAIL de energy_balance y regime_gas.
   *Resolución:* banco con el binario k10b y la config de B1 desde 290 s (o en 340-345 s), comparado con k11_mo20_s290.
5. **O5.** La hipótesis de err_liq_lk es falsable.
   *Resolución:* pre-registrar err_liq_lk ≈ 6.92e-6 kg/paso con 0.5 ms desde 290 s, con una banda congelada antes de correr.

### Verificado por mí (solo lectura)
- Las piezas sin el paso 1 de k10b_mo20, k10b_dt05 y k10b_dt025 reproducen la tabla del reporte (Bgq 1.55/1.91 e; Br2/Bgr; e −1.4505e-5 / −4.572e-6).
- Piezas de k11_mo20_s290, k11_dt025_s290 y k11_dt025_tgfix: cifras y bootstrap de arriba.
- Estabilidad por quintos de k10b_mo20, k11_mo20_s290, k10b_dt025, k11_dt025_s290 y k10b_base.
- judge_otp_280 no tiene `m_gas_err_multi`: no sirve para separar ventana y transitorio.

VEREDICTO: rechaza