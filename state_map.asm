; This file handles the position hashmap for the threefold repetition rule (https://en.wikipedia.org/wiki/Threefold_repetition)
; A position is represented by a 64 byte binary string.
%include "constants.inc"

; Must be multiple of 8
%define TABLE_MASK 0x1FF
%define TABLE_SIZE 512
	section .bss
table:	resb TABLE_SIZE * 65
	section .text

	extern fx_hash

	global posmap_clear
	global posmap_inc

; Clears the position map
; cobblers: rsi, rdi
posmap_clear:
	lea rsi, [rel table]
	mov rdi, TABLE_SIZE * 65
	add rdi, rsi

	pmc_loop:
		mov qword [rsi], 0
		add rsi, 8

		test rsi, rdi
		jne pmc_loop
	ret

; Increment position counter
; cobblers: r8, r9, rdx, rcx
; rsi -> position address
; rax <- number of occurences (after increment)
posmap_inc:
	; hash position
	mov r8, rsi
	mov rdi, 64
	call fx_hash
	mov rsi, r8
	and rax, TABLE_MASK
	
	lea rdx, [rel table]

	; rsi: position address
	; rax: slot index
	; rdx: table address

	pmi_probe:
		; get slot address in rcx (rcx points to position, rcx - 1 points to count)
		mov rcx, rax
		imul rcx, 65
		add rcx, rdx
		inc rcx
		
		; load count
		xor r8, r8
		mov r8b, byte [rcx - 1]
		test r8, r8
		jnz pmi_match_positions
		
		; the slot is empty, insert here
		mov byte [rcx - 1], 1
		mov_position rcx, rsi

		; return 1
		mov rax, 1
		ret

		pmi_match_positions:
		; slot is occupied, check if it is the right position
		cmp_position rcx, rsi
		jne pmi_next_probe

		; load count in rax, increment, store and return
		xor eax, eax
		mov al, byte [rcx - 1]
		inc rax
		mov byte [rcx - 1], al
		ret

		pmi_next_probe:
		; the slot is occupied with another entry, probe next slot
		inc rax
		and rax, TABLE_MASK
		jmp pmi_probe ; we don't handle full tables, won't happen
