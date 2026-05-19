# FPGA-ELM-Linux-Driver
### MI - Sistemas Digitais (PBL)
## Sumário

- [Introdução](#introdução)
- [Requisitos Principais](#requisitos-principais)
  - [Entrada e Saída](#entrada-e-saída)
  - [Driver](#driver)
  - [Aplicação C](#aplicação-c)
- [Co-processador ELM](#co-processador-elm)
  - [Unidade de Controle](#unidade-de-controle)
  - [Unidade de Inferência](#unidade-de-inferência)
  - [Load/Store Unit](#loadstore-unit)
  - [Conjunto de Instruções](#conjunto-de-instruções)
  - [Fluxo de Execução](#fluxo-de-execução)
- [Metodologia de Desenvolvimento](#metodologia-de-desenvolvimento)


## Introdução
Este relatório descreve o desenvolvimento do Marco 2 de um sistema embarcado voltado para a classificação de imagens de dígitos numéricos (TEC499 — UEFS, 2026.1), com foco na integração entre o HPS e a FPGA da plataforma DE1-SoC e no desenvolvimento do driver Linux em Assembly ARM responsável por controlar o co-processador ELM via MMIO.

O problema proposto consiste em construir um classificador capaz de receber uma imagem 28×28 pixels em escala de cinza no formato PNG, processá-la através de uma rede neural ELM implementada no co-processador em FPGA, e retornar o dígito previsto entre 0 e 9. O co-processador responsável por executar essa inferência foi desenvolvido no Marco 1 e herdado pelo nosso grupo como base para esta etapa.

Foram desenvolvidos: a integração do co-processador ao projeto Quartus com mapeamento via ponte Lightweight HPS-to-FPGA, um driver Linux em Assembly ARM para controle do hardware via MMIO, e uma aplicação em C capaz de receber uma imagem PNG, acionar o driver e imprimir o dígito classificado. O relatório detalha cada uma dessas etapas, incluindo a arquitetura da solução, os testes realizados e os resultados obtidos.
Por fim, agradecemos ao monitor Maike de Oliveira Nascimento pela disponibilização do co-processador ELM desenvolvido no Marco 1, cujo trabalho foi essencial para o avanço desta etapa.

## Requisitos Principais
Esta seção descreve os requisitos que a solução deve atender, tanto os definidos explicitamente pelo enunciado quanto os identificados pela equipe ao longo do desenvolvimento. Para o Marco 2, o desafio central é garantir que o co-processador ELM desenvolvido no Marco 1 seja corretamente integrado ao HPS, controlado via MMIO através de um driver em Assembly ARM, e acessível por uma aplicação em C que permita ao usuário classificar imagens de dígitos numéricos de ponta a ponta.

### Entrada e Saída
A entrada do sistema é uma imagem em escala de cinza com 28×28 pixels, 8 bits por pixel, no formato PNG, totalizando 784 bytes. Cada pixel representa a intensidade luminosa de um ponto da imagem, variando de 0 (preto) a 255 (branco). Cada imagem representa um único dígito numérico entre 0 e 9.

Antes de ser enviada ao co-processador, a imagem é lida pela aplicação C, que extrai os 784 bytes de pixels e os repassa ao driver em Assembly, responsável por transferi-los ao hardware via MMIO.

A saída esperada é um número inteiro no intervalo [0, 9] correspondente ao dígito classificado pelo co-processador ELM, obtido através da operação argmax aplicada ao vetor de saída da rede neural.


### Driver
O driver deve ser implementado em Assembly ARM e atuar como interface entre a aplicação C e o co-processador ELM via MMIO, expondo uma API que permita à aplicação inicializar o hardware, enviar a imagem, os pesos e o bias, iniciar a inferência, aguardar a finalização via polling e retornar o resultado da classificação. Além disso, deve garantir a correta sincronização entre o HPS e a FPGA, assegurando que os dados sejam transferidos na ordem correta e que o co-processador esteja pronto antes de cada operação.

### Aplicação C
A aplicação em C deve servir como interface entre o usuário e o sistema, sendo responsável por receber o caminho de uma imagem PNG via linha de comando, realizar a leitura e extração dos pixels e acionar o driver para que o processo de classificação seja iniciado. Após obter o resultado, a aplicação deve imprimir o dígito previsto na tela de forma clara ao usuário.

## Co-processador ELM
Esta seção é dedicada exclusivamente a descrever o funcionamento do co-processador ELM desenvolvido pelo monitor Maike de Oliveira Nascimento no Marco 1, cujo hardware foi utilizado como base para o desenvolvimento desta etapa.

O co-processador é composto por três módulos principais: a Unidade de Controle, a Unidade de Inferência e a Load/Store Unit. Cada um desses módulos possui responsabilidades e barramentos bem definidos.

IMG
### Unidade de Controle
A Unidade de Controle é responsável por receber as instruções e sinais de controle externos, realizar a decodificação da instrução e direcionar o processador para um estado de memória ou de inferência. Durante a execução de uma instrução nenhuma outra pode ser executada, sendo necessário aguardar o término da operação atual antes de enviar uma nova.

### Unidade de Inferência
A Unidade de Inferência abriga os MACs e os bancos de registradores utilizados durante o processo de cálculo. É dividida em seis submódulos: Primeira Camada, responsável pelos cálculos da camada oculta do ELM; Banco de 128 Registradores, que armazena os resultados dos neurônios da camada oculta; Segunda Camada, responsável pelos cálculos da camada de saída; Banco de 10 Registradores, que armazena os resultados dos neurônios da camada de saída; Argmax Iterativo, que busca o registrador de maior valor para determinar o dígito classificado; e a Unidade de Controle de Inferência, que organiza a execução de cada etapa da ELM.

### Load/Store Unit
A Load/Store Unit gerencia as operações de leitura e escrita de memória, implementando quatro instâncias de memória RAM de duas portas: mem_img, que armazena os 784 pixels da imagem; mem_win, que armazena os 100352 pesos da camada oculta; mem_bias, que armazena os 128 valores de bias; e mem_beta, que armazena os 1280 valores de beta da camada de saída.

### conjunto de instruções
Em relação ao conjunto de instruções, o co-processador implementa seis instruções de 32 bits: Store Image (opcode 000), Store Weights Addr (001), Store Weights Value (010), Store Bias (011), Store Beta (100) e Start (101). A comunicação com o co-processador é feita através de três barramentos: Data In (32 bits), utilizado para envio das instruções; Signals (3 bits), utilizado para envio de sinais de controle como Enable, Clear Operation e Reset; e Data Out (32 bits), que retorna o resultado da inferência e as flags de Done, Busy e Error.

### Fluxo de execução
O fluxo de execução do co-processador segue uma sequência bem definida: primeiro os dados são carregados nas memórias via instruções de memória (Store Image, Store Weights, Store Bias e Store Beta), em seguida a instrução Start dispara o processo de inferência, que percorre a camada oculta, aplica a função de ativação tanh, processa a camada de saída e por fim executa o argmax para determinar o dígito classificado. O resultado fica disponível no barramento Data Out junto com a flag de Done indicando a conclusão da operação.

## Metodologia de Desenvolvimento
O desenvolvimento da solução foi realizado seguindo a metodologia PBL, em que o projeto foi avançando de forma incremental a cada sessão tutorial. Os roteiros de laboratório disponibilizados ao longo do processo foram fundamentais para guiar a equipe nas etapas iniciais do desenvolvimento.

O Lab 0 foi relevante para nivelar o conhecimento da equipe sobre o uso da plataforma DE1-SoC, introduzindo conceitos básicos de SSH, comandos Linux e programação em C, que serviram de base para o trabalho com o HPS ao longo do projeto.

O Lab 2 foi o mais diretamente aplicável ao desenvolvimento do Marco 2. Por meio dele, a equipe compreendeu como funciona a integração entre o HPS e a FPGA, especialmente como abrir o projeto base no Quartus, visualizar o HPS e instanciar um módulo no top level do projeto, processo essencial para integrar o co-processador do Maike ao sistema. Essa compreensão orientou diretamente as decisões tomadas na etapa de integração HPS-FPGA.

No decorrer das sessões, a equipe decidiu por conta própria elaborar um fluxo de informações inicial, que serviu como base conceitual para o entendimento do sistema, sem ainda definir as instruções de forma concreta. Paralelamente, foram realizadas pesquisas sobre temas como polling, MMIO, como estruturar uma API em Assembly e outros conceitos relacionados, que trouxeram mudanças significativas na compreensão teórica da equipe e orientaram as decisões de implementação ao longo do desenvolvimento.

IMG 

No desenvolvimento do driver, a equipe optou por implementar diretamente em Assembly ARM, sem passar por uma versão intermediária em C. Para garantir a corretude da implementação, foi utilizado o GDB como ferramenta de depuração, permitindo inspecionar o estado de cada registrador em tempo real a cada etapa da execução. A integração no Quartus foi realizada com base no aprendizado do Lab 2, seguindo o mesmo processo de construção do top level para instanciar o co-processador no projeto base.
