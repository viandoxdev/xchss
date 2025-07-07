ASFLAGS=-f elf64 -F dwarf -g
LDFLAGS=--nostd -z noexecstack
BIN=xchss
OBJECTS:=$(patsubst %.asm,%.o,$(wildcard *.asm))

run: all
	./$(BIN)

build: $(BIN)
all: $(BIN)

syscalls.inc: syscalls.sh
	./syscalls.sh > syscalls.inc

%.o: %.asm
	nasm $(ASFLAGS) $< -o $@
$(BIN): syscalls.inc symbols.o $(OBJECTS) 
	ld $(OBJECTS) symbols.o $(LDFLAGS) -o $@
symbols.o: symbols.h
	gcc -fdebug-types-section -Og -x c -g -O0 -c $< -o $@
debug: symbols.o all
	# can't use gdb -s as it is bugged
	gdb \
		--ex 'tty /dev/pts/3' \
		--ex 'set confirm no' \
		--ex 'add-symbol-file symbols.o' \
		--ex 'set confirm yes' \
		$(BIN)

debug-server: symbols.o all
	gdbserver localhost:8664 $(BIN)
debug-client: symbols.o all
	gdb \
		--ex 'target remote localhost:8664' \
		--ex 'set confirm no' \
		--ex 'add-symbol-file symbols.o' \
		--ex 'set confirm yes' \
	$(BIN)

clean:
	rm *.o
	rm $(BIN)
	rm syscalls.inc

.PHONY: clean build all run
