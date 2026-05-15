# FPGA-ELM-Linux-Driver
MI - Sistemas Digitais (PBL)
## Introdução
Este relatório descreve o desenvolvimento do Marco 2 de um sistema embarcado voltado para a classificação de imagens de dígitos numéricos (TEC499 — UEFS, 2026.1), com foco na integração entre o HPS e a FPGA da plataforma DE1-SoC e no desenvolvimento do driver Linux em Assembly ARM responsável por controlar o co-processador ELM via MMIO.

O problema proposto consiste em construir um classificador capaz de receber uma imagem 28×28 pixels em escala de cinza no formato PNG, processá-la através de uma rede neural ELM implementada no co-processador em FPGA, e retornar o dígito previsto entre 0 e 9. O co-processador responsável por executar essa inferência foi desenvolvido no Marco 1 e herdado pelo nosso grupo como base para esta etapa.

Foram desenvolvidos: a integração do co-processador ao projeto Quartus com mapeamento via ponte Lightweight HPS-to-FPGA, um driver Linux em Assembly ARM para controle do hardware via MMIO, e uma aplicação em C capaz de receber uma imagem PNG, acionar o driver e imprimir o dígito classificado. O relatório detalha cada uma dessas etapas, incluindo a arquitetura da solução, os testes realizados e os resultados obtidos.
Por fim, agradecemos ao monitor Maike de Oliveira Nascimento pela disponibilização do co-processador ELM desenvolvido no Marco 1, cujo trabalho foi essencial para o avanço desta etapa.