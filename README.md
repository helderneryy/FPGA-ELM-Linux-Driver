# FPGA-ELM-Linux-Driver
MI - Sistemas Digitais (PBL)
## Introdução
Este relatorio descreve o desenvolvimento do Marco 2 de um sistema embarcado voltado para a classificacao de imagens de digitos numericos, com foco na integracao entre o HPS e a FPGA da plataforma DE1-SoC e no desenvolvimento do driver Linux em Assembly ARM responsavel por controlar o co-processador ELM via MMIO.

O problema proposto consiste em construir um classificador capaz de receber uma imagem 28x28 pixels em escala de cinza no formato PNG, processa-la atraves de uma rede neural ELM implementada no co-processador em FPGA, e retornar o digito previsto entre 0 e 9.
O co-processador responsavel por executar essa inferencia foi desenvolvido pelo monitor da disciplina, Maike de Oliveira Nascimento, no Marco 1. Nosso grupo herdou esse hardware e agradece ao Maike pela disponibilizacao do trabalho, que foi esencial para o avanco desta etapa.

Foram desenvolvidos: a integracao do co-processador ao projeto Quartus com mapeamento via ponte Lightweight HPS-to-FPGA, um driver Linux em Assembly ARM para controle do hardware via MMIO, e uma aplicacao em C capaz de receber uma imagem PNG, acionar o driver e imprimir o digito classificado. O relatorio detalha cada uma dessas etapas, incluindo a arquitetura da solucao, os testes realizados e os resultados obtidos.