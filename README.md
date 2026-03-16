# Reloj Digital en Assembler — ATmega328P

Reloj digital programado en Assembler puro para el microcontrolador ATmega328P (Arduino Nano), sin librerías externas. Incluye visualización de hora y fecha, configuración mediante botones y alarma con buzzer activo.

---

## Características

- Display de 4 dígitos de 7 segmentos multiplexado
- Visualización de hora (HH:MM) y fecha (DD:MM)
- 5 modos de operación navegables con botones
- Alarma configurable por hora, minutos, día y mes
- Buzzer activo en PC4 (A4)
- Parpadeo del punto decimal como indicador de segundos
- Debounce por software en todos los botones

---

## Hardware utilizado

| Componente | Descripción |
|---|---|
| Arduino Nano | ATmega328P a 16MHz |
| Display 7 segmentos x4 | Cátodo común |
| Buzzer activo | 5V, conectado a PC4 (A4) |
| Botones x5 | Con resistencia pull-up 10kΩ a 5V |
| Resistencias 220Ω x8 | Una por segmento del display (A-G + DP) |

---

## Mapa de pines

| Pin Arduino | Puerto | Función |
|---|---|---|
| D0 – D7 | PD0 – PD7 | Segmentos A-G + DP del display |
| A0 – A3 | PC0 – PC3 | Selección de dígito 1-4 |
| A4 | PC4 | Buzzer alarma |
| D8 | PB0 | Botón MODE |
| D9 | PB1 | Botón NEXT |
| D10 | PB2 | Botón UP |
| D11 | PB3 | Botón DOWN |
| D12 | PB4 | Botón OK |

---

## Modos de operación

| Modo | Función |
|---|---|
| 0 | Mostrar hora normal |
| 1 | Mostrar fecha |
| 2 | Configurar hora |
| 3 | Configurar fecha |
| 4 | Configurar alarma |

### Navegación
- **MODE** — cicla entre modos 0 → 1 → 2 → 3 → 4 → 0
- **NEXT** — cambia el campo activo dentro del modo
- **UP / DOWN** — incrementa o decrementa el valor del campo
- **OK** — confirma y regresa al modo anterior
- **Cualquier botón** — apaga la alarma si está sonando

---

## Funcionamiento del Timer ISR

El Timer1 se configura en modo CTC con prescaler 1024 y OCR1A = 7812, generando una interrupción cada 500ms con un cristal de 16MHz.

```
f_interrupcion = 16,000,000 / (1024 × (7812 + 1)) ≈ 2 Hz → 500ms
```

Cada 2 interrupciones = 1 segundo real. La ISR también maneja el parpadeo del display y la verificación de la alarma.

---

## Estructura del código

```
main.asm
│
├── Variables SRAM          — digitos, tiempo, fecha, alarma, control
├── Vectores                — Reset, PCINT0, Timer1
├── Tabla 7 segmentos       — Códigos para dígitos 0-9
├── Main                    — Configuración de puertos, timer e interrupciones
├── Loop principal          — Debounce, selección de pantalla, multiplexado
├── ISR Timer1              — Blink, contador de segundos, verificación alarma
├── ISR PCINT0              — Detección de botones con debounce
├── Subrutinas de display   — separar_2dig, cargar_tabla, aplicar_blink, aplicar_parpadeo
├── Subrutinas de calendario — incrementar_dia, obtener_limite_mes
└── Acciones de botones     — accion_mode, next, up, down, ok
```

---

## Cómo compilar y cargar

1. Abrir el proyecto en **Microchip Studio**
2. Compilar con **Build → Build Solution** (F7)
3. Conectar el Arduino Nano por USB
4. Cargar con **Tools → Device Programming** o usando avrdude:

```bash
avrdude -c arduino -p m328p -P COMx -b 57600 -U flash:w:main.hex
```

> Reemplaza `COMx` con el puerto correspondiente (ej. COM3 en Windows, /dev/ttyUSB0 en Linux)

---

## Desarrollado con

- [Microchip Studio](https://www.microchip.com/en-us/tools-resources/develop/microchip-studio) — IDE para desarrollo en Assembler/C para AVR
- AVR Assembler — lenguaje ensamblador para ATmega328P

---

## Autor
Kevin Abraham Carrillo Lopez - 231058

Proyecto desarrollado como práctica de microcontroladores en Assembler puro para el ATmega328P.
