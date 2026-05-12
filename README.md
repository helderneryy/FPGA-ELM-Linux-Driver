# FPGA-ELM-Linux-Driver
MI - Sistemas Digitais (PBL)
## Introdução
Este relatório apresenta o desenvolvimento do Marco 2 do problema de Sistemas Digitais (TEC499 —  UEFS, 2026.1) , que trata da integração entre o HPS e a FPGA da DE1-SoC através de um driver Linux em Assembly ARM.
Vale destacar que o coprocessador ELM usado como base, o núcleo que de fato executa a inferência e classifica os dígitos, foi desenvolvido pelo monitor Maike de Oliveira Nascimento no Marco 1 . Nosso grupo não partiu do zero: herdamos esse hardware e construímos em cima dele a camada de software, o driver e a comunicação HPS-FPGA. Achamos importante deixar isso claro e agradecemos ao Maike pela disponibilização do trabalho.
A partir daí, o foco da nossa equipe foi desenvolver o driver em Assembly ARM para controlar o coprocessador via MMIO, além da aplicação em C que lê uma imagem PMG, envia ao hardware e imprime o dígito previsto.