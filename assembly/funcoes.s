@ Código assembly responsável por:
@ Inicializar o hardware;
@ Enviar a imagem;
@ Enviar os pesos e o bias;
@ Iniciar inferência;
@ Aguardar finalização (polling ou interrupção);
@ Ler resultados e métricas.

.section .data
    .dev_mem_path: .asciz "/dev/mem"
    FPGA_BASE:  .word 0 @ Endereço virtual base após mmap
    DEV_MEM_FD: .word 0 @ File descriptor do /dev/mem

@ Offsets dos PIOs em relação à base mapeada
.equ PIO_DATA_OUT, 0x00 @ Leitura de resultado/status
.equ PIO_SIGNALS, 0x10 @ Controle: enable(0), clr(1), rst(2)
.equ PIO_DATA_IN, 0x20 @ Instrução enviada ao coprocessador

@ Bits do pio_signals
.equ BIT_ENABLE, 0 @ bit 0 - enable
.equ BIT_CLR, 1 @ bit 1 - clr_operation
.equ BIT_RST, 2 @ bit 2 - rst

@ Bits do pio_data_out
.equ BIT_DONE, 4
.equ BIT_BUSY, 5
.equ BIT_ERROR, 6

@ Opcodes da ISA
.equ OP_IMG, 0b000
.equ OP_ADDR, 0b001
.equ OP_VALUE, 0b010
.equ OP_BIAS, 0b011
.equ OP_BETA, 0b100
.equ OP_START, 0b101

@ Parâmetros do mmap
.equ MMAP_SIZE, 4096 @ 4KB = tamanho de uma página de memória no Linux (cobre todos os PIOs)
.equ PROT_RW, 3 @ Permite a região ser lida e escrita
.equ MAP_SHARED, 1 @ Permite que as mudanças feitas na memória mapeada cheguem ao coprocessador

.section .text @ A seguir, vem código executável

@ Funções visíveis fora do arquivo Assembly
.global iniciar
.global resetar
.global limpar
.global send_image
.global send_weights
.global send_bias
.global send_beta
.global send_start
.global polling
.global ler_resultado
.global fechar

@ Informa ao compilador que os símbolos são funções
.type iniciar, %function
.type resetar, %function
.type limpar, %function
.type send_image, %function
.type send_weights, %function
.type send_bias, %function
.type send_beta, %function
.type send_start, %function
.type polling, %function
.type ler_resultado, %function
.type fechar, %function

@ Macro: pulso de enable no pio_signals
.macro pulse_enable r_base, r_tmp
    mov \r_tmp, #1
    str \r_tmp, [\r_base, #PIO_SIGNALS]
    mov \r_tmp, #0
    str \r_tmp, [\r_base, #PIO_SIGNALS]
.endm

@ Abre /dev/mem e mapeia ponte LW em 0xFF200000
iniciar:
    push {r4, r5, lr} @ Salva os reg utilizados e o endereço de retorno na pilha

    @ Abertura de /dev/mem 
    mov r7, #5 @ Syscall open(): r7 = 5
    ldr r0, =.dev_mem_path
    ldr r1, =0x101002 
    svc 0 @ Executa syscall @ Executa syscall
    cmp r0, #0
    blt .init_fail_open @ Se r0 < 0, a abertura falhou
    mov r4, r0

    ldr r5, =DEV_MEM_FD
    str r4, [r5] @ Depois o FD será utilizado em "fechar"

    @ Mapeamento da ponte LW
    mov r5, r4
    mov r7, #192 @ Syscall mmap2 - mapeia a ponte LW em espaço de usuário
    mov r0, #0
    mov r1, #MMAP_SIZE
    mov r2, #PROT_RW
    mov r3, #MAP_SHARED
    mov r4, r5
    ldr r5, =0xFF200
    svc 0 @ Executa syscall

    ldr r1, =0xF0000000
    cmp r0, r1
    bhs .init_fail_mmap @ Verifica se o mmap falhou

    ldr r5, =FPGA_BASE @ Salva o endereço virtual retornado pelo mmap
    str r0, [r5]

    mov r0, #0
    pop {r4, r5, pc} @ Retorna 0 (sucesso) e restaura os registradores

@ Tratamento de erros
@ Se o open falhou, retorna -1
.init_fail_open:
    mov r0, #-1
    pop {r4, r5, pc}

@ Se o mmap falhou, fecha o FD que foi aberto antes de retornar -2
.init_fail_mmap:
    mov r7, #6 @ Syscall close(): r7 = 6
    mov r0, r4
    svc 0 @ Executa syscall
    mov r0, #-2
    pop {r4, r5, pc}

@ Pulsa rst (bit 2 de pio_signals)
resetar:
    push {r4, lr} @ Salva r4 e o endereço de retorno

    ldr r4, =FPGA_BASE @ Carrega o endereço
    ldr r4, [r4] @ Carrega o valor

    mov r0, #(1 << BIT_RST) @ Coloca 1 no bit 2
    str r0, [r4, #PIO_SIGNALS] @ Ativa o sinal
    mov r0, #0
    str r0, [r4, #PIO_SIGNALS] @ Destiva o sinal

    pop {r4, pc} @ Restaura r4 e retorna

@ Pulsa clr_operation (bit 1 de pio_signals)
limpar:
    push {r4, lr} @ Salva r4 e o endereço de retorno

    ldr r4, =FPGA_BASE @ Carrega o endereço
    ldr r4, [r4] @ Carrega o valor

    mov r0, #(1 << BIT_CLR) @ Coloca 1 no bit 1
    str r0, [r4, #PIO_SIGNALS] @ Ativa o sinal
    mov r0, #0
    str r0, [r4, #PIO_SIGNALS] @ Desativa o sinal

    pop {r4, pc} @ Restaura r4 e retorna

@ A partir daqui, todas as funções de envio seguem a mesma estrutura. 
@ As únicas diferenças estão em como as instruções são montadas e, no
@ caso dos psos, são enviadas duas instruções por cada um deles (uma
@ para o endereço e outra para o valor). Em resumo, todas as funções: 
@ Salvam registradores;
@ Armazenam o ponteiro do buffer em r4;
@ Armazenam o endereço virtual da ponte (FPGA_BASE);
@ Armazenam o índice/endereço atual.

@ Já dentro dos loops, para cada elemento, acontece:
@ Envio da instrução já montada ao coprocessador;
@ Pulsa enable para o processamento;
@ Incrementa índice -> compara com total -> repete se não terminou;
@ Restaura regs e retorna (no pop).

@ Envia 784 pixels (opcode 000)
send_image:
    push {r4, r5, r6, r7, lr}

    mov r4, r0         
    ldr r5, =FPGA_BASE
    ldr r5, [r5]           
    mov r6, #0          

.send_img_loop:
    ldrb r0, [r4], #1 @ Lê 1 byte por pixel 

    lsl r1, r0, #13 
    lsl r2, r6, #3   
    orr r2, r1, r2 @ Montagem da instrução      

    str r2, [r5, #PIO_DATA_IN]
    pulse_enable r5, r0

    add r6, r6, #1
    cmp r6, #784
    blt .send_img_loop

    pop {r4, r5, r6, r7, pc}

@ Envia todos os pesos em loop (opcodes 001 + 010)
send_weights:
    push {r4, r5, r6, r7, lr}

    mov r4, r0              
    mov r6, r1             
    ldr r7, =FPGA_BASE
    ldr r7, [r7]         
    mov r5, #0              

.send_w_loop:
    @ Instrução ADDR (001)
    lsl r0, r5, #3        
    orr r0, r0, #OP_ADDR      
    str r0, [r7, #PIO_DATA_IN]
    pulse_enable r7, r3

    @ Instrução VALUE (010)
    ldrh r0, [r4], #2         
    rev16 r0, r0
    lsl r0, r0, #3      
    orr r0, r0, #OP_VALUE     
    str r0, [r7, #PIO_DATA_IN]
    pulse_enable r7, r3

    add r5, r5, #1
    cmp r5, r6
    blt .send_w_loop

    pop {r4, r5, r6, r7, pc}

@ Envia todos os bias em loop (opcode 011)
send_bias:
    push {r4, r5, r6, r7, lr}

    mov r4, r0                 
    mov r6, r1               
    ldr r7, =FPGA_BASE
    ldr r7, [r7]    
    mov r5, #0

.send_bias_loop:
    ldrh r0, [r4], #2  
    rev16 r0, r0

    lsl r1, r0, #10   
    lsl r2, r5, #3 
    orr r1, r1, r2
    orr r1, r1, #OP_BIAS 
    str r1, [r7, #PIO_DATA_IN]
    pulse_enable r7, r0

    add r5, r5, #1
    cmp r5, r6
    blt .send_bias_loop

    pop {r4, r5, r6, r7, pc}

@ Envia todos os beta em loop (opcode 100)
send_beta:
    push {r4, r5, r6, r7, lr}

    mov r4, r0         
    mov r6, r1    
    ldr r7, =FPGA_BASE
    ldr r7, [r7] 
    mov r5, #0 

.send_beta_loop:
    ldrh r0, [r4], #2 
    rev16 r0, r0

    lsl r1, r0, #14         
    lsl r2, r5, #3           
    orr r1, r1, r2
    orr r1, r1, #OP_BETA       
    str r1, [r7, #PIO_DATA_IN]
    pulse_enable r7, r0

    add r5, r5, #1
    cmp r5, r6
    blt .send_beta_loop

    pop {r4, r5, r6, r7, pc}

@ Envia instrução Start (opcode 101).
@ Não tem loop nem buffer, apenas envia a instrução,
@ pois não carrega nenhum dado, é só um comando de disparo.
send_start:
    push {r4, lr}

    ldr r4, =FPGA_BASE
    ldr r4, [r4]

    mov r0, #OP_START
    str r0, [r4, #PIO_DATA_IN] @ Escreve o opcode no pio_data_in
    pulse_enable r4, r1

    pop {r4, pc}

@ Aguarda Done (bit 4 do pio_data_out) = 1
polling:
    push {r4, lr}

    ldr r4, =FPGA_BASE
    ldr r4, [r4]

.poll_loop:
    ldr r0, [r4, #PIO_DATA_OUT] @ Lê o valor atualç do pio_data_out
    tst r0, #(1 << BIT_DONE) @ Testa o bit 4 (Done)
    beq .poll_loop @ Se bit 4 = 4, lê de novo

    pop {r4, pc}

@ Lê dígito predito (bits 3:0 do pio_data_out)
ler_resultado:
    push {r4, lr}

    ldr r4, =FPGA_BASE
    ldr r4, [r4]

    ldr r0, [r4, #PIO_DATA_OUT] @ Leitura do pio_data_out
    and r0, r0, #0xF @ Isolamento dos bits [3:0]

    pop {r4, pc}

@ Desmapeia memória e fecha /dev/mem
fechar:
    push {r4, r5, lr}

    ldr r4, =FPGA_BASE
    ldr r0, [r4]
    mov r1, #MMAP_SIZE
    mov r7, #91 @ Syscall munmap
    svc 0 @ Executa syscall
    mov r0, #0
    str r0, [r4] @ Zera FPGA_BASE para evitar uso acidental do endereço inválido

    ldr r5, =DEV_MEM_FD
    ldr r0, [r5] 
    mov r7, #6 @ Syscall close
    svc 0 @ Executa syscall
    mov r0, #0
    str r0, [r5] @ Zera DEV_MEM_FD

    pop {r4, r5, pc}
