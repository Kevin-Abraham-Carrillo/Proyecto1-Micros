;***************************************************************************************************************
; Universidad del Valle de Guatemala
; IE2023: Programacion de Microcontroladores
; Test.asm
; Author : Kevin Carrillo
; LAB2-Micros.asm
; Hardware: ATMega328P
; Created: 8/02/2026 21:00:22
; Proyecto1-Reloj-Micros.asm
; Created: 22/02/2026 14:38:54

;*********************************************
; RELOJ DIGITAL CON ALARMA
; Microcontrolador: ATmega328P
; Descripcion:
;   - Reloj HH:MM con display 7 segmentos x4
;   - Calendario DD:MM
;   - Alarma con fecha y hora configurable
;   - Buzzer activo en PC4 (A4)
;   - 5 botones: MODE, NEXT, UP, DOWN, OK
;*********************************************

;*********************************************
; MODOS DE OPERACION
;   Modo 0: Mostrar hora normal
;   Modo 1: Mostrar fecha
;   Modo 2: Configurar hora
;   Modo 3: Configurar fecha
;   Modo 4: Configurar alarma
;*********************************************

;*********************************************
; MAPA DE PINES
;   PORTD (PD0-PD6): Segmentos A-G del display
;   PORTD (PD7)    : Punto decimal DP (parpadeo segundos)
;   PORTC (PC0-PC3): Seleccion de digito 1-4
;   PORTC (PC4)    : Buzzer alarma
;   PORTB (PB0)    : Boton MODE  (D8)
;   PORTB (PB1)    : Boton NEXT  (D9)
;   PORTB (PB2)    : Boton UP    (D10)
;   PORTB (PB3)    : Boton DOWN  (D11)
;   PORTB (PB4)    : Boton OK    (D12)
;*********************************************

.include "m328pdef.inc"

;*********************************************
; VARIABLES EN SRAM
;*********************************************
.dseg

; -- Digitos del display --
digito1:        .byte 1
digito2:        .byte 1
digito3:        .byte 1
digito4:        .byte 1

; -- Tiempo actual --
segundos:       .byte 1
minutos:        .byte 1
horas:          .byte 1

; -- Fecha actual --
dia:            .byte 1
mes:            .byte 1

; -- Control de interfaz --
modo:           .byte 1         ; modo activo (0-4)
campo:          .byte 1         ; campo seleccionado dentro del modo

; -- Control de display --
blink:          .byte 1         ; bandera parpadeo 500ms (0/1)
tick_500:       .byte 1         ; contador para generar 1 segundo

; -- Control de botones --
last_pinb:      .byte 1         ; estado anterior de PORTB
debounce_timer: .byte 1         ; contador de debounce
boton_guardado: .byte 1         ; boton detectado esperando confirmacion

; -- Alarma --
alarm_h:        .byte 1         ; hora de alarma
alarm_m:        .byte 1         ; minuto de alarma
alarm_d:        .byte 1         ; dia de alarma
alarm_mes:      .byte 1         ; mes de alarma
alarm_on:       .byte 1         ; alarma habilitada (0/1)
alarm_ring:     .byte 1         ; alarma sonando actualmente (0/1)


;*********************************************
; VECTORES DE INTERRUPCION
;*********************************************
.cseg
.org 0x0000
    RJMP main                   ; Reset

.org 0x0006
    RJMP PCINT0_ISR             ; Interrupcion botones PORTB

.org 0x0016
    RJMP TIMER1_COMPA_ISR       ; Interrupcion Timer1 cada 500ms


;*********************************************
; TABLA DE CODIGOS 7 SEGMENTOS (0-9)
; Formato: segmentos GFEDCBA activos en alto
;*********************************************
TABLA:
    .DB 0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F
    ;   0     1     2   3     4    5    6   7    8    9


;*********************************************
; CONSTANTES DE SELECCION DE DIGITOS
; 0 = digito activo (catodo comun activo bajo)
;*********************************************
.equ DIG1 = 0b00001110          ; PC0=0 activa digito 1
.equ DIG2 = 0b00001101          ; PC1=0 activa digito 2
.equ DIG3 = 0b00001011          ; PC2=0 activa digito 3
.equ DIG4 = 0b00000111          ; PC3=0 activa digito 4


;*********************************************
; INICIO DEL PROGRAMA PRINCIPAL
;*********************************************
main:

;---------------------------------------------
; CONFIGURACION DEL STACK
;---------------------------------------------
    LDI R16,LOW(RAMEND)
    OUT SPL,R16
    LDI R16,HIGH(RAMEND)
    OUT SPH,R16

;---------------------------------------------
; CONFIGURACION DE PUERTOS
;---------------------------------------------

    ; PORTD: Segmentos A-G + DP — todo salida
    LDI R16,0xFF
    OUT DDRD,R16
    CLR R16
    OUT PORTD,R16

    ; PORTC: PC0-PC3 digitos, PC4 buzzer, PC5 libre — todo salida
    LDI R16,0b00111111
    OUT DDRC,R16
    CLR R16
    OUT PORTC,R16

    ; PORTB: Botones MODE/NEXT/UP/DOWN/OK — todo entrada sin pullup
    CLR R16
    OUT DDRB,R16
    CLR R16
    OUT PORTB,R16

;---------------------------------------------
; CONFIGURACION DE INTERRUPCIONES DE BOTONES
; PCINT0: PB0-PB4 (D8-D12)
;---------------------------------------------
    LDI R16,(1<<PCIE0)
    STS PCICR,R16

    LDI R16,0b00011111          ; habilitar PB0-PB4
    STS PCMSK0,R16

    IN R16,PINB
    STS last_pinb,R16

;---------------------------------------------
; INICIALIZACION DE VARIABLES
;---------------------------------------------

    ; Tiempo en cero
    CLR R16
    STS segundos,R16
    STS minutos,R16
    STS horas,R16

    ; Control de display en cero
    STS blink,R16
    STS tick_500,R16

    ; Interfaz en cero
    STS modo,R16
    STS campo,R16

    ; Fecha inicial: dia 1, mes 1
    LDI R16,1
    STS dia,R16
    STS mes,R16

    ; Alarma en cero
    CLR R16
    STS alarm_h,R16
    STS alarm_m,R16

    ; Fecha alarma inicial: dia 1, mes 1
    LDI R16,1
    STS alarm_d,R16
    STS alarm_mes,R16

    ; Alarma desactivada
    CLR R16
    STS alarm_on,R16
    STS alarm_ring,R16

;---------------------------------------------
; CONFIGURACION TIMER1 — CTC, 500ms
; Fosc=16MHz, prescaler=1024
; OCR1A = 16000000 / (1024 * 2) - 1 = 7812
;---------------------------------------------
    CLR R16
    STS TCCR1A,R16
    STS TCCR1B,R16
    STS TCNT1H,R16
    STS TCNT1L,R16

    LDI R16,HIGH(7812)
    STS OCR1AH,R16
    LDI R16,LOW(7812)
    STS OCR1AL,R16

    LDI R16,(1<<OCIE1A)         ; habilitar interrupcion comparacion
    STS TIMSK1,R16

    LDI R16,0x0D                ; CTC + prescaler 1024
    STS TCCR1B,R16

    SEI                         ; habilitar interrupciones globales


;*********************************************
; LOOP PRINCIPAL
;*********************************************
loop:

;---------------------------------------------
; PASO 1: Liberar debounce si botones sueltos
;---------------------------------------------
    IN   R16, PINB
    ANDI R16, 0x1F              ; solo PB0-PB4

    CPI  R16, 0x1F              ; todos en alto = sueltos
    BRNE revisar_debounce

    CLR  R16
    STS  boton_guardado, R16    ; limpiar boton guardado

revisar_debounce:

;---------------------------------------------
; PASO 2: Contador de debounce
;---------------------------------------------
    LDS  R16, debounce_timer
    CPI  R16, 0
    BREQ continuar_loop

    DEC  R16
    STS  debounce_timer, R16

    CPI  R16, 0
    BRNE continuar_loop

    RCALL ejecutar_boton_guardado   ; ejecutar accion confirmada

continuar_loop:

;---------------------------------------------
; PASO 3: Seleccion de pantalla segun modo
;---------------------------------------------
    LDS R16,modo

    CPI R16,1
    BREQ mostrar_fecha          ; modo 1: fecha actual

    CPI R16,3
    BREQ mostrar_fecha          ; modo 3: config fecha (muestra fecha)

    CPI R16,4
    BREQ mostrar_alarma         ; modo 4: config alarma

    RJMP mostrar_hora           ; modo 0 y 2: mostrar hora


;---------------------------------------------
; PANTALLA: ALARMA
; campo 0-1: hora alarma | campo 2-3: fecha alarma
;---------------------------------------------
mostrar_alarma:
    LDS R16,campo
    CPI R16,2
    BRSH mostrar_fecha_alarma

    LDS R16,alarm_h
    RCALL separar_2dig
    STS digito2,R16
    STS digito1,R17

    LDS R16,alarm_m
    RCALL separar_2dig
    STS digito4,R16
    STS digito3,R17

    RJMP continuar_display

mostrar_fecha_alarma:
    LDS R16,alarm_d
    RCALL separar_2dig
    STS digito2,R16
    STS digito1,R17

    LDS R16,alarm_mes
    RCALL separar_2dig
    STS digito4,R16
    STS digito3,R17

    RJMP continuar_display


;---------------------------------------------
; PANTALLA: HORA ACTUAL (HH:MM)
;---------------------------------------------
mostrar_hora:
    LDS R16,minutos
    RCALL separar_2dig
    STS digito4,R16
    STS digito3,R17

    LDS R16,horas
    RCALL separar_2dig
    STS digito2,R16
    STS digito1,R17

    RJMP continuar_display


;---------------------------------------------
; PANTALLA: FECHA ACTUAL (DD:MM)
;---------------------------------------------
mostrar_fecha:
    LDS R16,dia
    RCALL separar_2dig
    STS digito2,R16             ; unidades dia
    STS digito1,R17             ; decenas dia

    LDS R16,mes
    RCALL separar_2dig
    STS digito4,R16             ; unidades mes
    STS digito3,R17             ; decenas mes

    RJMP continuar_display


;*********************************************
; MULTIPLEXADO DE DISPLAY
; Cicla los 4 digitos rapidamente
; Preserva PC4 (buzzer) en cada escritura
;*********************************************
continuar_display:

; --- DIGITO 1 ---
IN  R16, PORTC
ORI R16, 0x0F                   ; apagar todos los digitos, preservar PC4
OUT PORTC, R16
LDI R19,1
LDS R18,digito1
RCALL cargar_tabla
RCALL aplicar_parpadeo
RCALL aplicar_blink
IN  R17,PORTD
ANDI R17,0b10000000             ; conservar PD7 (DP)
MOV R18,R16
ANDI R18,0b01111111             ; solo segmentos A-G
OR  R17,R18
OUT PORTD,R17
IN  R16, PORTC
ANDI R16, 0b00010000            ; conservar PC4 (buzzer)
ORI R16, DIG1
OUT PORTC, R16
RCALL delay_pequeno

; --- DIGITO 2 ---
IN  R16, PORTC
ORI R16, 0x0F
OUT PORTC, R16
LDI R19,2
LDS R18,digito2
RCALL cargar_tabla
RCALL aplicar_parpadeo
RCALL aplicar_blink
IN  R17,PORTD
ANDI R17,0b10000000
MOV R18,R16
ANDI R18,0b01111111
OR  R17,R18
OUT PORTD,R17
IN  R16, PORTC
ANDI R16, 0b00010000
ORI R16, DIG2
OUT PORTC, R16
RCALL delay_pequeno

; --- DIGITO 3 ---
IN  R16, PORTC
ORI R16, 0x0F
OUT PORTC, R16
LDI R19,3
LDS R18,digito3
RCALL cargar_tabla
RCALL aplicar_parpadeo
RCALL aplicar_blink
IN  R17,PORTD
ANDI R17,0b10000000
MOV R18,R16
ANDI R18,0b01111111
OR  R17,R18
OUT PORTD,R17
IN  R16, PORTC
ANDI R16, 0b00010000
ORI R16, DIG3
OUT PORTC, R16
RCALL delay_pequeno

; --- DIGITO 4 ---
IN  R16, PORTC
ORI R16, 0x0F
OUT PORTC, R16
LDI R19,4
LDS R18,digito4
RCALL cargar_tabla
RCALL aplicar_parpadeo
RCALL aplicar_blink
IN  R17,PORTD
ANDI R17,0b10000000
MOV R18,R16
ANDI R18,0b01111111
OR  R17,R18
OUT PORTD,R17
IN  R16, PORTC
ANDI R16, 0b00010000
ORI R16, DIG4
OUT PORTC, R16
RCALL delay_pequeno

RJMP loop


;*********************************************
; SUBRUTINAS DE DISPLAY
;*********************************************

; Separa un numero en decenas (R17) y unidades (R16)
separar_2dig:
    CLR R17
sep10:
    CPI R16,10
    BRLO finsep
    SUBI R16,10
    INC R17
    RJMP sep10
finsep:
    RET

; Carga el codigo 7 segmentos del digito en R18 desde TABLA
cargar_tabla:
    LDI ZL,LOW(TABLA<<1)
    LDI ZH,HIGH(TABLA<<1)
    ADD ZL,R18
    CLR R18
    ADC ZH,R18
    LPM R16,Z
    RET

; Controla el punto decimal PD7 segun blink (parpadeo de segundos)
aplicar_blink:
    LDS R17,blink
    CPI R17,1
    BRNE no_dp
    SBI PORTD,7
    RET
no_dp:
    CBI PORTD,7
    RET

; Apaga el digito activo si esta en modo config y es el campo seleccionado
aplicar_parpadeo:
    LDS R17,modo
    CPI R17,2
    BREQ cfg
    CPI R17,3
    BREQ cfg
    CPI R17,4
    BREQ cfg
    RET
cfg:
    LDS R17,blink
    CPI R17,0
    BREQ finp
    LDS R17,campo
    CPI R17,0
    BREQ izq
    CPI R19,3
    BREQ apagar
    CPI R19,4
    BREQ apagar
    RET
izq:
    CPI R19,1
    BREQ apagar
    CPI R19,2
    BREQ apagar
    RET
apagar:
    CLR R16
finp:
    RET

; Delay corto para multiplexado (~1ms)
delay_pequeno:
    LDI R20,1
d1:
    LDI R21,200
d2:
    DEC R21
    BRNE d2
    DEC R20
    BRNE d1
    RET


;*********************************************
; MANEJO DE BOTONES
;*********************************************

; Despacha la accion del boton guardado
; Si la alarma esta sonando, cualquier boton la apaga
ejecutar_boton_guardado:
    LDS R16, alarm_ring
    CPI R16, 1
    BRNE no_apagar_ring
    RJMP apagar_alarma_ring

no_apagar_ring:
    LDS R16, boton_guardado

    CPI R16,1
    BREQ ejecutar_mode

    CPI R16,2
    BREQ ejecutar_next

    CPI R16,3
    BREQ ejecutar_up

    CPI R16,4
    BREQ ejecutar_down

    CPI R16,5
    BREQ ejecutar_ok

    RET

ejecutar_mode:
    RCALL accion_mode
    RET

ejecutar_next:
    RCALL accion_next
    RET

ejecutar_up:
    RCALL accion_up
    RET

ejecutar_down:
    RCALL accion_down
    RET

ejecutar_ok:
    RCALL accion_ok
    RET


;*********************************************
; ISR TIMER1 — Ejecuta cada 500ms
; Controla: blink, contador de segundos,
;           incremento de tiempo/fecha, alarma
;*********************************************
TIMER1_COMPA_ISR:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R30
    PUSH R31
    IN R16,SREG
    PUSH R16

;---------------------------------------------
; Alternar blink cada 500ms
;---------------------------------------------
    LDS R16,blink
    LDI R17,1
    EOR R16,R17
    STS blink,R16

;---------------------------------------------
; Cada 2 ticks = 1 segundo real
;---------------------------------------------
    LDS R16,tick_500
    INC R16
    CPI R16,2
    BRSH continuar_tick
    RJMP solo_guardar_tick

continuar_tick:
    CLR R16
    STS tick_500,R16

;---------------------------------------------
; Incremento de segundos
;---------------------------------------------
    LDS R16,segundos
    INC R16
    CPI R16,60
    BRLO guardar_seg

    CLR R16
    STS segundos,R16

;---------------------------------------------
; Incremento de minutos
;---------------------------------------------
    LDS R17,minutos
    INC R17
    CPI R17,60
    BRLO guardar_min

    CLR R17
    STS minutos,R17

;---------------------------------------------
; Incremento de horas
;---------------------------------------------
    LDS R18,horas
    INC R18
    CPI R18,24
    BRLO guardar_hora

    CLR R18
    STS horas,R18

    RCALL incrementar_dia       ; nuevo dia al llegar a 24h
    RJMP verificar_alarma

guardar_hora:
    STS horas,R18
    RJMP verificar_alarma

guardar_min:
    STS minutos,R17
    RJMP verificar_alarma

guardar_seg:
    STS segundos,R16
    RJMP verificar_alarma

;---------------------------------------------
; Solo guardar tick si no llego al segundo
;---------------------------------------------
solo_guardar_tick:
    STS tick_500,R16
    RJMP salir_timer

;---------------------------------------------
; Verificacion y activacion de alarma
; Se chequea cada segundo con valores actuales
;---------------------------------------------
verificar_alarma:
    ; Si ya esta sonando, mantener buzzer
    LDS R16,alarm_ring
    CPI R16,1
    BREQ sonar_buzzer

    ; Si alarma desactivada, salir
    LDS R16,alarm_on
    CPI R16,1
    BRNE salir_timer

    ; Comparar hora
    LDS R16,horas
    LDS R17,alarm_h
    CP R16,R17
    BRNE salir_timer

    ; Comparar minutos
    LDS R16,minutos
    LDS R17,alarm_m
    CP R16,R17
    BRNE salir_timer

    ; Comparar dia
    LDS R16,dia
    LDS R17,alarm_d
    CP R16,R17
    BRNE salir_timer

    ; Comparar mes
    LDS R16,mes
    LDS R17,alarm_mes
    CP R16,R17
    BRNE salir_timer

    ; Todo coincide: activar alarma
    LDI R16,1
    STS alarm_ring,R16

;---------------------------------------------
; Buzzer 
;---------------------------------------------
sonar_buzzer:
    SBI PORTC, 4        ; buzzer ON continuo
    RJMP salir_timer

salir_timer:
    POP R16
    OUT SREG,R16
    POP R31
    POP R30
    POP R18
    POP R17
    POP R16
    RETI


;*********************************************
; SUBRUTINAS DE CALENDARIO
;*********************************************

; Incrementa el dia y ajusta mes/año si corresponde
incrementar_dia:
    LDS R16,dia
    INC R16
    LDS R17,mes

    CPI R17,2
    BREQ mes_28
    CPI R17,4
    BREQ mes_30
    CPI R17,6
    BREQ mes_30
    CPI R17,9
    BREQ mes_30
    CPI R17,11
    BREQ mes_30

    LDI R17,31
    RJMP validar_dia

mes_28:
    LDI R17,28
    RJMP validar_dia

mes_30:
    LDI R17,30

validar_dia:
    CP R16,R17
    BRLO guardar_dia
    BREQ guardar_dia

    LDI R16,1
    STS dia,R16

    LDS R18,mes
    INC R18
    CPI R18,13
    BRLO guardar_mes
    LDI R18,1

guardar_mes:
    STS mes,R18
    RET

guardar_dia:
    STS dia,R16
    RET

; Retorna en R17 el limite de dias del mes actual
obtener_limite_mes:
    LDS R17,mes
    CPI R17,2
    BREQ limite_28
    CPI R17,4
    BREQ limite_30
    CPI R17,6
    BREQ limite_30
    CPI R17,9
    BREQ limite_30
    CPI R17,11
    BREQ limite_30
    LDI R17,31
    RET
limite_28:
    LDI R17,28
    RET
limite_30:
    LDI R17,30
    RET

; Retorna en R17 el limite de dias del mes de la alarma
obtener_limite_mes_alarma:
    LDS R17,alarm_mes
    CPI R17,2
    BREQ limite_28_a
    CPI R17,4
    BREQ limite_30_a
    CPI R17,6
    BREQ limite_30_a
    CPI R17,9
    BREQ limite_30_a
    CPI R17,11
    BREQ limite_30_a
    LDI R17,31
    RET
limite_28_a:
    LDI R17,28
    RET
limite_30_a:
    LDI R17,30
    RET


;*********************************************
; ISR PCINT0 — Deteccion de botones PB0-PB4
; Guarda el boton presionado y activa debounce
;*********************************************
PCINT0_ISR:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R30
    PUSH R31
    IN   R16,SREG
    PUSH R16

    IN  R16,PINB
    LDS R17,last_pinb
    MOV R18,R16
    EOR R18,R17                 ; detectar cambio de estado
    STS last_pinb,R16

; --- MODE (PB0 - D8) ---
SBRS R18,0
RJMP chk_next
SBRC R16,0
RJMP chk_next
LDI R16,1
STS boton_guardado,R16
LDI R16,5
STS debounce_timer,R16
RJMP salir_pcint

; --- NEXT (PB1 - D9) ---
chk_next:
SBRS R18,1
RJMP chk_up
SBRC R16,1
RJMP chk_up
LDI R16,2
STS boton_guardado,R16
LDI R16,5
STS debounce_timer,R16
RJMP salir_pcint

; --- UP (PB2 - D10) ---
chk_up:
SBRS R18,2
RJMP chk_down
SBRC R16,2
RJMP chk_down
LDI R16,3
STS boton_guardado,R16
LDI R16,5
STS debounce_timer,R16
RJMP salir_pcint

; --- DOWN (PB3 - D11) ---
chk_down:
SBRS R18,3
RJMP chk_ok
SBRC R16,3
RJMP chk_ok
LDI R16,4
STS boton_guardado,R16
LDI R16,5
STS debounce_timer,R16
RJMP salir_pcint

; --- OK (PB4 - D12) ---
chk_ok:
SBRS R18,4
RJMP salir_pcint
SBRC R16,4
RJMP salir_pcint
LDI R16,5
STS boton_guardado,R16
LDI R16,5
STS debounce_timer,R16
RJMP salir_pcint

salir_pcint:
    POP R16
    OUT SREG,R16
    POP R31
    POP R30
    POP R18
    POP R17
    POP R16
    RETI

debounce_exit:
    RET


;*********************************************
; ACCIONES DE BOTONES
;*********************************************

; MODE: avanza al siguiente modo (0 -> 1 -> 2 -> 3 -> 4 -> 0)
accion_mode:
    LDS R16,modo
    INC R16
    CPI R16,5
    BRLO save_mode
    CLR R16
save_mode:
    STS modo,R16
    RET

; NEXT: avanza al siguiente campo dentro del modo actual
accion_next:
    LDS R16,modo

    CPI R16,2
    BREQ next_hora

    CPI R16,3
    BREQ next_fecha

    CPI R16,4
    BREQ next_alarma

    RET

next_hora:
    LDS R16,campo
    INC R16
    CPI R16,2
    BRLO save_field_h
    CLR R16
save_field_h:
    STS campo,R16
    RET

next_fecha:
    LDS R16,campo
    INC R16
    CPI R16,2
    BRLO save_field_f
    CLR R16
save_field_f:
    STS campo,R16
    RET

next_alarma:
    LDS R16,campo
    INC R16
    CPI R16,4
    BRLO save_field_a
    CLR R16
save_field_a:
    STS campo,R16
    RET

; OK: confirma accion segun modo, o apaga alarma si esta sonando
accion_ok:
    LDS R16,alarm_ring
    CPI R16,1
    BREQ apagar_alarma_ring

    LDS R16,modo

    CPI R16,2
    BREQ ok_to_hora

    CPI R16,3
    BREQ ok_to_fecha

    CPI R16,1
    BREQ ok_to_hora

    CPI R16,4
    BREQ activar_alarma_directo

    RET

ok_to_fecha:
    LDI R16,1
    STS modo,R16
    RET

ok_to_hora:
    LDI R16,0
    STS modo,R16
    RET

activar_alarma_directo:
    LDI R16,1
    STS alarm_on,R16
    LDI R16,0
    STS modo,R16
    RET

; Apaga el buzzer y limpia los flags de alarma
apagar_alarma_ring:
    CLR R16
    STS alarm_ring,R16
    STS alarm_on,R16
    CBI PORTC,4
    RET

; UP: incrementa el valor del campo activo
accion_up:
    LDS R16,modo

    CPI R16,2
    BREQ up_hora

    CPI R16,3
    BRNE siguiente_up1
    RJMP up_fecha

siguiente_up1:
    CPI R16,4
    BRNE siguiente_up2
    RJMP up_alarma

siguiente_up2:
    RET

up_alarma:
    LDS R17,campo
    CPI R17,0
    BREQ up_alarm_h
    CPI R17,1
    BREQ up_alarm_m
    CPI R17,2
    BREQ up_alarm_d
    CPI R17,3
    BREQ up_alarm_mes
    RET

up_alarm_h:
    LDS R18,alarm_h
    INC R18
    CPI R18,24
    BRLO save_ah
    CLR R18
save_ah:
    STS alarm_h,R18
    RET

up_alarm_m:
    LDS R18,alarm_m
    INC R18
    CPI R18,60
    BRLO save_am
    CLR R18
save_am:
    STS alarm_m,R18
    RET

up_alarm_d:
    LDS R18,alarm_d
    INC R18
    RCALL obtener_limite_mes_alarma
    CP R18,R17
    BRLO save_ad
    BREQ save_ad
    LDI R18,1
save_ad:
    STS alarm_d,R18
    RET

up_alarm_mes:
    LDS R18,alarm_mes
    INC R18
    CPI R18,13
    BRLO save_ames
    LDI R18,1
save_ames:
    STS alarm_mes,R18
    RET

up_hora:
    LDS R17,campo
    CPI R17,0
    BREQ up_horas

    LDS R18,minutos
    INC R18
    CPI R18,60
    BRLO save_min_up
    CLR R18
save_min_up:
    STS minutos,R18
    RET

up_horas:
    LDS R18,horas
    INC R18
    CPI R18,24
    BRLO save_h_up
    CLR R18
save_h_up:
    STS horas,R18
    RET

up_fecha:
    LDS R17,campo
    CPI R17,0
    BREQ up_dia

    LDS R18,mes
    INC R18
    CPI R18,13
    BRLO save_mes_up
    LDI R18,1
save_mes_up:
    STS mes,R18
    RET

up_dia:
    LDS R18,dia
    INC R18
    RCALL obtener_limite_mes
    CP R18,R17
    BRLO save_dia_up
    BREQ save_dia_up
    LDI R18,1
save_dia_up:
    STS dia,R18
    RET

; DOWN: decrementa el valor del campo activo
accion_down:
    LDS R16,modo

    CPI R16,2
    BRNE chk_down_fecha
    RJMP down_hora

chk_down_fecha:
    CPI R16,3
    BRNE chk_down_alarma
    RJMP down_fecha

chk_down_alarma:
    CPI R16,4
    BRNE fin_down
    RJMP down_alarma

fin_down:
    RET

down_alarma:
    LDS R17,campo
    CPI R17,0
    BREQ down_alarm_h
    CPI R17,1
    BREQ down_alarm_m
    CPI R17,2
    BREQ down_alarm_d
    CPI R17,3
    BREQ down_alarm_mes
    RET

down_alarm_h:
    LDS R18,alarm_h
    CPI R18,0
    BRNE dec_ah
    LDI R18,23
    RJMP save_ah_d
dec_ah:
    DEC R18
save_ah_d:
    STS alarm_h,R18
    RET

down_alarm_m:
    LDS R18,alarm_m
    CPI R18,0
    BRNE dec_am
    LDI R18,59
    RJMP save_am_d
dec_am:
    DEC R18
save_am_d:
    STS alarm_m,R18
    RET

down_alarm_d:
    LDS R18,alarm_d
    CPI R18,1
    BRNE dec_ad
    RCALL obtener_limite_mes_alarma
    MOV R18,R17
    RJMP save_ad_d
dec_ad:
    DEC R18
save_ad_d:
    STS alarm_d,R18
    RET

down_alarm_mes:
    LDS R18,alarm_mes
    CPI R18,1
    BRNE dec_ames
    LDI R18,12
    RJMP save_ames_d
dec_ames:
    DEC R18
save_ames_d:
    STS alarm_mes,R18
    RET

down_hora:
    LDS R17,campo
    CPI R17,0
    BREQ down_horas

    LDS R18,minutos
    CPI R18,0
    BRNE dec_min
    LDI R18,59
    RJMP save_min_down
dec_min:
    DEC R18
save_min_down:
    STS minutos,R18
    RET

down_horas:
    LDS R18,horas
    CPI R18,0
    BRNE dec_h
    LDI R18,23
    RJMP save_h_down
dec_h:
    DEC R18
save_h_down:
    STS horas,R18
    RET

down_fecha:
    LDS R17,campo
    CPI R17,0
    BREQ down_dia

    LDS R18,mes
    CPI R18,1
    BRNE dec_mes
    LDI R18,12
    RJMP save_mes_down
dec_mes:
    DEC R18
save_mes_down:
    STS mes,R18
    RET

down_dia:
    LDS R18,dia
    CPI R18,1
    BRNE dec_d
    RCALL obtener_limite_mes
    MOV R18,R17
    RJMP save_dia_down
dec_d:
    DEC R18
save_dia_down:
    STS dia,R18
    RET


	;FIN