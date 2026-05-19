@ =============================================================================
@ coprocessor_api.s — Biblioteca de controle do Coprocessador ELM
@ Disciplina: TEC499 - Sistemas Digitais, UEFS 2026.1
@
@ Funções exportadas:
@   coprocessor_init    — Abre /dev/mem e mapeia ponte LW
@   coprocessor_reset   — Reseta o coprocessador (rst via pio_signals[2])
@   coprocessor_clear   — Limpa flags e volta ao IDLE (clr via pio_signals[1])
@   send_image          — Envia 784 pixels (opcode 000)
@   send_weights        — Envia pesos addr+value (opcodes 001 e 010)
@   send_bias           — Envia bias (opcode 011)
@   send_beta           — Envia beta (opcode 100)
@   send_start          — Envia comando Start (opcode 101)
@   wait_done           — Polling até Done (bit 4 do data_out) = 1
@   read_result         — Lê dígito predito (bits 3:0 do data_out)
@   coprocessor_close   — Desmapeia memória e fecha /dev/mem
@
@ Mapa de PIOs (base = 0xFF200000):
@   [base + 0x00]  pio_data_out — leitura do resultado
@   [base + 0x10]  pio_signals  — bit0=enable, bit1=clr_operation, bit2=rst
@   [base + 0x20]  pio_data_in  — instrução para o coprocessador
@
@ Formato do data_out:
@   bits[3:0] = dígito predito (0-9)
@   bit[4]    = Done
@   bit[5]    = Busy
@   bit[6]    = Error
@
@ ISA completa:
@   inst img   (000): [31:21]nu [20:13]dado(8b)    [12:3]addr(10b) [2:0]op
@   inst addr  (001): [31:20]nu [19:3]addr(17b)                    [2:0]op
@   inst value (010): [31:19]nu [18:3]dado(16b Q4.12)              [2:0]op
@   inst bias  (011): [31:26]nu [25:10]dado(16b Q4.12) [9:3]addr(7b) [2:0]op
@   inst beta  (100): [31:30]nu [29:14]dado(16b Q4.12) [13:3]addr(11b) [2:0]op
@   inst start (101): [31:3]nu                         [2:0]op
@
@ Sobre Q4.12:
@   Os dados de weights, bias e beta são inteiros de 16 bits no formato Q4.12
@   (4 bits inteiros + 12 bits fracionários). Em Assembly tratamos como
@   inteiros de 16 bits normais usando ldrh — sem conversão necessária.
@   O coprocessador interpreta Q4.12 internamente.
@ =============================================================================

.section .data
    .dev_mem_path:  .asciz "/dev/mem"
    FPGA_BASE:      .word 0     @ Endereço virtual base após mmap
    DEV_MEM_FD:     .word 0     @ File descriptor do /dev/mem

@ Offsets dos PIOs em relação à base mapeada
.equ PIO_DATA_OUT, 0x00     @ Leitura de resultado/status
.equ PIO_SIGNALS,  0x10     @ Controle: enable(0), clr(1), rst(2)
.equ PIO_DATA_IN,  0x20     @ Instrução enviada ao coprocessador

@ Bits do pio_signals
.equ BIT_ENABLE,   0        @ bit 0
.equ BIT_CLR,      1        @ bit 1 — clr_operation
.equ BIT_RST,      2        @ bit 2 — rst

@ Bits do pio_data_out
.equ BIT_DONE,     4        @ bit 4
.equ BIT_BUSY,     5        @ bit 5
.equ BIT_ERROR,    6        @ bit 6

@ Opcodes da ISA
.equ OP_IMG,       0b000    @ 0
.equ OP_ADDR,      0b001    @ 1
.equ OP_VALUE,     0b010    @ 2
.equ OP_BIAS,      0b011    @ 3
.equ OP_BETA,      0b100    @ 4
.equ OP_START,     0b101    @ 5

@ Parâmetros do mmap
.equ MMAP_SIZE,    4096
.equ PROT_RW,      3        @ PROT_READ | PROT_WRITE
.equ MAP_SHARED,   1
.equ LW_BRIDGE,    0xFF200000

.section .text
.global coprocessor_init
.global coprocessor_reset
.global coprocessor_clear
.global send_image
.global send_weights
.global send_bias
.global send_beta
.global send_start
.global wait_done
.global read_result
.global coprocessor_close

@ =============================================================================
@ Macro auxiliar: envia pulso de enable no pio_signals
@ Usa r_base como ponteiro da base, r_tmp como registrador temporário
@ =============================================================================
.macro pulse_enable r_base, r_tmp
    mov     \r_tmp, #1
    str     \r_tmp, [\r_base, #PIO_SIGNALS]
    mov     \r_tmp, #0
    str     \r_tmp, [\r_base, #PIO_SIGNALS]
.endm

@ =============================================================================
@ coprocessor_init
@   Abre /dev/mem e mapeia a ponte LW em espaço de usuário.
@
@   Parâmetros: nenhum
@   Retorno:
@     r0 =  0  sucesso (FPGA_BASE e DEV_MEM_FD gravados em .data)
@     r0 = -1  falha ao abrir /dev/mem
@     r0 = -2  falha no mmap
@
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
coprocessor_init:
    push    {r4, r5, lr}

    @ --- open("/dev/mem", O_RDWR | O_SYNC) ---
    mov     r7, #5                  @ syscall: open
    ldr     r0, =.dev_mem_path
    ldr     r1, =0x101002           @ O_RDWR | O_SYNC
    svc     0
    cmp     r0, #0
    blt     .init_fail_open
    mov     r4, r0                  @ r4 = fd

    @ Salva fd em DEV_MEM_FD
    ldr     r5, =DEV_MEM_FD
    str     r4, [r5]

    @ --- mmap2(NULL, 4096, PROT_RW, MAP_SHARED, fd, offset_pages) ---
    @ ARM Linux mmap2: todos os 6 argumentos em r0-r5, sem uso da pilha.
    @ Ordem: r0=addr, r1=length, r2=prot, r3=flags, r4=fd, r5=offset(páginas)
    @ Offset físico em páginas de 4KB: 0xFF200000 >> 12 = 0xFF200
    mov     r5, r4                  @ salva fd temporariamente em r5
    mov     r7, #192                @ syscall: mmap2
    mov     r0, #0                  @ r0 = addr   (NULL)
    mov     r1, #MMAP_SIZE          @ r1 = length (4096)
    mov     r2, #PROT_RW            @ r2 = prot   (PROT_READ|PROT_WRITE)
    mov     r3, #MAP_SHARED         @ r3 = flags  (MAP_SHARED)
    mov     r4, r5                  @ r4 = fd
    ldr     r5, =0xFF200            @ r5 = offset em páginas de 4KB
    svc     0
    @ MAP_FAILED = 0xFFFFFFFF — qualquer valor >= 0xF0000000 indica erro
    ldr     r1, =0xF0000000
    cmp     r0, r1
    bhs     .init_fail_mmap

    @ Salva base virtual em FPGA_BASE
    ldr     r5, =FPGA_BASE
    str     r0, [r5]

    mov     r0, #0                  @ retorno: sucesso
    pop     {r4, r5, pc}

.init_fail_open:
    mov     r0, #-1
    pop     {r4, r5, pc}

.init_fail_mmap:
    @ Fecha fd antes de retornar erro
    mov     r7, #6                  @ syscall: close
    mov     r0, r4
    svc     0
    mov     r0, #-2
    pop     {r4, r5, pc}

@ =============================================================================
@ coprocessor_reset
@   Aplica pulso de reset no coprocessador (bit 2 de pio_signals).
@   Sequência: rst=1 → rst=0.
@
@   Parâmetros: nenhum
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
coprocessor_reset:
    push    {r4, lr}

    ldr     r4, =FPGA_BASE
    ldr     r4, [r4]                @ r4 = base virtual

    mov     r0, #(1 << BIT_RST)    @ rst = 1
    str     r0, [r4, #PIO_SIGNALS]
    mov     r0, #0                  @ rst = 0
    str     r0, [r4, #PIO_SIGNALS]

    pop     {r4, pc}

@ =============================================================================
@ coprocessor_clear
@   Limpa flags do coprocessador e retorna ao estado IDLE (bit 1 de pio_signals).
@   Sequência: clr=1 → clr=0.
@
@   Parâmetros: nenhum
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
coprocessor_clear:
    push    {r4, lr}

    ldr     r4, =FPGA_BASE
    ldr     r4, [r4]

    mov     r0, #(1 << BIT_CLR)    @ clr = 1
    str     r0, [r4, #PIO_SIGNALS]
    mov     r0, #0                  @ clr = 0
    str     r0, [r4, #PIO_SIGNALS]

    pop     {r4, pc}

@ =============================================================================
@ send_image
@   Envia 784 pixels ao coprocessador usando opcode 000 (OP_IMG).
@
@   Formato da instrução IMG:
@     bits[31:21] = não usados
@     bits[20:13] = dado (pixel, 8 bits)
@     bits[12:3]  = endereço (0–783, 10 bits usados de 10)
@     bits[2:0]   = opcode (000)
@
@   Parâmetros:
@     r0 = ponteiro para o buffer de imagem (784 bytes)
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
send_image:
    push    {r4, r5, r6, r7, lr}

    mov     r4, r0                  @ r4 = ponteiro buffer

    ldr     r5, =FPGA_BASE
    ldr     r5, [r5]                @ r5 = base virtual

    mov     r6, #0                  @ r6 = contador (0..783)

.send_img_loop:
    ldrb    r0, [r4], #1            @ r0 = pixel (pós-incrementa ponteiro)

    @ Monta instrução: dado(8b) << 13 | addr(10b) << 3 | OP_IMG(000)
    lsl     r1, r0, #13             @ bits[20:13] = pixel
    lsl     r2, r6, #3              @ bits[12:3]  = endereço
    orr     r2, r1, r2              @ combina (opcode 000 = 0, sem OR extra)

    str     r2, [r5, #PIO_DATA_IN]  @ envia instrução
    pulse_enable r5, r0             @ pulso de enable

    add     r6, r6, #1
    cmp     r6, #784
    blt     .send_img_loop

    pop     {r4, r5, r6, r7, pc}

@ =============================================================================
@ send_weights
@   Envia um par (endereço, valor) de peso ao coprocessador.
@   Usa dois ciclos: opcode 001 (OP_ADDR) seguido de opcode 010 (OP_VALUE).
@
@   Formato OP_ADDR (001):
@     bits[31:20] = não usados
@     bits[19:3]  = endereço (17 bits)
@     bits[2:0]   = opcode (001)
@
@   Formato OP_VALUE (010):
@     bits[31:19] = não usados
@     bits[18:3]  = dado Q4.12 (16 bits)
@     bits[2:0]   = opcode (010)
@
@   Parâmetros:
@     r0 = endereço do peso (17 bits)
@     r1 = valor do peso (16 bits Q4.12, tratado como inteiro)
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
send_weights:
    push    {r4, r5, lr}

    mov     r4, r0                  @ r4 = endereço
    mov     r5, r1                  @ r5 = valor
    rev16   r5, r5

    ldr     r0, =FPGA_BASE
    ldr     r0, [r0]                @ r0 = base virtual

    @ --- Instrução ADDR (001) ---
    lsl     r2, r4, #3              @ bits[19:3] = endereço
    orr     r2, r2, #OP_ADDR        @ bits[2:0]  = 001
    str     r2, [r0, #PIO_DATA_IN]
    pulse_enable r0, r3

    @ --- Instrução VALUE (010) ---
    lsl     r2, r5, #3              @ bits[18:3] = valor Q4.12
    orr     r2, r2, #OP_VALUE       @ bits[2:0]  = 010
    str     r2, [r0, #PIO_DATA_IN]
    pulse_enable r0, r3

    pop     {r4, r5, pc}

@ =============================================================================
@ send_bias
@   Envia um valor de bias ao coprocessador (opcode 011 — OP_BIAS).
@
@   Formato OP_BIAS (011):
@     bits[31:26] = não usados
@     bits[25:10] = dado Q4.12 (16 bits)
@     bits[9:3]   = endereço (7 bits)
@     bits[2:0]   = opcode (011)
@
@   Parâmetros:
@     r0 = endereço do bias (7 bits)
@     r1 = valor do bias (16 bits Q4.12)
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
send_bias:
    push    {r4, r5, r6, lr}

    mov     r4, r0                  @ r4 = endereço
    mov     r5, r1                  @ r5 = valor
    rev16   r5,r5              

    ldr     r6, =FPGA_BASE
    ldr     r6, [r6]                @ r6 = base virtual

    @ Monta instrução: valor(16b) << 10 | endereço(7b) << 3 | OP_BIAS
    lsl     r2, r5, #10             @ bits[25:10] = valor Q4.12
    lsl     r3, r4, #3              @ bits[9:3]   = endereço
    orr     r2, r2, r3
    orr     r2, r2, #OP_BIAS        @ bits[2:0]   = 011

    str     r2, [r6, #PIO_DATA_IN]
    pulse_enable r6, r0

    pop     {r4, r5, r6, pc}

@ =============================================================================
@ send_beta
@   Envia um valor de beta ao coprocessador (opcode 100 — OP_BETA).
@
@   Formato OP_BETA (100):
@     bits[31:30] = não usados
@     bits[29:14] = dado Q4.12 (16 bits)
@     bits[13:3]  = endereço (11 bits)
@     bits[2:0]   = opcode (100)
@
@   Parâmetros:
@     r0 = endereço do beta (11 bits)
@     r1 = valor do beta (16 bits Q4.12)
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
send_beta:
    push    {r4, r5, r6, lr}

    mov     r4, r0                  @ r4 = endereço
    mov     r5, r1                  @ r5 = valor
    rev16   r5, r5 

    ldr     r6, =FPGA_BASE
    ldr     r6, [r6]                @ r6 = base virtual

    @ Monta instrução: valor(16b) << 14 | endereço(11b) << 3 | OP_BETA
    lsl     r2, r5, #14             @ bits[29:14] = valor Q4.12
    lsl     r3, r4, #3              @ bits[13:3]  = endereço
    orr     r2, r2, r3
    orr     r2, r2, #OP_BETA        @ bits[2:0]   = 100

    str     r2, [r6, #PIO_DATA_IN]
    pulse_enable r6, r0

    pop     {r4, r5, r6, pc}

@ =============================================================================
@ send_start
@   Envia comando de início de inferência (opcode 101 — OP_START).
@
@   Formato OP_START (101):
@     bits[31:3] = não usados
@     bits[2:0]  = opcode (101)
@
@   Parâmetros: nenhum
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
send_start:
    push    {r4, lr}

    ldr     r4, =FPGA_BASE
    ldr     r4, [r4]                @ r4 = base virtual

    mov     r0, #OP_START           @ instrução: apenas opcode 101
    str     r0, [r4, #PIO_DATA_IN]
    pulse_enable r4, r1

    pop     {r4, pc}

@ =============================================================================
@ wait_done
@   Polling no pio_data_out até que o bit 4 (Done) seja 1.
@
@   Parâmetros: nenhum
@   Retorno: nenhum (void — retorna apenas quando Done=1)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
wait_done:
    push    {r4, lr}

    ldr     r4, =FPGA_BASE
    ldr     r4, [r4]                @ r4 = base virtual

.poll_loop:
    ldr     r0, [r4, #PIO_DATA_OUT] @ lê pio_data_out
    tst     r0, #(1 << BIT_DONE)   @ testa bit 4 (Done)
    beq     .poll_loop              @ zero → ainda não terminou

    pop     {r4, pc}

@ =============================================================================
@ read_result
@   Lê o dígito predito do pio_data_out.
@
@   Parâmetros: nenhum
@   Retorno:
@     r0 = dígito predito (bits 3:0 do pio_data_out, valor 0–9)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
read_result:
    push    {r4, lr}

    ldr     r4, =FPGA_BASE
    ldr     r4, [r4]

    ldr     r0, [r4, #PIO_DATA_OUT] @ lê pio_data_out
    and     r0, r0, #0xF            @ isola bits[3:0] = dígito

    pop     {r4, pc}

@ =============================================================================
@ coprocessor_close
@   Desmapeia a memória mapeada e fecha o file descriptor de /dev/mem.
@
@   Parâmetros: nenhum
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@ =============================================================================
coprocessor_close:
    push    {r4, r5, lr}

    @ --- munmap(FPGA_BASE, 4096) ---
    ldr     r4, =FPGA_BASE
    ldr     r0, [r4]                @ r0 = endereço virtual mapeado
    mov     r7, #91                 @ syscall: munmap
    mov     r1, #MMAP_SIZE
    svc     0

    @ Zera FPGA_BASE
    mov     r0, #0
    str     r0, [r4]

    @ --- close(DEV_MEM_FD) ---
    ldr     r5, =DEV_MEM_FD
    ldr     r0, [r5]                @ r0 = fd
    mov     r7, #6                  @ syscall: close
    svc     0

    @ Zera DEV_MEM_FD
    mov     r0, #0
    str     r0, [r5]

    pop     {r4, r5, pc}

    