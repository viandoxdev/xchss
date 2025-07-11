; Keyboard, terminal based agent
%use ifunc
%include "constants.inc"

%define DIRTY_STYLES_BIT	0b01
%define DIRTY_MOVES_BIT		0b10

	section .bss

moves_buffer:		resb 32
moves_buffer_len:	resb 1
	alignb 64
board_styles:		resb 64
	section .data
; board mapping squares to moves, each cell is the index of a move
; in moves_buffer, or 0xFF if none
	align 64
board_moves:		times 64 db 0xFF
; first byte is file, second is rank
selected_square:	db 0, 0
; first byte is file, second is rank, 0xFFFF if none
target_square:		db 0xFF, 0xFF
; what has change
;  0b000
;     │└─ styles need to be changed
;     └─ moves need to be recomputed
dirty_byte:	db DIRTY_STYLES_BIT | DIRTY_MOVES_BIT

	section .text
move_styles:
	db SQUARE_STYLE_MOVE ; move
	db SQUARE_STYLE_CAPTURE ; capture
	db SQUARE_STYLE_MOVE ; castling
	db SQUARE_STYLE_MOVE ; promotion

	global pc_setup
	global pc_process

	extern pop_keystroke
	extern db_features
	extern drawing_board
	extern default_board_styles
	extern generate_moves
	extern default_board
	extern apply_move

pc_setup:
	ret

; process agent
; cobblers: rax, rbx, rdx, rcx, rdi, rsi, r8, r9
; rax -> AGENT_ value
pc_process:
	pcp_input_loop:
		call pop_keystroke
		test rax, rax
		jz pcp_end ; no input

		; rsi will keep this value the whole time
		lea rsi, [rel drawing_board]

		; used to keep track of labels
		%assign key_num 0

		; begin a key handler, anything between this and the nearest end_key
		; will only be executed if rax matches KEY_%1
		%macro begin_key 1
		cmp rax, KEY_%1
		jne pcpil_key_%[key_num]_end
		%endmacro

		; see begin_key
		%macro end_key 0
		jmp pcpil_key_done
		pcpil_key_%[key_num]_end:
		%assign key_num key_num+1
		%endmacro

		; macro for arrow keys handleing
		; %1 <- direction of arrow (LEFT, RIGHT, UP, DOWN)
		; %2 <- 0 if affects file, 1 if affects rank
		; %3 <- 0 if should increase, 1 if decrease (on unflipped board)
		%macro handle_arrow 3
			begin_key %1_ARROW
			; update dirty flags
			or byte [rel dirty_byte], DIRTY_STYLES_BIT

			; get file/rank in rax
			%if %2
			movzx rax, byte [rel selected_square + 1]
			%else
			movzx rax, byte [rel selected_square]
			%endif

			; get 1 if FLIP_BOARD_BIT is set, -1 if not in rdx
			mov rdx, FLIP_BOARD_BIT
			and dx, word [rsi + 16]
			shr rdx, ilog2(FLIP_BOARD_BIT) ; 0 or 1
			dec rdx ; -1 or 0
			or rdx, 1 ; -1 or 1

			; conditional flip for up/down and left/right
			%if %3
			neg rdx
			%endif
			
			; prepare for cmov
			xor edi, edi
			mov rcx, 7
			; add offset and cmov to keep in bounds
			add rax, rdx
			cmovs rax, rdi
			cmp rax, 8
			cmove rax, rcx
			
			; update value
			%if %2
			mov byte [rel selected_square + 1], al
			%else
			mov byte [rel selected_square], al
			%endif

			end_key
		%endmacro
		
		begin_key ESC
			mov rax, AGENT_EXIT
			ret
		end_key

		handle_arrow LEFT,	0, 0
		handle_arrow RIGHT,	0, 1
		handle_arrow UP,	1, 0
		handle_arrow DOWN,	1, 1

		begin_key SPACE
			or byte [rel dirty_byte], DIRTY_MOVES_BIT | DIRTY_STYLES_BIT

			; get selected_square in ax, 0xFFFF (none) in dx
			mov ax, word [rel selected_square]
			mov dx, 0xFFFF

			cmp ax, word [rel target_square]
			cmove ax, dx ; set ax to none if selected_square = target_square

			mov word [rel target_square], ax ; write ax into target_square
		end_key

		begin_key ENTER
			pcpil_apply:
			movzx rax, word [rel target_square]
			cmp ax, 0xFFFF ; check if target exists
			je pcpil_skip_apply ; skip if not

			; get move index in dl
			lea rsi, [rel board_moves]
			movzx rdi, byte [rel selected_square + 1]
			lea rsi, [rsi + rdi * 8]
			mov dil, byte [rel selected_square]
			movzx rdx, byte [rsi + rdi]

			cmp dl, 0xFF
			je pcpil_skip_apply ; no move for this square, skip

			; get move into dl
			lea rsi, [rel moves_buffer]
			movzx rdx, byte [rsi + rdx]
			
			lea rsi, [rel default_board]

			call apply_move

			; set dirty because we changed the board
			or byte [rel dirty_byte], DIRTY_MOVES_BIT | DIRTY_STYLES_BIT
			mov word [rel target_square], 0xFFFF ; resest target square
			pcpil_skip_apply:
		end_key

		begin_key A
			xor word [rel db_features], FLIP_BOARD_BIT
		end_key

		begin_key B
			xor word [rel db_features], DRAW_IMMEDIATE_BIT
		end_key

		pcpil_key_done:
		jmp pcp_input_loop

	pcp_end:

	test byte [rel dirty_byte], DIRTY_MOVES_BIT
	jz pcp_recompute_styles

	; DIRTY_MOVES_BIT is set

	mov byte [rel moves_buffer_len], 0 ; empty moves buffer
	cmp word [rel target_square], 0xFFFF
	je pcp_recompute_styles ; no target_square, no moves to compute

	; compute the moves from the target_square
	mov ax, word [rel target_square]
	lea rdi, [rel moves_buffer]
	lea rsi, [rel default_board]
	call generate_moves
	mov byte [rel moves_buffer_len], al

	pcp_recompute_styles:
	test byte [rel dirty_byte], DIRTY_STYLES_BIT
	jz pcp_styles_done

	; reset styles
	lea rax, [rel default_board_styles]
	lea rdx, [rel board_styles]
	mov_position rdx, rax

	; reset moves map
	pcmpeqb xmm1, xmm1 ; get all 0xFF in xmm1
	movdqa [rel board_moves +  0], xmm1
	movdqa [rel board_moves + 16], xmm1
	movdqa [rel board_moves + 32], xmm1
	movdqa [rel board_moves + 48], xmm1

	; we will be only using dil, sil and dl below
	; we clear now for practical reason
	xor edi, edi
	xor esi, esi
	xor edx, edx

	; loop over the moves
	lea rax, [rel moves_buffer]
	movzx rcx, byte [rel moves_buffer_len]
	dec rcx
	js pcps_moves_done
	pcps_moves_loop:
		mov dl, byte [rax + rcx]
		and dl, MOVE_TYPE_BITS
		cmp dl, MOVE_TYPE_PROMOTION
		je pcpsml_promotion

		; move is move, capture or castling

		; get destination in rsi (file), rdi (rank)
		mov dil, byte [rax + rcx]
		mov sil, dil
		and dil, MOVE_RANK_BITS
		and sil, MOVE_FILE_BITS
		shr dil, MOVE_RANK_OFFSET
		shr sil, MOVE_FILE_OFFSET
		jmp pcpsml_end

		pcpsml_promotion:
		; for a promotion the destination square is the same as the piece
		mov dil, byte [rel target_square + 1]
		mov sil, byte [rel target_square]
			
		pcpsml_end:

		; get associated square style in dl
		shr dl, MOVE_TYPE_OFFSET
		lea rbx, [rel move_styles]
		mov dl, [rbx + rdx]

		; write style in board_styles
		lea rbx, [rel board_styles]
		lea rbx, [rbx + rdi * 8]
		mov byte [rbx + rsi], dl

		; write move in board_moves
		lea rbx, [rel board_moves]
		lea rbx, [rbx + rdi * 8]
		mov byte [rbx + rsi], cl

		dec rcx
		jns pcps_moves_loop
	pcps_moves_done:
	lea rax, [rel board_styles]

	; set selected square style
	mov sil, byte [rel selected_square + 1]
	lea rdx, [rax + rsi * 8]
	mov sil, byte [rel selected_square]
	mov byte [rdx + rsi], SQUARE_STYLE_SELECTED

	; check if target_square exists
	mov dx, word [rel target_square]
	cmp dx, 0xFFFF ; check if target_square exists
	je pcp_style_target_done ; jump if not

	; set target square style
	mov sil, byte [rel target_square + 1]
	lea rdx, [rax + rsi * 8]
	mov sil, byte [rel target_square]
	mov byte [rdx + rsi], SQUARE_STYLE_TARGET

	pcp_style_target_done:

	; set the current style board to board_styles
	lea rdx, [rel drawing_board]
	mov qword [rdx + 8], rax

	pcp_styles_done:
	; reset all dirty bits now that we've handled it all
	mov byte [rel dirty_byte], 0

	mov rax, AGENT_CONTINUE
	ret
