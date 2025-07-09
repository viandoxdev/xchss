; This file handles parsing of bytes sequences to keystroke ID (see KEY_ macros in constants.inc)
; macro magic FTW
%include "constants.inc"
	section .text

	extern input_buf
	extern input_buf_used
	extern input_buf_offset

	global pop_keystroke

; Read input buffer and get one keystroke
; cobblers: rax, rdx, rsi, rdi
; rax -> keystroke id (see KEY_ macros), or 0 if none
pop_keystroke:
	xor edi, edi
	xor eax, eax
	xor edx, edx

	; load address of buffer and size (number of bytes is used - offset)
	mov dil, byte [rel input_buf_used]
	mov al, byte [rel input_buf_offset]
	lea rsi, [rel input_buf]
	add rsi, rax

	cmp rdi, rax ; check if there's any bytes available
	jne pk_bytes_available

	; no keystrokes, clear out buffer and return 0
	mov byte [rel input_buf_offset], 0
	mov byte [rel input_buf_used], 0
	xor eax, eax
	ret

	pk_bytes_available:

	; match against all keys
%assign i 1
%rep key_count
	; make sure there's enough data in the buffer to match
	cmp rdi, KEY_%[i]_LEN
	jl pk_%[i]_end

	xor edx, edx

	; match each byte individually: we don't  do conditionals here
	; we just xor every byte and or all the results. If the result is 0
	; we have a match, otherwise at least one bit was different
	%assign j 1
	%rep KEY_%[i]_LEN
	
	mov al, byte [rsi + j - 1]
	xor al, KEY_%[i]_BYTES_%[j]
	or rdx, rax

	%assign j j+1
	%endrep

	jnz pk_%[i]_end
	; we have a match

	; advance buffer by the amount of bytes matched
	add byte [rel input_buf_offset], KEY_%[i]_LEN
	mov rax, i
	ret

	pk_%[i]_end:
	; go onto the next key
%assign i i+1
%endrep

	; no key was matched, but there is data in the buffer

	; discard first byte
	inc byte [rel input_buf_offset]
	; start again from the top
	jmp pop_keystroke
