# Documentação da API — Driver Assembly ARM

## Visão Geral

O driver `funcoes.s` é implementado em Assembly ARM e expõe uma API em C através do header `funcoes.h`. Ele é responsável por toda a comunicação de baixo nível entre a aplicação C e o co-processador ELM implementado na FPGA da plataforma DE1-SoC, utilizando o mecanismo de MMIO (Memory-Mapped I/O) através da ponte Lightweight HPS-to-FPGA.

### Endereços e Offsets

| Registrador     | Offset  | Descrição                              |
|-----------------|---------|----------------------------------------|
| `pio_data_out`  | `0x00`  | Leitura de resultado e flags de status |
| `pio_signals`   | `0x10`  | Envio de sinais de controle            |
| `pio_data_in`   | `0x20`  | Envio de instruções ao co-processador  |

### Bits de Controle (`pio_signals`)

| Bit | Nome       | Descrição                        |
|-----|------------|----------------------------------|
| 0   | `ENABLE`   | Habilita a execução da instrução |
| 1   | `CLR`      | Limpa flags Done/Busy/Error      |
| 2   | `RST`      | Reseta o co-processador          |

### Bits de Status (`pio_data_out`)

| Bit   | Nome    | Descrição                         |
|-------|---------|-----------------------------------|
| 4     | `DONE`  | Inferência concluída              |
| 5     | `BUSY`  | Co-processador em processamento   |
| 6     | `ERROR` | Erro no processamento             |
| [3:0] | —       | Dígito predito (0–9)              |

### Opcodes da ISA

| Opcode  | Instrução          | Descrição                        |
|---------|--------------------|----------------------------------|
| `000`   | `OP_IMG`           | Envia pixel da imagem            |
| `001`   | `OP_ADDR`          | Envia endereço do peso           |
| `010`   | `OP_VALUE`         | Envia valor do peso              |
| `011`   | `OP_BIAS`          | Envia valor de bias              |
| `100`   | `OP_BETA`          | Envia valor de beta              |
| `101`   | `OP_START`         | Inicia a inferência              |

---

## Funções

---

### `iniciar`

```c
int iniciar(void);
```

**Descrição:**
Abre o arquivo `/dev/mem` via syscall `open` e mapeia a região física da ponte Lightweight HPS-to-FPGA (`0xFF200000`) para um endereço virtual acessível pelo processo, utilizando a syscall `mmap2`. O endereço virtual retornado é salvo em `FPGA_BASE` e o file descriptor em `DEV_MEM_FD`, sendo ambos utilizados pelas demais funções.

**Parâmetros:** nenhum

**Retorno:**

| Valor | Descrição                        |
|-------|----------------------------------|
| `0`   | Sucesso                          |
| `-1`  | Falha ao abrir `/dev/mem`        |
| `-2`  | Falha no mapeamento com `mmap2`  |

**Exemplo de uso:**
```c
if (iniciar() != 0) {
    printf("Erro ao inicializar o hardware.\n");
    return -1;
}
```

---

### `resetar`

```c
void resetar(void);
```

**Descrição:**
Aplica um pulso de reset no co-processador ativando e desativando o bit 2 (`RST`) do `pio_signals`. Garante que o co-processador esteja em estado IDLE antes de uma nova operação.

**Parâmetros:** nenhum

**Retorno:** nenhum

**Exemplo de uso:**
```c
resetar();
```

---

### `limpar`

```c
void limpar(void);
```

**Descrição:**
Limpa as flags de status (`Done`, `Busy`, `Error`) do co-processador ativando e desativando o bit 1 (`CLR`) do `pio_signals`. Deve ser chamada entre inferências para garantir que os flags estejam zerados antes de um novo ciclo.

**Parâmetros:** nenhum

**Retorno:** nenhum

**Exemplo de uso:**
```c
limpar();
```

---

### `send_image`

```c
void send_image(uint8_t *buffer);
```

**Descrição:**
Envia os 784 pixels da imagem ao co-processador utilizando o opcode `000` (`OP_IMG`). Para cada pixel, monta uma instrução de 32 bits posicionando o dado nos bits `[20:13]` e o endereço nos bits `[12:3]`, escreve no `pio_data_in` e pulsa o enable.

**Formato da instrução:**

| Bits      | Campo    | Descrição           |
|-----------|----------|---------------------|
| `[31:21]` | —        | Não utilizados      |
| `[20:13]` | dado     | Pixel (8 bits)      |
| `[12:3]`  | endereço | Índice (0–783)      |
| `[2:0]`   | opcode   | `000`               |

**Parâmetros:**

| Parâmetro | Tipo        | Descrição                          |
|-----------|-------------|------------------------------------|
| `buffer`  | `uint8_t *` | Ponteiro para os 784 bytes da imagem |

**Retorno:** nenhum

**Exemplo de uso:**
```c
uint8_t imagem[784];
// ... carrega imagem ...
send_image(imagem);
```

---

### `send_weights`

```c
void send_weights(uint16_t *buffer, int count);
```

**Descrição:**
Envia todos os pesos da camada oculta ao co-processador. Para cada peso, são enviadas duas instruções: primeiro o endereço (opcode `001` — `OP_ADDR`) e em seguida o valor (opcode `010` — `OP_VALUE`). Os valores em ponto fixo Q4.12 passam por `rev16` para correção de endianness antes do envio.

**Formato da instrução ADDR (`001`):**

| Bits      | Campo    | Descrição           |
|-----------|----------|---------------------|
| `[31:20]` | —        | Não utilizados      |
| `[19:3]`  | endereço | 17 bits             |
| `[2:0]`   | opcode   | `001`               |

**Formato da instrução VALUE (`010`):**

| Bits      | Campo  | Descrição           |
|-----------|--------|---------------------|
| `[31:19]` | —      | Não utilizados      |
| `[18:3]`  | dado   | Valor Q4.12         |
| `[2:0]`   | opcode | `010`               |

**Parâmetros:**

| Parâmetro | Tipo         | Descrição                          |
|-----------|--------------|------------------------------------|
| `buffer`  | `uint16_t *` | Ponteiro para o array de pesos     |
| `count`   | `int`        | Número de pesos a enviar           |

**Retorno:** nenhum

**Exemplo de uso:**
```c
uint16_t pesos[100352];
// ... carrega pesos ...
send_weights(pesos, 100352);
```

---

### `send_bias`

```c
void send_bias(uint16_t *buffer, int count);
```

**Descrição:**
Envia todos os valores de bias ao co-processador utilizando o opcode `011` (`OP_BIAS`). Para cada valor, monta uma instrução de 32 bits posicionando o dado nos bits `[25:10]` e o endereço nos bits `[9:3]`. Os valores passam por `rev16` para correção de endianness.

**Formato da instrução (`011`):**

| Bits      | Campo    | Descrição           |
|-----------|----------|---------------------|
| `[31:26]` | —        | Não utilizados      |
| `[25:10]` | dado     | Valor Q4.12         |
| `[9:3]`   | endereço | 7 bits              |
| `[2:0]`   | opcode   | `011`               |

**Parâmetros:**

| Parâmetro | Tipo         | Descrição                          |
|-----------|--------------|------------------------------------|
| `buffer`  | `uint16_t *` | Ponteiro para o array de bias      |
| `count`   | `int`        | Número de valores a enviar         |

**Retorno:** nenhum

**Exemplo de uso:**
```c
uint16_t bias[128];
// ... carrega bias ...
send_bias(bias, 128);
```

---

### `send_beta`

```c
void send_beta(uint16_t *buffer, int count);
```

**Descrição:**
Envia todos os valores de beta ao co-processador utilizando o opcode `100` (`OP_BETA`). Para cada valor, monta uma instrução de 32 bits posicionando o dado nos bits `[29:14]` e o endereço nos bits `[13:3]`. Os valores passam por `rev16` para correção de endianness.

**Formato da instrução (`100`):**

| Bits      | Campo    | Descrição           |
|-----------|----------|---------------------|
| `[31:30]` | —        | Não utilizados      |
| `[29:14]` | dado     | Valor Q4.12         |
| `[13:3]`  | endereço | 11 bits             |
| `[2:0]`   | opcode   | `100`               |

**Parâmetros:**

| Parâmetro | Tipo         | Descrição                          |
|-----------|--------------|------------------------------------|
| `buffer`  | `uint16_t *` | Ponteiro para o array de beta      |
| `count`   | `int`        | Número de valores a enviar         |

**Retorno:** nenhum

**Exemplo de uso:**
```c
uint16_t beta[1280];
// ... carrega beta ...
send_beta(beta, 1280);
```

---

### `send_start`

```c
void send_start(void);
```

**Descrição:**
Envia o comando de início de inferência ao co-processador, utilizando apenas o opcode `101` (`OP_START`) nos bits `[2:0]`. Não carrega nenhum dado — é exclusivamente um comando de disparo.

**Formato da instrução (`101`):**

| Bits     | Campo  | Descrição  |
|----------|--------|------------|
| `[31:3]` | —      | Não utilizados |
| `[2:0]`  | opcode | `101`      |

**Parâmetros:** nenhum

**Retorno:** nenhum

**Exemplo de uso:**
```c
send_start();
```

---

### `polling`

```c
void polling(void);
```

**Descrição:**
Aguarda a conclusão da inferência realizando leitura contínua do `pio_data_out` até que o bit 4 (`DONE`) seja 1. A função bloqueia a execução até que o co-processador sinalize o término do processamento.

**Parâmetros:** nenhum

**Retorno:** nenhum (retorna apenas quando `DONE = 1`)

**Exemplo de uso:**
```c
send_start();
polling(); // aguarda a inferência terminar
```

---

### `ler_resultado`

```c
int ler_resultado(void);
```

**Descrição:**
Lê o dígito predito pelo co-processador isolando os bits `[3:0]` do `pio_data_out`. Deve ser chamada após `polling` confirmar que a inferência foi concluída.

**Parâmetros:** nenhum

**Retorno:**

| Valor  | Descrição              |
|--------|------------------------|
| `0–9`  | Dígito predito         |

**Exemplo de uso:**
```c
polling();
int digito = ler_resultado();
printf("Dígito predito: %d\n", digito);
```

---

### `fechar`

```c
void fechar(void);
```

**Descrição:**
Desfaz o mapeamento de memória via syscall `munmap` e fecha o file descriptor do `/dev/mem` via syscall `close`. Após a chamada, `FPGA_BASE` e `DEV_MEM_FD` são zerados para evitar uso acidental de endereços inválidos.

**Parâmetros:** nenhum

**Retorno:** nenhum

**Exemplo de uso:**
```c
fechar();
```

---

## Fluxo Completo de Uso

```c
// 1. Inicializar
if (iniciar() != 0) return -1;

// 2. Resetar e limpar
resetar();
limpar();

// 3. Enviar dados
send_image(buffer_imagem);
send_weights(buffer_pesos, 100352);
send_bias(buffer_bias, 128);
send_beta(buffer_beta, 1280);

// 4. Disparar inferência
send_start();

// 5. Aguardar e ler resultado
polling();
int digito = ler_resultado();
printf("Dígito predito: %d\n", digito);

// 6. Finalizar
limpar();
fechar();
```

---

## Erros Comuns

| Situação                        | Causa Provável                              | Solução                              |
|---------------------------------|---------------------------------------------|--------------------------------------|
| `iniciar()` retorna `-1`        | Sem permissão para abrir `/dev/mem`         | Executar com `sudo`                  |
| `iniciar()` retorna `-2`        | Falha no mapeamento do endereço físico      | Verificar se a FPGA está programada  |
| `polling()` não retorna         | Co-processador travado ou dados incorretos  | Chamar `resetar()` e `limpar()`      |
| Resultado incorreto             | Dados enviados em ordem ou formato errado   | Verificar endianness e formato Q4.12 |
