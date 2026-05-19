@ =============================================================================
@ main.s — Ponto de entrada do driver do Coprocessador ELM
@ Disciplina: TEC499 - Sistemas Digitais, UEFS 2026.1
@
@ Fluxo de execução:
@   1. Inicializa coprocessador (abre /dev/mem e mapeia ponte LW)
@   2. Reseta o coprocessador
@   3. Lê imagem do arquivo 5.bin (784 bytes)
@   4. Envia imagem ao coprocessador
@   5. Envia pesos (W_in_q.bin), bias (b_q.bin) e beta (beta_q.bin)
@   6. Envia comando Start
@   7. Aguarda Done (polling via wait_done)
@   8. Lê e exibe resultado
@   9. Fecha coprocessador e encerra
@ =============================================================================

@ Declarações externas (implementadas em coprocessor_api.s)
.extern coprocessor_init
.extern coprocessor_reset
.extern coprocessor_clear
.extern send_image
.extern send_weights
.extern send_bias
.extern send_beta
.extern send_start
.extern wait_done
.extern read_result
.extern coprocessor_close

.section .data
    image_file:     .asciz "bins/4.bin"      @ Arquivo de imagem (28x28 = 784 bytes)
    weights_file:   .asciz "bins/W_in_q.bin" @ Pesos entrada: 784x128 valores int16
    bias_file:      .asciz "bins/b_q.bin"    @ Bias: 128 valores int16
    beta_file:      .asciz "bins/beta_q.bin" @ Beta: 128x10 valores int16

    @ Mensagens de saída
    msg_init_ok:      .asciz "[OK] Coprocessador inicializado.\n"
    msg_init_fail:    .asciz "[ERRO] Falha ao inicializar coprocessador.\n"
    msg_reset_ok:     .asciz "[OK] Reset aplicado.\n"
    msg_img_ok:       .asciz "[OK] Imagem enviada.\n"
    msg_img_fail:     .asciz "[ERRO] Falha ao abrir/ler imagem.\n"
    msg_weights_ok:   .asciz "[OK] Pesos enviados.\n"
    msg_weights_fail: .asciz "[ERRO] Falha ao abrir/ler W_in_q.bin.\n"
    msg_bias_ok:      .asciz "[OK] Bias enviado.\n"
    msg_bias_fail:    .asciz "[ERRO] Falha ao abrir/ler b_q.bin.\n"
    msg_beta_ok:      .asciz "[OK] Beta enviado.\n"
    msg_beta_fail:    .asciz "[ERRO] Falha ao abrir/ler beta_q.bin.\n"
    msg_start_ok:     .asciz "[OK] Inferencia iniciada.\n"
    msg_done:         .asciz "[OK] Inferencia concluida. Digito: "
    msg_newline:      .asciz "\n"

    @ Buffer de conversão do dígito para ASCII (1 char + newline)
    digit_buf:      .byte 0, 10, 0      @ char, '\n', terminador

@ Tamanhos dos buffers (em bytes, todos int16 = 2 bytes por valor)
.equ W_IN_COUNT,   100352   @ 784 * 128 valores
.equ W_IN_BYTES,   200704   @ W_IN_COUNT * 2
.equ B_COUNT,      128      @ 128 valores
.equ B_BYTES,      256      @ B_COUNT * 2
.equ BETA_COUNT,   1280     @ 128 * 10 valores
.equ BETA_BYTES,   2560     @ BETA_COUNT * 2

.section .bss
    .align 2
    image_buffer:   .space 784          @ Buffer imagem (784 bytes)
    weights_buffer: .space W_IN_BYTES   @ Buffer W_in_q (200704 bytes)
    bias_buffer:    .space B_BYTES      @ Buffer b_q    (256 bytes)
    beta_buffer:    .space BETA_BYTES   @ Buffer beta_q (2560 bytes)

.section .text
.global _start

@ =============================================================================
@ _start — Ponto de entrada principal
@ =============================================================================
_start:
    @ -----------------------------------------------------------------------
    @ PASSO 1: Inicializar coprocessador
    @ -----------------------------------------------------------------------
    bl      coprocessor_init
    cmp     r0, #0
    blt     .error_init

    ldr     r0, =msg_init_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 2: Resetar coprocessador
    @ -----------------------------------------------------------------------
    bl      coprocessor_reset

    ldr     r0, =msg_reset_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 3: Abrir e ler imagem (5.bin → image_buffer)
    @ -----------------------------------------------------------------------
    @ open("5.bin", O_RDONLY)
    mov     r7, #5
    ldr     r0, =image_file
    mov     r1, #0                      @ O_RDONLY
    svc     0
    cmp     r0, #0
    blt     .error_img

    mov     r4, r0                      @ r4 = fd da imagem

    @ read(fd, image_buffer, 784)
    mov     r7, #3
    mov     r0, r4
    ldr     r1, =image_buffer
    mov     r2, #784
    svc     0
    cmp     r0, #784                    @ verifica se leu exatamente 784 bytes
    bne     .error_img_close

    @ close(fd da imagem)
    mov     r7, #6
    mov     r0, r4
    svc     0

    @ -----------------------------------------------------------------------
    @ PASSO 4: Enviar imagem ao coprocessador
    @ -----------------------------------------------------------------------
    ldr     r0, =image_buffer
    bl      send_image

    ldr     r0, =msg_img_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 5a: Ler e enviar pesos (W_in_q.bin — 100352 valores int16)
    @   Cada valor int16 corresponde a um peso Q4.12.
    @   O endereço enviado ao coprocessador é o índice linear (0..100351).
    @ -----------------------------------------------------------------------
    mov     r7, #5
    ldr     r0, =weights_file
    mov     r1, #0                      @ O_RDONLY
    svc     0
    cmp     r0, #0
    blt     .error_weights
    mov     r4, r0                      @ r4 = fd W_in_q

    mov     r7, #3
    mov     r0, r4
    ldr     r1, =weights_buffer
    ldr     r2, =W_IN_BYTES
    svc     0
    cmp     r0, #W_IN_BYTES
    bne     .error_weights_close

    mov     r7, #6
    mov     r0, r4
    svc     0                           @ fecha W_in_q.bin

    @ Loop de envio: send_weights(índice, valor) para cada um dos 100352 pesos
    ldr     r4, =weights_buffer         @ r4 = ponteiro no buffer (pós-incrementado)
    mov     r5, #0                      @ r5 = índice (endereço) atual

.send_weights_loop:
    ldrh    r1, [r4], #2                @ r1 = valor int16 (pós-incrementa 2 bytes)
    mov     r0, r5                      @ r0 = endereço
    bl      send_weights
    add     r5, r5, #1
    ldr     r6, =W_IN_COUNT
    cmp     r5, r6
    blt     .send_weights_loop

    ldr     r0, =msg_weights_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 5b: Ler e enviar bias (b_q.bin — 128 valores int16)
    @   Endereço = índice do neurônio (0..127).
    @ -----------------------------------------------------------------------
    mov     r7, #5
    ldr     r0, =bias_file
    mov     r1, #0
    svc     0
    cmp     r0, #0
    blt     .error_bias
    mov     r4, r0                      @ r4 = fd b_q

    mov     r7, #3
    mov     r0, r4
    ldr     r1, =bias_buffer
    mov     r2, #B_BYTES
    svc     0
    cmp     r0, #B_BYTES
    bne     .error_bias_close

    mov     r7, #6
    mov     r0, r4
    svc     0                           @ fecha b_q.bin

    @ Loop de envio: send_bias(índice, valor) para cada um dos 128 bias
    ldr     r4, =bias_buffer
    mov     r5, #0                      @ r5 = índice

.send_bias_loop:
    ldrh    r1, [r4], #2
    mov     r0, r5
    bl      send_bias
    add     r5, r5, #1
    cmp     r5, #B_COUNT
    blt     .send_bias_loop

    ldr     r0, =msg_bias_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 5c: Ler e enviar beta (beta_q.bin — 1280 valores int16)
    @   Endereço = índice linear (0..1279).
    @ -----------------------------------------------------------------------
    mov     r7, #5
    ldr     r0, =beta_file
    mov     r1, #0
    svc     0
    cmp     r0, #0
    blt     .error_beta
    mov     r4, r0                      @ r4 = fd beta_q

    mov     r7, #3
    mov     r0, r4
    ldr     r1, =beta_buffer
    ldr     r2, =BETA_BYTES
    svc     0
    cmp     r0, #BETA_BYTES
    bne     .error_beta_close

    mov     r7, #6
    mov     r0, r4
    svc     0                           @ fecha beta_q.bin

    @ Loop de envio: send_beta(índice, valor) para cada um dos 1280 beta
    ldr     r4, =beta_buffer
    mov     r5, #0                      @ r5 = índice

.send_beta_loop:
    ldrh    r1, [r4], #2
    mov     r0, r5
    bl      send_beta
    add     r5, r5, #1
    ldr     r6, =BETA_COUNT
    cmp     r5, r6
    blt     .send_beta_loop

    ldr     r0, =msg_beta_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 6: Enviar comando Start
    @ -----------------------------------------------------------------------
    bl      send_start

    ldr     r0, =msg_start_ok
    bl      print_str

    @ -----------------------------------------------------------------------
    @ PASSO 7: Aguardar conclusão da inferência (polling em Done)
    @ -----------------------------------------------------------------------
    bl      wait_done

    @ -----------------------------------------------------------------------
    @ PASSO 8: Ler e exibir resultado
    @ -----------------------------------------------------------------------
    bl      read_result                 @ r0 = dígito (0–9)
    mov     r4, r0                      @ preserva dígito em r4

    @ Converte dígito para ASCII e grava no digit_buf
    add     r0, r4, #'0'               @ converte para caractere ASCII
    ldr     r1, =digit_buf
    strb    r0, [r1]                    @ grava no buffer

    @ Exibe mensagem "Digito: X\n"
    ldr     r0, =msg_done
    bl      print_str

    ldr     r0, =digit_buf
    bl      print_str                   @ imprime "X\n"

    @ -----------------------------------------------------------------------
    @ PASSO 9: Fechar coprocessador e encerrar
    @ -----------------------------------------------------------------------
    bl      coprocessor_close

    mov     r7, #1                      @ syscall: exit
    mov     r0, #0                      @ código de saída 0 (sucesso)
    svc     0

@ -----------------------------------------------------------------------
@ Tratamento de erros
@ -----------------------------------------------------------------------
.error_init:
    ldr     r0, =msg_init_fail
    bl      print_str
    b       .exit_fail

.error_img_close:
    @ Fecha fd da imagem antes de reportar erro
    mov     r7, #6
    mov     r0, r4
    svc     0
.error_img:
    ldr     r0, =msg_img_fail
    bl      print_str
    bl      coprocessor_close           @ garante fechamento do /dev/mem
    b       .exit_fail

.error_weights_close:
    mov     r7, #6
    mov     r0, r4
    svc     0
.error_weights:
    ldr     r0, =msg_weights_fail
    bl      print_str
    bl      coprocessor_close
    b       .exit_fail

.error_bias_close:
    mov     r7, #6
    mov     r0, r4
    svc     0
.error_bias:
    ldr     r0, =msg_bias_fail
    bl      print_str
    bl      coprocessor_close
    b       .exit_fail

.error_beta_close:
    mov     r7, #6
    mov     r0, r4
    svc     0
.error_beta:
    ldr     r0, =msg_beta_fail
    bl      print_str
    bl      coprocessor_close
    b       .exit_fail

.exit_fail:
    mov     r7, #1                      @ syscall: exit
    mov     r0, #1                      @ código de saída 1 (erro)
    svc     0

@ =============================================================================
@ print_str
@   Escreve uma string terminada em '\0' na saída padrão (stdout).
@
@   Parâmetros:
@     r0 = ponteiro para a string (terminada em '\0')
@   Retorno: nenhum (void)
@   Registradores preservados: r4–r11 (AAPCS)
@
@   Nota: calcula o comprimento percorrendo a string byte a byte,
@   depois invoca write(1, ptr, len).
@ =============================================================================
print_str:
    push    {r4, r5, r7, lr}

    mov     r4, r0                      @ r4 = ponteiro início da string
    mov     r5, #0                      @ r5 = contador de comprimento

.strlen_loop:
    ldrb    r1, [r4, r5]                @ carrega byte na posição r5
    cmp     r1, #0                      @ é '\0'?
    beq     .do_write
    add     r5, r5, #1
    b       .strlen_loop

.do_write:
    mov     r7, #4                      @ syscall: write
    mov     r0, #1                      @ fd = stdout
    mov     r1, r4                      @ ptr = início da string
    mov     r2, r5                      @ len = comprimento calculado
    svc     0

    pop     {r4, r5, r7, pc}

