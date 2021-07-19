NASM_FORMAT=elf64

des: des.o main.o
				gcc -I . -o des des.o main.o

des.o: des.asm
				nasm -f $(NASM_FORMAT) des.asm -o des.o

main.o: main.c
				gcc -c main.c -o main.o

clean:
				rm *.o
				rm des
