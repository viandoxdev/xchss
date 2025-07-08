%include "constants.inc"
	section .bss
	alignb 8
drawing_board:
; address of board to draw
db_board:		resb 8 ;	(0:8)
; bitmask of features : 
;  0b0000000
;    │││││└┴─ current screen
;    ││││└─ selected square bit ┐
;    │││└─ target square bit    │ playing
;    ││└─ available squares bit │ screen
;    │└─ capturable pieces bit  │
;    └─ flip board bit          ╛
db_features:		resb 2 ; 	(8:2)

; positions:
; bytes    0:1
;       file:rank
db_selected_square:	resb 2 ; 	(10:2)
db_target_square:	resb 2 ;	(12:2)
db_moves_count:		resb 1 ;	(14:1)
db_captures_count:	resb 1 ;	(15:1)
; arrays of positions 
; (see db_selected_square)
db_moves_squares:	resb 8 ;	(16:8)
db_captures_squares:	resb 8 ;	(24:8)

%define INPUT_BUFFER_SIZE 64 ; <= 255
input_buf_used:		resb 1
input_buf_offset:	resb 1
input_buf:		resb INPUT_BUFFER_SIZE

	global drawing_board
	global db_board
	global db_features
	global db_selected_square
	global db_target_square
	global db_moves_count
	global db_captures_count
	global db_moves_squares
	global db_captures_squares

	global input_buf
	global input_buf_used
	global input_buf_offset

	section .data
align 8
pollfd:
	dd STDIN
	dw POLLIN
	dw 0

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
		db 0x1b, "[48;5;177m     " ; target square	(3)
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
	extern set_raw
	extern enter_alt
	extern leave_alt
	extern show_cursor
	extern unset_raw
	extern hide_cursor
	extern get_size
	extern set_cursor
	extern qprint_unsigned
	extern pop_keystroke
	extern pc_process

%define SQUARE_STYLE_WHITE 0
%define SQUARE_STYLE_BLACK 1
%define SQUARE_STYLE_SELECTED 2
%define SQUARE_STYLE_TARGET 3
%define SQUARE_STYLE_MOVE 4
%define SQUARE_STYLE_CAPTURE 5

; Draw draw board 
; cobblers: rax, rcx, rdx, rdi, rsi, r8, r9, r10
; arguments: see db_ symbols
draw_board:
	lea r10, [rel drawing_board]

	call clear_screen

	; check which screen we are onto
	mov ax, word [r10 + 8]
	and rax, DRAW_SCREEN_BITS

	cmp rax, SCREEN_PLAYING
	jne db_paused

	db_playing:

	call get_size

	mov rax, qword [rax]
	mov rdi, qword [rdi]

	shr rax, 1
	sub rax, 4

	shr rdi, 1
	sub rdi, 8

	push rax
	push rdi

	;TODO: Moves stuff, available moves, keep track of immediate attacks in game state (update default_board to match)

	; Stack now has 2 qwords : column of top right corner, line of top right corner

	xor rdi, rdi
	db_lines_loop:
		xor rsi, rsi
		db_columns_loop:
			; rsi is col, rdi is line

			; get piece index in rax (will go on stack on be popped in r8)
			mov rax, qword [r10]
			lea rax, [rax + rdi * 8]
			mov al, byte [rax + rsi]
			and rax, 0xf

			; load feature flags in r8
			mov r8, qword [r10 + 8]

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

			; get feature flags in r8
			mov r8, qword [r10 + 8]
			test r8, DRAW_SELECTED_BIT
			jz dblc_style_target
			
			; DRAW_SELECTED_BIT is set, check if the current square is selected
			mov dx, word [r10 + 10]
			cmp cx, dx
			mov r9, SQUARE_STYLE_SELECTED
			cmove rax, r9

			dblc_style_target:
			test r8, DRAW_TARGET_BIT
			jz dblc_style_moves

			; DRAW_TARGET_BIT is set, check if the current square is the target
			mov dx, word [r10 + 12]
			cmp cx, dx
			mov r9, SQUARE_STYLE_TARGET
			cmove rax, r9

			dblc_style_moves:
			test r8, DRAW_MOVES_BIT
			jz dblc_style_captures

			; DRAW_MOVES_BIT is set, check if the current square is one of the moves squares
			; get the address of the array in rsi and the last index in rdi
			xor rdi, rdi
			mov dil, byte [r10 + 14]
			mov rsi, qword [r10 + 16]

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
			mov dil, byte [r10 + 15]
			mov rsi, qword [r10 + 24]

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
		mov r8, qword [r10 + 8]
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
		mov r8, qword [r10 + 8]
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

	add rsp, 16

	ret

	db_paused:

	cmp rax, SCREEN_PAUSED
	jne db_main_menu

	ret

	db_main_menu:

	ret

	global _start
_start:
	; setup screen
	call hide_cursor
	call enter_alt
	call set_raw

	lea rsi, [rel drawing_board]

	lea rax, [rel default_board]
	mov qword [rsi], rax ; board
	mov word [rsi + 8], SCREEN_PLAYING | DRAW_SELECTED_BIT  ; features
	mov byte [rsi + 10], 0 ; selected_square file
	mov byte [rsi + 11], 0 ; selected_square rank

	; game loop
	main_loop:
		call draw_board

		; poll stdin with a timeout (to refresh the screen)
		mov rax, SYS_POLL
		lea rdi, [rel pollfd]
		mov rsi, 1
		mov rdx, 100
		syscall

		; if rax is 0 the poll ended on timeout, if rax > 0,
		; there is something to read, if rax < 0, error
		test rax, rax
		jz ml_no_input


		; read the input
		mov rax, SYS_READ
		mov rdi, STDIN
		lea rsi, [rel input_buf]
		mov rdx, INPUT_BUFFER_SIZE
		syscall

		mov byte [rel input_buf_used], al

		; input needs to be handled:
		; call out to agents, ...
		call pc_process

		cmp rax, AGENT_EXIT
		je main_loop_end

		ml_no_input:
		
		jmp main_loop
	main_loop_end:

	; leave screen
	call unset_raw
	call leave_alt
	call show_cursor

	mov rax, SYS_EXIT
	xor rdi, rdi
	syscall
