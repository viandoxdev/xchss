	section .bss
fx_hash_value:	resb 8
	section .text

	global fx_hash
	global fx_hasher_init
	global fx_hasher_hash
	global fx_hasher_finish

%define FX_ROTATE 5
%define FX_SEED 0x517cc1b727220a95

; Reset / initialize fx hasher state
; cobblers: nothing
fx_hasher_init:
	mov qword [rel fx_hash_value], 0
	ret
; Hash 8 bytes (fxhash)
; rax -> quad word to be hashed
; cobblers: rdx
; rax <- hasher state at this point
fx_hasher_hash:
	mov rdx, [rel fx_hash_value]
	rol rdx, FX_ROTATE
	xor rdx, rax
	mov rax, FX_SEED
	imul rax, rdx
	mov [rel fx_hash_value], rax
	ret
; Get the fx hasher state
; cobblers: none
; rax <- hasher state
fx_hasher_finish:
	mov rax, [rel fx_hash_value]
	ret

%macro fx_hash_rdx_into_rax 0
	rol rax, FX_ROTATE
	xor rax, rdx
	mov rdx, FX_SEED
	imul rax, rdx
%endmacro

; Fx hash bytes
; cobblers: rdx, rdi, rsi
; rsi -> pointer
; rdi -> size
; rax <- hash
fx_hash:
	; hasher state in rax
	xor rax, rax

	; loop hash as many 8 bytes as possible
	fhg8:
		cmp rdi, 8
		jl fhl8
		; load qword in rdx and hash into rax
		mov rdx, qword [rsi]
		fx_hash_rdx_into_rax
		; go to next qword in string
		sub rdi, 8
		add rsi, 8
		jmp fhg8

	fhl8:
	; 0 <= size (rdi) < 8

	cmp rdi, 4
	jl fhl4

	xor rdx, rdx ; technically unnecessary, but here for my sanity
	mov edx, dword [rsi]
	fx_hash_rdx_into_rax
	sub rdi, 4
	add rsi, 4

	fhl4:

	cmp rdi, 2
	jl fhl2

	xor rdx, rdx
	mov dx, word [rsi]
	fx_hash_rdx_into_rax
	sub rdi, 2
	add rsi, 2

	fhl2:

	cmp rdi, 1
	jl fhl1

	xor rdx, rdx
	mov dl, byte [rsi]
	fx_hash_rdx_into_rax
	dec rdi
	inc rsi

	fhl1:

	ret
