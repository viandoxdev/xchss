%include "constants.inc"
	section .bss
	alignb 8
drawing_board:
; address of board to draw
db_board:		resb 8 ;	(0:8)
; bitmask of features : 
;  0b0000000
;       ││└┴─ current screen
;       │└─ flip board bit
;       └─ draw immediate attacks
; address of the styles to use for the squares
db_board_style:		resb 8 ;	(8:8)
db_features:		resb 2 ; 	(16:2)

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

	global default_board
	global default_board_styles

	section .data
align 8
pollfd:
	dd STDIN
	dw POLLIN
	dw 0

default_board:
	db Pr__, Pn_b, Pb_b, Pq_b, Pk_b, Pb_b, Pn_b, Pr__
	db Pp_b, Pp_b, Pp_b, Pp_b, Pp_b, Pp_b, Pp_b, Pp_b
	db P__b, P__b, P__b, P__b, P__b, P__b, P__b, P__b
	db P___, P___, P___, P___, P___, P___, P___, P___
	db P___, P___, P___, P___, P___, P___, P___, P___
	db P_w_, P_w_, P_w_, P_w_, P_w_, P_w_, P_w_, P_w_
	db PPw_, PPw_, PPw_, PPw_, PPw_, PPw_, PPw_, PPw_
	db PR__, PNw_, PBw_, PQw_, PKw_, PBw_, PNw_, PR__

	section .text
default_board_styles:
	%rep 4
	times 4 db SQUARE_STYLE_WHITE, SQUARE_STYLE_BLACK
	times 4 db SQUARE_STYLE_BLACK, SQUARE_STYLE_WHITE
	%endrep

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
	extern posmap_inc
	extern posmap_clear
	extern resolve_immediate_attacks
	extern apply_move
	extern generate_moves

; Draw draw board 
; cobblers: rax, rcx, rdx, rdi, rsi, r8, r9, r10
; arguments: see db_ symbols
draw_board:
	lea r10, [rel drawing_board]

	call clear_screen

	; check which screen we are onto
	mov ax, word [r10 + 16]
	and rax, DRAW_SCREEN_BITS

	cmp rax, SCREEN_PLAYING
	jne db_paused

	db_playing:

	; get top left corner of board screen position in rax and rdi
	call get_size

	mov rax, qword [rax]
	mov rdi, qword [rdi]

	shr rax, 1
	sub rax, 4

	shr rdi, 1
	sub rdi, 8

	push rax
	push rdi

	; stack now has 2 qwords : column of top right corner, line of top right corner

	xor edi, edi
	db_lines_loop:
		xor esi, esi
		db_columns_loop:
			; rsi is col, rdi is line

			; get piece index in rax (will go on stack on be popped in r8)
			mov rax, qword [r10]
			lea rax, [rax + rdi * 8]
			mov al, byte [rax + rsi]
			and rax, 0xf

			; load feature flags in r8
			mov r8, qword [r10 + 16]

			push_many rdi, rsi, rax

			; load position of top left corner of board in rax, rdx
			mov rax, qword [rsp + 24]
			mov rdx, qword [rsp + 32]

			; check flip board bit
			test r8, FLIP_BOARD_BIT
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

			; index board styles, get style in al
			mov rax, qword [r10 + 8]
			mov rdi, [rsp + 16]
			mov rsi, [rsp + 8]
			lea rax, [rax + rdi * 8]
			movzx rax, byte [rax + rsi]

			; check for draw immediate (debug purposes)
			test word [r10 + 16], DRAW_IMMEDIATE_BIT
			jz dblc_draw_style

			; get style index in rax: (let x be the attack bits 00, 01, 10, or 11)
			mov rax, qword [r10]
			lea rax, [rax + rdi * 8]
			movzx rax, byte [rax + rsi]
			shr rax, PIECE_ATTACK_OFFSET
			dec rax
			and rax, 0b11

			dblc_draw_style:

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
		mov r8, qword [r10 + 16]
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
		mov r8, qword [r10 + 16]
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
	lea rax, [rel default_board_styles]
	mov qword [rsi + 8], rax ; board styles
	mov word [rsi + 16], SCREEN_PLAYING  ; features

	; game loop
	main_loop:
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


		; read the input into the buffer
		mov rax, SYS_READ
		mov rdi, STDIN
		lea rsi, [rel input_buf]
		mov rdx, INPUT_BUFFER_SIZE
		syscall

		mov byte [rel input_buf_used], al

		ml_no_input:

		call pc_process

		cmp rax, AGENT_EXIT
		je main_loop_end

		call draw_board
		
		jmp main_loop
	main_loop_end:

	; leave screen
	call unset_raw
	call leave_alt
	call show_cursor

	mov rax, SYS_EXIT
	xor edi, edi
	syscall
