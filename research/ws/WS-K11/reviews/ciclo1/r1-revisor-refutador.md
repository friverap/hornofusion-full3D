## Revisión del refutador, WS-K11, ronda 1

**Veredicto: rechaza.** Lo que la prueba pre-registrada sí sostiene es que el pico es propio de reiniciar desde el snapshot de 280 s y que no lo causa dt por sí solo. El reporte va más allá en tres puntos:
- Atribuye la causa a las claves, sin aislarlas a 0.25 ms.
- Llama «transitorio» a un régimen que a 0.25 ms no decae en 60 ms.
- Omite que el banco de control llega a 450 kPa sin ningún cambio de claves.

Revisión hecha en solo lectura: Python únicamente sobre audit.csv, h5 y configs existentes; sin corridas.

### 1. Conclusiones, hipótesis alternativa y dato que las separa

**C1. La centinela de k10b_dt025 es el transitorio del cambio de claves (C-227).**
- **Alternativa:** el estado de 280 s, o el snapshot escrito por el binario del 20-oct, es inestable a 0.25 ms con independencia de las claves. El contraste 280→290 cambia a la vez el cambio de claves, el estado físico y el binario que escribió el snapshot.
- **Qué dice el dato que ya existe, a 1 ms:** apoya a las claves.
  - judge_fh_275 pasa liso por 280000 (72 m/s, 15 kPa).
  - scrfh_base reinicia de 280 s con las claves apagadas y queda liso (72/15).
  - scrfh_b difiere de scrfh_base solo en f28 = true y da 160/65 y 190/62.
  - m203_280 y m21f1_280 (solo f28) reproducen la serie de judge_otp_280.
  - El reporte no cita nada de esto.
- **A 0.25 ms no hay discriminador.**
- **Dato que las separa:** 0.25 ms desde judge_fh_275/eaf3d_00290000.h5 con las claves encendidas.
- **Ojo:** judge_otp_280/eaf3d_00280000.h5 no es el archivo de fh_275. El restart es idéntico, pero S_arc, G_rad, S_rad, F_lorentz, S_chem y S_CO_src difieren: el binario del 22-oct recalculó las fuentes de arco y de radiación con otro valor.

**C2. «Amplificado al bajar dt»; se corrige en un número de pasos.**
- **Alternativa:** con 0.25 ms se entra en un régimen alto persistente.
- **Qué dicen los datos:** contradicen la lectura del reporte.
  - k10b_dt025, pasos con p_max >= 100 kPa por cuartos: 31, 21, 32 y 33 de 58.
  - 592 kPa en el paso 280161 (+40 ms); u = 229 m/s en el tercer cuarto.
  - Con 1 ms se asienta en unos 25 pasos; con 0.5 ms decae (8, 1, 2, 0).
- **Además, la amplificación con dt existe también desde 290 s:** el máximo de los pasos 2-10 es 55, 71 y 79 kPa con 1, 0.5 y 0.25 ms, y crece la alternancia par/impar.

**C3. Desde 290 s, el banco de 0.25 ms no se acerca a la centinela.**
- Vale para u_gas (129 m/s).
- Pero p_max llega a 450 kPa (paso 290093) y a 344 kPa (290074). Es el 90 % de regime_p y casi igual a los 461 kPa del evento que se explica. Está en C-230 y no aparece en el reporte.

**C4. La config de B1 no tiene el pico desde 290 s (C-233).**
- Se verificó: k11_base_s290 reproduce la serie continua de judge_otp_280.
- Una sola trayectoria a 1 ms.

**C5. Descartes de comp_carry y de la demanda 1/dt (C-228), y H12 refutada (C-225).**
- Verificados. El escalado con dt se cumple también paso a paso en los pasos 1-5.

### 2. ¿Repite fracasos registrados?
No. Es un diagnóstico sin cambios en src/. H12 (Tg_end) no repite A3-3 ni ninguna refutada. Sí hay un roce con la regla de acople-pv.md:279 (dinámica caótica, régimen con varias trayectorias): el contraste de toda la ventana es de una sola trayectoria por condición (O4).

### 3. Objeciones
- **O1 (bloqueante).** La atribución a las claves está confundida con el estado de 280 s y con el binario. Para resolverla: citar los datos de 1 ms (scrfh_base/scrfh_b, judge_fh_275, m203_280) y, o bien acotar la conclusión, o bien correr 0.25 ms desde judge_fh_275/eaf3d_00290000.h5 con las claves encendidas (o desde fh_275/280 con las claves en false explícito).
- **O2 (bloqueante).** «Transitorio de 2-3 pasos» lo contradicen los cuartos de k10b_dt025: no decae y el máximo de 592 kPa llega a +40 ms. Hay que retirar la lectura de «número de pasos» y corregir .claude/rules/transporte-energia.md:362. Para decidir entre transitorio largo y régimen persistente: prolongar k10b_dt025 (por ejemplo hasta 280.3 s) o usar el discriminador de O1.
- **O3 (bloqueante).** Falta el máximo de toda la ventana de k11_dt025_s290 (450 kPa, 129 m/s), y «amplificado al bajar dt» no es exclusivo del cambio de claves. Lo específico de 280 s es u = 300 y la persistencia del régimen alto.
- **O4.** Contraste de régimen con una sola trayectoria. Para resolverlo: réplicas a 14 ranks con el criterio de régimen acotado, o declararlo en el reporte.
- **O5.** Dos incertidumbres se reducen con datos que ya existen. A 1 ms, f28 sola explica el transitorio (scrfh_b; m203_280 idéntico a judge_otp_280). El cambio de binario no se ve en 290 s (k11_base_s290 coincide con la serie continua). La oscilación 122/77 es la alternancia que ya tiene la corrida continua (107/91).
- **O6.** Fechas y procedencia: 8f568fc es del 22-oct 02:56, no del 21-oct. El archivo de 280 s lo reescribió judge_otp_280 (con el mismo restart y las fuentes recalculadas).

VEREDICTO: rechaza