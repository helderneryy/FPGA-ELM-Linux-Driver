# FPGA-ELM-Linux-Driver
MI - Sistemas Digitais (PBL)
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