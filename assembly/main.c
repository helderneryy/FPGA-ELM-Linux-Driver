// Bibliotecas necessárias 
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "funcoes.h"

// Tamanhos dos buffers e caminhos dos arquivos de pesos
#define IMAGE_SIZE 784
#define W_IN_COUNT 100352
#define W_IN_BYTES (W_IN_COUNT * 2)
#define B_COUNT 128
#define B_BYTES (B_COUNT * 2)
#define BETA_COUNT 1280
#define BETA_BYTES (BETA_COUNT * 2)

// Caminhos dos arquivos de pesos, bias e beta
#define WEIGHTS_FILE "bins/W_in_q.bin"
#define BIAS_FILE "bins/b_q.bin"
#define BETA_FILE "bins/beta_q.bin"

// Buffers para armazenar os dados lidos dos arquivos binários
static uint8_t  image_buffer [IMAGE_SIZE];
static uint16_t weights_buffer[W_IN_COUNT];
static uint16_t bias_buffer [B_COUNT];
static uint16_t beta_buffer [BETA_COUNT];

// Caminho da imagem atual e flags de controle de estado
static char image_path[256] = "bins/4.bin";
static int hardware_init = 0; // 1 se o hardware foi inicializado
static int img_carregada = 0; // 1 se a imagem foi carregada
static int pesos_carregados = 0; // 1 se os pesos foram acerrgados
static int bias_carregado = 0; // 1 se o bias foi carregado
static int beta_carregado = 0; // 1 se o beta foi carregado

// Carrega arquivo binário no buffer
static int carregar_arquivo(const char *caminho, void *buffer, size_t tamanho) {
    FILE *f = fopen(caminho, "rb"); // Abre o arquivo em modo leitura binária
    if (!f) {
        printf("[ERRO] Nao foi possivel abrir: %s\n", caminho);
        fflush(stdout);
        return -1;
    }
    size_t lido = fread(buffer, 1, tamanho, f); // lê tamanho (bytes) do arquivo para o buffer
    fclose(f); // Fechamento do arquivo
    if (lido != tamanho) {
        printf("[ERRO] Leitura incompleta em %s: %zu/%zu bytes\n",
                caminho, lido, tamanho);
                fflush(stdout);
        return -1; // Se não leu exatamente o esperado
    }
    printf("[OK] Arquivo carregado: %s\n", caminho);
    return 0; // Se deu tudo certo
}

// Função para realizar a inferência completa em sequência automática
static void inferencia_completa(void) {
    printf("\n--- Iniciando inferencia completa ---\n");

    if (!hardware_init) { // Verifica se o hardware já está inicializado
        int ret = iniciar();
        if (ret != 0) {
            printf( "[ERRO] Falha ao inicializar hardware (cod %d)\n", ret);
            fflush(stdout);
            return;
        }
        hardware_init = 1;
        printf("[OK] Hardware inicializado\n");
    }
    
    // Exigências do coprocessador
    resetar();
    limpar();
    printf("[OK] Reset e limpeza aplicados\n");

    // Envio da imagem
    if (carregar_arquivo(image_path, image_buffer, IMAGE_SIZE) != 0) return;
    send_image(image_buffer);
    printf("[OK] Imagem enviada\n");

    // Envio dos pesos
    if (carregar_arquivo(WEIGHTS_FILE, weights_buffer, W_IN_BYTES) != 0) return;
    send_weights(weights_buffer, W_IN_COUNT);
    printf("[OK] Pesos enviados\n");

    // Envio do bias
    if (carregar_arquivo(BIAS_FILE, bias_buffer, B_BYTES) != 0) return;
    send_bias(bias_buffer, B_COUNT);
    printf("[OK] Bias enviado\n");

    // Envio do beta
    if (carregar_arquivo(BETA_FILE, beta_buffer, BETA_BYTES) != 0) return;
    send_beta(beta_buffer, BETA_COUNT);
    printf("[OK] Beta enviado\n");

    // Inicia a inferência com o start
    send_start();
    printf("[OK] Inferencia iniciada, aguardando resultado...\n");

    // Polling para ler o data_out
    polling();
    int digito = ler_resultado();
    printf("\n>>> Digito predito: %d <<<\n\n", digito);
}

// Exibição do menu
static void exibir_menu(void) {
    printf("\n---------- ELM Digit Classifier ----------\n");
    printf("  Status do hardware: %s\n", hardware_init ? "[INICIALIZADO]" : "[NAO INICIALIZADO]");
    printf("\n  [1] Executar inferencia completa (automatico)\n");
    printf("  [2] Inicializar hardware\n");
    printf("  [3] Resetar coprocessador\n");
    printf("  [4] Limpar flags (Done/Busy/Error)\n");
    printf("  [5] Carregar e enviar imagem\n");
    printf("  [6] Carregar e enviar pesos\n");
    printf("  [7] Carregar e enviar bias\n");
    printf("  [8] Carregar e enviar beta\n");
    printf("  [9] Iniciar inferencia (Start)\n");
    printf("  [10] Aguardar resultado (Polling)\n");
    printf("  [11] Ler resultado\n");
    printf("  [12] Fechar hardware\n");
    printf("  [13] Alterar caminho da imagem (atual: %s)\n", image_path);
    printf("  [0] Sair\n");
    printf("\nNumero da opcao desejada: ");
}

// Funcao principal
int main(void) {
    int opcao;

    while (1) {
        exibir_menu();

        // Valida a entrda do usuario
        if (scanf("%d", &opcao) != 1) {
            while (getchar() != '\n');
            printf("[ERRO] Entrada invalida. Digite um numero.\n");
            continue;
        }

        // Switch case que chama a respectiva funcao escolhida pelo usuario
        // Faz a verificacao de inicializacao do hardware
        switch (opcao) {

            case 0:
                if (hardware_init) { fechar(); printf("[OK] Hardware fechado.\n"); }
                printf("Encerrando.\n");
                return 0;

            case 1:
                inferencia_completa();
                break;

            case 2:
                if (hardware_init) { printf("[AVISO] Hardware ja inicializado.\n"); break; }
                {
                    int ret = iniciar();
                    if (ret == 0) { hardware_init = 1; printf("[OK] Hardware inicializado.\n"); }
                    else {printf( "[ERRO] Falha ao inicializar (cod %d).\n", ret);
                    fflush(stdout);}
                }
                break;

            case 3:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                resetar();
                printf("[OK] Reset aplicado.\n");
                break;

            case 4:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                limpar();
                printf("[OK] Flags limpas.\n");
                break;

            case 5:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                if (carregar_arquivo(image_path, image_buffer, IMAGE_SIZE) == 0) {
                    send_image(image_buffer);
                    img_carregada = 1;
                    printf("[OK] Imagem enviada.\n");
                }
                break;

            case 6:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                if (carregar_arquivo(WEIGHTS_FILE, weights_buffer, W_IN_BYTES) == 0) {
                    send_weights(weights_buffer, W_IN_COUNT);
                    pesos_carregados = 1;
                    printf("[OK] Pesos enviados.\n");
                }
                break;

            case 7:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                if (carregar_arquivo(BIAS_FILE, bias_buffer, B_BYTES) == 0) {
                    send_bias(bias_buffer, B_COUNT);
                    bias_carregado = 1;
                    printf("[OK] Bias enviado.\n");
                }
                break;

            case 8:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                if (carregar_arquivo(BETA_FILE, beta_buffer, BETA_BYTES) == 0) {
                    send_beta(beta_buffer, BETA_COUNT);
                    beta_carregado = 1;
                    printf("[OK] Beta enviado.\n");
                }
                break;

            case 9:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                send_start();
                printf("[OK] Inferencia iniciada.\n");
                break;

            case 10:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                printf("Aguardando Done...\n");
                polling();
                printf("[OK] Done recebido.\n");
                break;

            case 11:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                printf("\n>>> Digito predito: %d <<<\n\n", ler_resultado());
                break;

            case 12:
                if (!hardware_init) { printf("[AVISO] Hardware nao inicializado.\n"); break; }
                fechar();
                hardware_init = img_carregada = pesos_carregados =
                                bias_carregado = beta_carregado = 0;
                printf("[OK] Hardware fechado.\n");
                break;
            
            case 13:
                printf("Novo caminho da imagem: ");
                scanf("%255s", image_path);
                printf("[OK] Caminho atualizado para: %s\n", image_path);
                break;

            case 14:
                

            default:
                printf("[ERRO] Opcao invalida.\n");
                break;
        }
    }
    return 0;
}
