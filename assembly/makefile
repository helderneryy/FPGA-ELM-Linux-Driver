build:
	@gcc -marm -c main.c -o main.o
	@gcc -marm -c funcoes.s -o funcoes.o
	@gcc -marm main.o funcoes.o -o exe

run:
	sudo ./exe

test:
	bash teste_batch.sh

clean:
	@rm -f main.o funcoes.o exe

help:
	@echo ""
	@echo "Comandos disponíveis:"
	@echo "make build - Compila o projeto"
	@echo "make run - Executa o programa (com sudo)"
	@echo "make test - Roda o teste batch nas 100 imagens (10 de cada)"
	@echo "make clean - Remove arquivos compilados"
	@echo "make help - Mostra esta mensagem"
	@echo ""