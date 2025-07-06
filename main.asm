%include "constants.inc"
	section .bss

	section .data

default_board:
	db 0b0011001, 0b0000101, 0b0000111, 0b0001011, 0b0001101, 0b0000111, 0b0000101, 0b0011001
	db 0b0000011, 0b0000011, 0b0000011, 0b0000011, 0b0000011, 0b0000011, 0b0000011, 0b0000011
	db 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000
	db 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000
	db 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000
	db 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000
	db 0b0000010, 0b0000010, 0b0000010, 0b0000010, 0b0000010, 0b0000010, 0b0000010, 0b0000010
	db 0b0011000, 0b0000100, 0b0000110, 0b0001010, 0b0001100, 0b0000110, 0b0000100, 0b0011000

	section .text

square_styles:	db 0x1b, "[48;5;016m     " ; white square	(0)
		db 0x1b, "[48;5;231m     " ; black square	(1)
		db 0x1b, "[48;5;063m     " ; selected square	(2)
		db 0x1b, "[48;5;219m     " ; target square	(3)
		db 0x1b, "[48;5;148m     " ; move square	(4)
		db 0x1b, "[48;5;160m     " ; capture square	(5)
reset_styles:	db 0x1b, "[00000000m     "

pieces:		db 0x1B, "[0093m         ", 
		db 0x1B, "[0090m         ", 
		db 0x1B, "[93m♟        ", 
		db 0x1B, "[90m♟        ", 
		db 0x1B, "[93m♞        ", 
		db 0x1B, "[90m♞        ", 
		db 0x1B, "[93m♝        ", 
		db 0x1B, "[90m♝        ", 
		db 0x1B, "[93m♜        ", 
		db 0x1B, "[90m♜        ", 
		db 0x1B, "[93m♛        ", 
		db 0x1B, "[90m♛        ", 
		db 0x1B, "[93m♚        ", 
		db 0x1B, "[90m♚        "
ranks:		db "12345678"
files:		db "ABCDEFGH"

	extern clear_screen
	extern get_size
	extern set_cursor
	extern qprint_unsigned

%define SQUARE_STYLE_WHITE 0
%define SQUARE_STYLE_BLACK 1
%define SQUARE_STYLE_SELECTED 2
%define SQUARE_STYLE_TARGET 3
%define SQUARE_STYLE_MOVE 4
%define SQUARE_STYLE_CAPTURE 5

%define FLIP_BOARD_BIT 0b10000
%define DRAW_CAPTURES_BIT 0b1000
%define DRAW_MOVES_BIT 0b100
%define DRAW_TARGET_BIT 0b10
%define DRAW_SELECTED_BIT 0b1

; Draw draw board 
; cobblers: rax, rcx, rdx, rdi, rsi, r8, r9
;  rax -> bitmask of features : 
;           0b00000
;             ││││└─ selected square bit
;             │││└─ target square bit
;             ││└─ available squares bit
;             │└─ capturable pieces bit
;             └─ flip board bit
;  rdi -> address of the board
;
; stack arguments:
;   offset:size │ meaning
;           0:1 │ column of selected square
;           1:1 │ line of selected square
;           2:1 │ column of target square
;           3:1 │ line of target square
;           4:1 │ count of moves squares
;           5:1 │ count of captures squares
;           6:2 │ zeros (padding)
;           8:8 │ address of moves squares array
;          16:8 │ address of captures squares array
; arrays:
;  both arrays are of the following format (2 bytes per element)
;   0x0000
;     ││└┴─ (byte) column of square
;     └┴─ (byte) line of square
draw_board:
	push rax
	push rdi

	call clear_screen
	call get_size

	mov rax, qword [rax]
	mov rdi, qword [rdi]

	shr rax, 1
	sub rax, 4

	shr rdi, 1
	sub rdi, 8

	push rax
	push rdi

	; Stack now has 4 qwords : features bitflags, board address, column of top right corner, line of top right corner

	xor rdi, rdi
	db_lines_loop:
		xor rsi, rsi
		db_columns_loop:
			; rsi is col, rdi is line

			; get piece index in rax (will go on stack on be popped in r8)
			mov rax, qword [rsp + 16]
			lea rax, [rax + rdi * 8]
			mov al, byte [rax + rsi]
			and rax, 0xf

			; load feature flags in r8
			mov r8, qword [rsp + 24]

			push rdi
			push rsi
			push rax

			; load position of top left corner of board in rax, rdx
			mov rax, qword [rsp + 24]
			mov rdx, qword [rsp + 32]

			; check flip board bit
			and r8, FLIP_BOARD_BIT
			jz dblc_set_cursor

			; didn't jump, board is flipped
			neg rsi
			neg rdi
			add rsi, 7
			add rdi, 7
			
			dblc_set_cursor:
			add rax, rsi 
			add rax, rsi ; Add rsi twice because each tile is 2×1
			add rdx, rdi
			call set_cursor

			; Load color of square in rax (0 -> white, 1 -> black)
			mov rax, 1
			add rax, qword [rsp + 8]
			add rax, qword [rsp + 16]
			and rax, 1
			
			; square features

			; we will put the current square in cx, and the square to match against in dx
			xor rcx, rcx
			xor rdx, rdx

			; get current square position in cx (bytes 0-1 of rcx)
			mov cl, byte [rsp + 8]
			mov ch, byte [rsp + 16]
			debug_start:

			mov r8, qword [rsp + 48]
			test r8, DRAW_SELECTED_BIT
			jz dblc_style_target
			
			; DRAW_SELECTED_BIT is set, check if the current square is selected
			mov dx, word [rsp + 64]
			cmp cx, dx
			mov r9, SQUARE_STYLE_SELECTED
			cmove rax, r9

			dblc_style_target:
			test r8, DRAW_TARGET_BIT
			jz dblc_style_moves

			; DRAW_TARGET_BIT is set, check if the current square is the target
			mov dx, word [rsp + 66]
			cmp cx, dx
			mov r9, SQUARE_STYLE_TARGET
			cmove rax, r9

			dblc_style_moves:
			test r8, DRAW_MOVES_BIT
			jz dblc_style_captures

			; DRAW_MOVES_BIT is set, check if the current square is one of the moves squares
			; get the address of the array in rsi and the last index in rdi
			xor rdi, rdi
			mov dil, byte [rsp + 68]
			mov rsi, qword [rsp + 72]

			; skip if length is 0
			dec rdi
			js dblc_style_captures

			dblcsm_loop:
				; load square and compare, if matches, set style and end loop
				mov dx, word [rsi + rdi * 2]
				cmp cx, dx
				mov r9, SQUARE_STYLE_MOVE
				cmove rax, r9
				mov r9, 0
				cmove rdi, r9
				
				dec rdi
				jns dblcsm_loop

			dblc_style_captures:
			test r8, DRAW_CAPTURES_BIT
			jz dblc_style_done

			; DRAW_CAPTURES_BIT is set, check if the current square is one of the capture squares
			; get the address of the array in rsi and the last index in rdi
			xor rdi, rdi
			mov dil, byte [rsp + 69]
			mov rsi, qword [rsp + 80]

			dec rdi
			js dblc_style_done

			dblcsc_loop:
				; load square and compare, if matches, set style and end loop
				mov dx, word [rsi + rdi * 2]
				cmp cx, dx
				mov r9, SQUARE_STYLE_CAPTURE
				cmove rax, r9
				mov r9, 0
				cmove rdi, r9
				
				dec rdi
				jns dblcsc_loop

			dblc_style_done:

			; Get corresponding style pointer in rsi
			lea rsi, [rel square_styles]
			shl rax, 4
			lea rsi, [rsi + rax]
			mov rdx, 11

			; Print style
			mov rax, SYS_WRITE
			mov rdi, STDOUT
			syscall

			; get piece index in r8
			pop r8

			; Print piece
			mov rax, SYS_WRITE
			mov rdi, STDOUT
			lea rsi, [rel pieces]
			shl r8, 4
			lea rsi, [rsi + r8]
			mov rdx, 9
			syscall
			
			pop rsi
			pop rdi

			inc rsi
			cmp rsi, 8
			jl db_columns_loop

		; save rdi
		mov r8, rdi

		; reset styles
		mov rax, SYS_WRITE
		mov rdi, STDOUT
		lea rsi, [rel reset_styles]
		mov rdx, 11
		syscall
		
		; restore rdi
		mov rdi, r8

		inc rdi
		cmp rdi, 8
		jl db_lines_loop

	; draw ranks
	mov rsi, 7
	db_ranks_loop:
		; load flags in r8
		mov r8, qword [rsp + 24]
		push rsi

		and r8, FLIP_BOARD_BIT
		jnz dbr_set_cursor
		
		; board isn't flipped
		neg rsi
		add rsi, 7
		
		dbr_set_cursor: ; set cursor
		mov rax, qword [rsp + 8]
		mov rdx, qword [rsp + 16]
		sub rax, 2
		add rdx, rsi
		call set_cursor

		; write rank
		mov rax, SYS_WRITE
		mov rdi, STDOUT
		lea rsi, [rel ranks]
		add rsi, qword [rsp]
		mov rdx, 1
		syscall

		; loop
		pop rsi
		dec rsi
		jns db_ranks_loop 

	; draw files
	mov rsi, 7
	db_files_loop:
		; load flags in r8
		mov r8, qword [rsp + 24]
		push rsi

		and r8, FLIP_BOARD_BIT
		jz dbf_set_cursor
		
		; board is flipped
		neg rsi
		add rsi, 7
		
		dbf_set_cursor: ; set cursor
		mov rax, qword [rsp + 8]
		mov rdx, qword [rsp + 16]
		add rax, rsi
		add rax, rsi
		add rdx, 8
		call set_cursor

		; write file
		mov rax, SYS_WRITE
		mov rdi, STDOUT
		lea rsi, [rel files]
		add rsi, qword [rsp]
		mov rdx, 1
		syscall

		; loop
		pop rsi
		dec rsi
		jns db_files_loop 

	add rsp, 32

	ret

	global _start
_start:
	mov rax, 0x0100010101020103
	push rax
	mov r8, rsp
	mov rax, 0x020702050103
	push rax
	mov r9, rsp

	mov rax, 0x030400010000
	push r9
	push r8
	push rax

	mov rax, FLIP_BOARD_BIT | DRAW_CAPTURES_BIT | DRAW_MOVES_BIT | DRAW_TARGET_BIT | DRAW_SELECTED_BIT
	lea rdi, [rel default_board]
	call draw_board

	add rsp, 40

	call get_size
	mov rax, qword [rax]
	mov rdx, qword [rdi]
	dec rax
	dec rdx
	call set_cursor

	mov rax, SYS_EXIT
	xor rdi, rdi
	syscall
