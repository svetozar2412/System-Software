MISC=misc
SRC=src

emulator: ${SRC}/emulator.c
	gcc -g ${SRC}/emulator.c -o emulator

linker: ${SRC}/linker.c
	gcc -g ${SRC}/linker.c -o linker

assembler: lex.yy.c y.tab.c
	gcc -g lex.yy.c y.tab.c -o assembler
	rm lex.yy.c y.tab.c y.tab.h

${MISC}/lex.yy.c: ${MISC}/y.tab.c ${MISC}/assembler.l
	lex ${MISC}/assembler.l

${MISC}/y.tab.c: ${MISC}/assembler.y
	yacc -d ${MISC}/assembler.y

clean: 
	rm -rf lex.yy.c y.tab.c y.tab.h assembler assembler.dSYM
