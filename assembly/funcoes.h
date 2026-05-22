// Arquivo cabeçalho para auxiliar o compilador C

#ifndef FUNCOES_H // Caso ainda não tenha sido definido
#define FUNCOES_H 

#include <stdint.h> // Serve para usar os tipos uint8_t e uint16_t nas assinaturas das funções

// Abre /dev/mem e mapeia ponte LW (0xFF200000)
int iniciar(void);

// Pulsa rst — garante estado IDLE
void resetar(void);

// Pulsa clr_operation — limpa Done/Busy/Error entre inferências
void limpar(void);

// Envia 784 pixels ao coprocessador (opcode 000)
void send_image(uint8_t *buffer);

// Envia todos os pesos (opcodes 001 + 010, valores Q4.12)
void send_weights(uint16_t *buffer, int count);

// Envia todos os bias (opcode 011, valores Q4.12)
void send_bias(uint16_t *buffer, int count);

// Envia todos os beta (opcode 100, valores Q4.12)
void send_beta(uint16_t *buffer, int count);

// Envia comando Start (opcode 101)
void send_start(void);

// Polling até Done (bit 4) = 1
void polling(void);

// Lê dígito predito (bits 3:0 do data_out)
int ler_resultado(void);

// Desmapeia memória e fecha /dev/mem
void fechar(void);

#endif // FUNCOES_H
