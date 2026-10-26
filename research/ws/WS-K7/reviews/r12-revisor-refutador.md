## Revisor refutador: WS-K7, lanzamiento nuevo, ronda 1

Revisión ciega: no leí `reviews/`. Solo lectura: Python únicamente sobre `audit.csv`, `.h5` y el registro existentes.

### 1. Conclusiones, alternativa y dato que las separa

| Conclusión del reporte | Mejor alternativa | Dato que las separa | ¿Ya está en los datos? |
|---|---|---|---|
| H queda **sin decidir** (0.319; neto 1.57) {C-145} | La prueba no es válida, porque H se formuló «en corrida convergida» y ≥ 85 % de los CG no converge | `k7v5_mo20` con `max_inner_pres` 200 | No. El reporte lo declara y reconoce que el veredicto solo protege contra «soportada». Recalculado: 0.3186 = 0.3836·0.7055 + 0.1629·0.2945. |
| El 29 % de Σ\|e\| en las nogas es gas exportado por la α de cara media con la celda en `act_g` por alcance | Artefacto del CG truncado en esa población | Brecha de la identidad de fila con el CG convergido en baño sobre poro seco | No para B1 (C-164). **Dato nuevo:** en `k7v4_long` la brecha crece de 0.177 a 0.258 por bloques de 1000 pasos (O2), lo que apunta en esa dirección. El conducto sí está verificado en el código (`mod_pressure_3d.f90:1237-1260`). |
| e_multi depende de las externas (×1.84; 43 %) | Variación entre trayectorias en un régimen caótico (una sola corrida por brazo) | Varias trayectorias, o estabilidad por bloques | **Sí, en parte:** el cociente 5/20 por bloques de 200 pasos es 1.70–1.81 y el de las nogas 0.94–0.99. Respalda la dependencia, pero el reporte no lo cita (O3). |
| El cociente por celda deriva hacia la refutación en las ventanas largas | Relajación tras el reinicio: las dos ventanas largas arrancan del mismo snapshot | Una ventana desde otro snapshot | No (O3). Se usa solo como cautela. |
| La población de las nogas no es la de Plan E | Confusor temporal (Plan E se midió a 320 s) | Recuento a 320 s | Sí: 454/564 sobre poro seco y 51/1612 caras a poro saturado. Lo recalculé y coincide con C-165. |

### 2. Repeticiones de fracasos registrados

- El WS es diagnóstico: numérica bit a bit y sin remedio. No repite ningún fracaso.
- El «remedio latente» (α del dador o sacar el baño del alcance) está bien declarado frente a F2.17–F2.21, F2.24 y la familia D/E/F/G/F2.31.
- Falta un antecedente: el negativo cerrado del «limitador dentro del Poisson» es **D2.2/D2.2c de Plan D** (`docs/PLAN_D_acople_implicito_alpha_p.md:197`), no Plan K, que sigue abierto (O4).

### 3. Objeciones

**O1 (bloqueante): el resultado de K7 no está registrado contra C-110.**
- `ledger.py show C-110` devuelve solo C-120, C-151 y C-152, y C-152 «RETIRA 'matiza C-110'». La cadena C-121…C-167 no tiene ref a C-110.
- C-110 sigue diciendo que el piso «es el complemento… gas que aparece donde el líquido se retira», con «+5.11e-3 creada» y el reparto «(convergido)».
- K7 midió lo contrario en las nogas: complemento por llamada 1.9e-6 kg frente a Σ\|e\| 4.8e-3 kg, y e = −dt·ΣF_g (C-137, C-157). Además, la convergencia no está medida (C-125) y e_multi depende de las externas en K7.
- El README exige que una corrección sea un evento con `ref`. C-110 ya no sale en `ledger.py open`, así que `/estado` la daría por resuelta sin el veredicto de K7.
- La regla `transporte-energia.md:140-143` sigue diciendo «alternativa abierta (ws_Fg_lk = 0)», y en :152-153 la declara NULA.
- **Resolución:** un evento `--ref C-110` con C-145, C-137/C-157, C-125 y C-152, comprobado con `show C-110`; y la corrección de :140-143 por el coordinador.

**O2 (no bloqueante): la cota «≤ 16–18 % en B1» vale solo con 20 externas en ≤ 1 s.**
- En `k7v4_long` la brecha es 0.226 en total y crece de forma monótona: 0.177 → 0.222 → 0.228 → 0.233 → 0.242 → 0.258. Ese banco usa el instrumento del cuarto ciclo, 5 externas y no pasa check_audit.
- Una cota sobre una suma cuyos términos «pueden cancelarse» no acota el CG por separado.
- **Resolución:** restringir la cifra y citar esos valores. Lo que decide es `k7v5_mo20` con `max_inner_pres` 200.

**O3 (no bloqueante): todo el régimen marginal se mide con una sola trayectoria por brazo.**
- Los bloques de 200 pasos (1.70–1.81; nogas 0.94–0.99) sostienen la dependencia de las externas. El reporte debería citarlos frente a la regla del juez estadístico.
- La deriva «hacia la refutación» no se separa de la relajación tras el reinicio.
- **Resolución:** citar los bloques. Para la deriva, una ventana desde otro snapshot (p. ej. 300000) o una segunda trayectoria con 12 o 14 ranks.

**O4 (no bloqueante): antecedente mal etiquetado.** Plan K figura como «registrado negativo» con G1/G2 abiertos. Hay que citar D2.2/D2.2c como el negativo cerrado.

### Verificado
- Descomposición 0.319 / 0.404 / 0.333 / 0.504 y valores de e_multi y err_liq_all.
- Código del conducto: α de cara media y `face_lim` (:1237-1260); alcance (:234-236).
- Población de las nogas a 320 s.
- Cadena del registro de C-110 y contradicción interna de la regla.
- Cocientes 5/20 por bloques y brecha por bloques en `k7v4_long`.
- Diff staged sin cambios fuera del índice; logs de tests posteriores a la última edición de `src/` y `tests/`.

VEREDICTO: rechaza