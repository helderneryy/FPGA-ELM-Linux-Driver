# Testa todas as imagens do diretório 100Digitos e 
# gera resultados.txt em TEC499/TP01/KHR/

BASE_DIR="."
DIGITS_DIR="100Digitos"
OUTPUT_FILE="resultados.txt"

# Muda para o diretório do projeto
cd "$BASE_DIR" || { echo "[ERRO] Diretório $BASE_DIR não encontrado."; exit 1; }

# Compila o projeto
echo "Compilando..."
gcc -marm main.c funcoes.s -o exe
if [ $? -ne 0 ]; then
    echo "[ERRO] Falha na compilação."
    exit 1
fi
echo "[OK] Compilado."

# Monta a  sequência de inputs e lista de imagens
declare -a imagens  
input_tmp=$(mktemp) 

for digito in $(seq 0 9); do
    for img in "$DIGITS_DIR/$digito"/*.bin; do
        [ -f "$img" ] || continue
        imagens+=("$digito|$img")
        printf "13\n%s\n1\n" "$img" >> "$input_tmp"
    done
done
printf "0\n" >> "$input_tmp"

total=${#imagens[@]}
echo "Total de imagens encontradas: $total"

# Executa o programa uma única vez com todos os inputs
echo "Executando inferencias..."
saida=$(sudo ./exe < "$input_tmp" 2>&1)
rm "$input_tmp"
echo "[OK] Inferencias concluidas."

# Extrai predições da saída
predicoes=($(echo "$saida" | grep "Digito predito:" | sed 's/.*predito: \([0-9]*\).*/\1/'))

npred=${#predicoes[@]}
if [ "$npred" -ne "$total" ]; then
    echo "[AVISO] Número de predições ($npred) difere do total de imagens ($total)."
    echo "        Alguns resultados podem estar faltando ou incorretos."
fi

# Gera relatório
{
    echo "  ---------- Resultados da finais ---------- "
    echo "  Total de imagens: $total"

    acertos=0
    digito_atual=-1

    for i in "${!imagens[@]}"; do
        esperado="${imagens[$i]%%|*}"
        caminho="${imagens[$i]##*|}"
        arquivo=$(basename "$caminho")
        predito="${predicoes[$i]:-?}"

        # Cabeçalho da pasta ao mudar de dígito
        if [ "$esperado" != "$digito_atual" ]; then
            digito_atual="$esperado"
            echo ""
            echo "--- Pasta $digito_atual (digito esperado: $digito_atual) ---"
        fi

        if [ "$predito" = "$esperado" ]; then
            echo "  [OK]   $arquivo -> predito: $predito"
            acertos=$((acertos + 1))
        else
            echo "  [ERRO] $arquivo -> predito: $predito  (esperado: $esperado)"
        fi
    done

    echo ""
    echo "  Acertos: $acertos / $total"
    if [ "$total" -gt 0 ]; then
        pct=$(awk "BEGIN {printf \"%.1f\", $acertos * 100 / $total}")
        echo "  Acuracia: $pct%"
    fi

} | tee "$OUTPUT_FILE"

echo ""
echo "Relatorio salvo em: $BASE_DIR/$OUTPUT_FILE"
