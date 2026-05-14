# FPGA-ELM-Linux-Driver
MI - Sistemas Digitais (PBL)
## Introdução
Introdução
Este relatório descreve o desenvolvimento do Marco 2 do problema proposto na disciplina TEC499 — MI SD (UEFS, 2026.1). O objetivo geral do problema é construir um classificador de imagens de dígitos numéricos embarcado em um SoC heterogêneo, combinando um co-processador em FPGA com um processador ARM Cortex-A9 (HPS) rodando Linux.

O sistema é baseado em uma rede neural ELM que recebe uma imagem 28×28 pixels em escala de cinza e retorna o dígito previsto entre 0 e 9. O co-processador responsável por executar essa inferência foi desenvolvido no Marco 1 e herdado pelo nosso grupo como base para esta etapa.

O foco do Marco 2 é a integração entre o HPS e a FPGA. Foram desenvolvidos: a integração do co-processador ao projeto Quartus com mapeamento via ponte Lightweight HPS-to-FPGA, um driver Linux em Assembly ARM para controle do hardware via MMIO, e uma aplicação em C capaz de receber uma imagem PNG, enviá-la ao co-processador e imprimir o dígito classificado. O relatório detalha cada uma dessas etapas, incluindo a arquitetura da solução, os testes realizados e os resultados obtidos.

Por fim, agradecemos ao monitor Maike de Oliveira Nascimento pela disponibilização do co-processador ELM desenvolvido no Marco 1, cujo trabalho foi essencial para o avanço desta etapa.