; Utilities to print number (or just converting to string), used for UI and escape sequences
%include "constants.inc"
	section .data
qstrpad:	db "00000000000000000000000000"
; longest possible number in 64 bits
qstr:		db "00000000000000000000"
qstrl:		dq 0

	section .text
	global qstrpad
	global qstr
	global qstrl
	global qprint_signed
	global qprint_unsigned
	global qstring_signed
	global qstring_unsigned

; Reverse string at qstr of len qstrl
; cobblers: rax, rdx, rdi, rcx, r8
qstr_rev:
	lea r8, [rel qstr]
	mov rdx, [rel qstrl]

	; rax is the left end index
	; rdx is the right end index
	; r8 is the pointer
	xor eax, eax
	dec rdx

qstrrevloop:
	mov dil, byte [r8 + rax]
	mov cl, byte [r8 + rdx]
	mov byte [r8 + rdx], dil
	mov byte [r8 + rax], cl

	inc rax
	dec rdx

	cmp rax, rdx

	; important as rdx can be -1
	jl qstrrevloop

	ret
; Convert number in to string (unsigned)
; cobblers: rax, rcx, rdx, rsi, rdi, r8, r9
; rax -> number to convert
; qstr <- resulting string
; qstrl <- resulting string length
qstring_unsigned:
	lea r8, [rel qstr]
	lea r9, [rel qstrl]

	mov rdi, 10

	; rsi holds the length
	xor esi, esi

qstruloop:
	xor edx, edx

	; rax <- rax / 10
	; rdx <- rax % 10
	div rdi
	add rdx, '0'
	; put resulting char into the string
	mov byte [r8 + rsi], dl
	inc rsi

	test rax, rax
	jnz qstruloop
	
	; move length into qstrl
	mov [r9], rsi
	; reverse the string
	call qstr_rev

	ret
; Convert number in to string (signed)
; cobblers: rax, rcx, rdx, rsi, rdi, r8, r9
; rax -> number to convert
; qstr <- resulting string
; qstrl <- resulting string length
qstring_signed:
	; for comments see qstring_unsigned
	lea r8, [rel qstr]
	lea r9, [rel qstrl]

	; save to check for the sign later
	mov rax, rcx
	; compute absolute of rax
	neg rax
	cmovs rcx, rax

	mov rdi, 10
	xor esi, esi
qstrsloop:
	xor edx, edx
	div rdi
	add rdx, 48
	mov byte [r8 + rsi], dl
	inc rsi

	test rax, rax
	jnz qstrsloop

	; add minus sign at the end of the string
	mov byte [r8 + rsi], '-'
	; rdi is 0, rdx is 1
	xor edi, edi
	mov rdx, 1
	; set rdi to 1 if rcx is negative (rcx is the original number)
	test rcx, rcx
	cmovs rdx, rdi
	; add rdi into the length of the string
	add rsi, rdi
	
	mov [r9], rsi
	call qstr_rev
	ret
; Print number (unsigned)
; cobblers: rax, rcx, rdx, rsi, rdi, r8, r9
; rax -> number to print
qprint_unsigned:
	; convert %rax to string
	call qstring_unsigned
	mov rax, SYS_WRITE
	mov rdi, STDOUT
	lea rsi, [rel qstr]
	lea rdx, [rel qstrl]
	mov rdx, [rdx]
	syscall
	ret
; Print number (signed)
; cobblers: rax, rcx, rdx, rsi, rdi, r8, r9
; rax -> number to print
qprint_signed:
	call qstring_signed
	mov rax, SYS_WRITE
	mov rdi, STDOUT
	lea rsi, [rel qstr]
	lea rdx, [rel qstrl]
	mov rdx, [rdx]
	syscall
	ret
