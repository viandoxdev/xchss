; This handles all moves related logic (generation, applying, ...)
%use ifunc
%include "constants.inc"
	section .bss
	align 8
moves_buffer:	resb 32
board:		resb 64
	section .text

	global resolve_immediate_attacks

; Set all the immediate attacks bits of a board, used for full move resolution
; cobblers: rbx, rcx, rdx, rdi, rsi, r8, r9
; rax <- board address
resolve_immediate_attacks:
	xor ebx, ebx

	; make 64 bit mask that gets rid of a whole rank's attack bits
	%xdefine M8 PIECE_BITS ^ PIECE_ATTACK_BITS ; 8 bit mask
	%assign M64 0 
	%rep 8 ; copy 8 times
	%assign M64 M64<<8 | M8
	%endrep
	; get mask in rdx (can't use 64bit immediates on and)
	mov rdx, M64
	%undef M8
	%undef M64

	; clear attack bits on all 8 ranks
	%assign i 0
	%rep 8
	and qword [rax + i], rdx
	%assign i i+8
	%endrep

	; resolve new attacks
	mov rsi, 7 ; rank index
	ria_rank_loop:
	mov rdi, 7 ; file index
		ria_file_loop:

		; get piece in rbx
		lea rdx, [rax + rsi * 8]
		mov bl, byte [rdx + rdi]

		; get bit in rcx
		mov rcx, rbx
		and rcx, PIECE_COLOR_BIT
		mov rdx, PIECE_ATTACK_WHITE
		shl rdx, cl
		mov rcx, rdx

		; jump to correct piece handler
		mov rdx, rbx
		and rdx, PIECE_TYPE_BITS | PIECE_COLOR_BIT
		jmp qword [ria_jmp_table + rdx * 8]
		
		ria_jmp_table:
		dq ria_loop_end, ria_loop_end
		dq ria_piece_white_pawn,	ria_piece_black_pawn
		dq ria_piece_white_knight,	ria_piece_black_knight 
		dq ria_piece_white_bishop,	ria_piece_black_bishop 
		dq ria_piece_white_rook,	ria_piece_black_rook
		dq ria_piece_white_queen,	ria_piece_black_queen 
		dq ria_piece_white_king,	ria_piece_black_king

		; set piece attack bit depending on color, 
		; making sure not to over/underflow the board
		; cobblers: rdx
		; %1 <- x offset
		; %2 <- y offset
		; rcx <- bit to set
		; rdi <- piece file
		; rsi <- piece rank
		%macro attack 2
		cmp rdi, -%1
		jl %%skip
		cmp rdi, 7 - %1
		jg %%skip
		cmp rsi, -%2
		jl %%skip
		cmp rsi, 7 - %2
		jg %%skip

		lea rdx, [rax + rsi * 8 + (%2 * 8)]
		or byte [rdx + rdi + %1], cl
		%%skip:
		%endmacro

		; set piece attack bit depending on color, 
		; making sure not to over/underflow the board.
		; attacks in a line until a piece blocks
		; cobblers: rdx, r8, r9
		; %1 <- x increment
		; %2 <- y increment
		; rcx <- bit to set
		; rdi <- piece file
		; rsi <- piece rank
		%macro attack_line 2
		mov r8, rdi
		mov r9, rsi

		%%loop:
		; check if would be out of bounds
		cmp r8, -%1
		jl %%end
		cmp r8, 7 - %1
		jg %%end
		cmp r9, -%2
		jl %%end
		cmp r9, 7 - %2
		jg %%end

		; increment
		add r8, %1
		add r9, %2

		; set attack bit
		lea rdx, [rax + r9 * 8]
		or byte [rdx + r8], cl
		; load piece in dl, continue while no piece
		mov dl, byte [rdx + r8]
		test dl, PIECE_TYPE_BITS
		jz %%loop

		%%end:
		%endmacro
		
		ria_piece_white_pawn:
			attack -1, -1
			attack  1, -1
			jmp ria_loop_end

		ria_piece_black_pawn:
			attack -1,  1
			attack  1,  1
			jmp ria_loop_end

		ria_piece_white_knight:
		ria_piece_black_knight: ; same code for both
			attack -1, -2
			attack  1, -2
			attack -1,  2
			attack  1,  2
			attack -2, -1
			attack  2, -1
			attack -2,  1
			attack  2,  1
			jmp ria_loop_end

		ria_piece_white_bishop:
		ria_piece_black_bishop:
			attack_line -1, -1
			attack_line  1, -1
			attack_line -1,  1
			attack_line  1,  1
			jmp ria_loop_end

		ria_piece_white_rook:
		ria_piece_black_rook:
			attack_line  0, -1
			attack_line  0,  1
			attack_line -1,  0
			attack_line  1,  0
			jmp ria_loop_end

		ria_piece_white_queen:
		ria_piece_black_queen:
			attack_line  0, -1
			attack_line  0,  1
			attack_line -1,  0
			attack_line  1,  0
			attack_line -1, -1
			attack_line  1, -1
			attack_line -1,  1
			attack_line  1,  1
			jmp ria_loop_end

		ria_piece_white_king:
		ria_piece_black_king:
			attack -1, -1
			attack  0, -1
			attack  1, -1
			attack -1,  0
			attack  1,  0
			attack -1,  1
			attack  0,  1
			attack  1,  1
			jmp ria_loop_end

		ria_loop_end:
		dec rdi
		jns ria_file_loop
	dec rsi
	jns ria_rank_loop

	ret

; apply a (potentially illegal) move to a board
; cobblers: rax, rbx, rcx, rdx, rdi, rsi, r8, r9
; rsi <- board address
; ax <- square where the piece doing the move is
; dl <- move
apply_move:
	mov dl, cl
	and rcx, MOVE_TYPE_BITS

	am_move_move:
	cmp rcx, MOVE_TYPE_MOVE
	jne am_move_capture

	xor r8d, r8d
	xor r9d, r9d
	xor edi, edi
	xor esi, esi

	; get destination file and rank in r8 and r9
	; and source file and rank in rax and rdi
	mov dl, r8b
	mov dl, r9b
	and r8b, MOVE_FILE_BITS
	and r9b, MOVE_RANK_BITS
	shr r8b, MOVE_FILE_OFFSET
	shr r9b, MOVE_RANK_OFFSET
	mov dil, ah
	movzx rax, al

	; apply move (remove piece from source and move in destination)
	lea rdx, [rsi + rdi * 8]
	mov cl, byte [rdx + rax]
	mov byte [rdx + rax], 0
	lea rdx, [rsi + r9 * 9]
	mov byte [rdx + r8], cl
	jmp am_move_end

	am_move_capture:
	cmp rcx, MOVE_TYPE_CAPTURE
	jne am_move_castle

	am_move_castle:
	cmp rcx, MOVE_TYPE_CASTLE
	jne am_move_promotion

	am_move_promotion:
	cmp rcx, MOVE_TYPE_PROMOTION
	jne am_move_end

	am_move_end:
	mov rax, rsi
	call resolve_immediate_attacks
	ret

; generate moves from a position and a piece
; cobblers: rax, rdx, r8, r9
; ax <- piece square
; rdi <- moves buffer (must be at least 32 bytes long)
; rsi <- board address
; rax -> number of moves
generate_moves:
	; get position in r8 and r9
	xor r8d, r8d
	xor r9d, r9d
	mov r8b, al
	; can't `mov r9b, ah` because rex prefix
	mov al, ah
	mov r9b, al

	; save buffer and get temporary buffer in rdi
	; rdi marks the end of that buffer (will be incremented)
	push rdi
	lea rdi, [rel moves_buffer]

	; get piece in dl
	lea rdx, [rax + r9 * 8]
	mov dl, [rdx + r8]

	; jump to correct label
	mov al, dl
	and rax, PIECE_TYPE_BITS | PIECE_COLOR_BIT
	jmp qword [gm_jmp_table + rax * 8]
	
	gm_jmp_table:
	dq gm_end, gm_end
	dq gm_piece_white_pawn,		gm_piece_black_pawn
	dq gm_piece_white_knight,	gm_piece_black_knight 
	dq gm_piece_white_bishop,	gm_piece_black_bishop 
	dq gm_piece_white_rook,		gm_piece_black_rook
	dq gm_piece_white_queen,	gm_piece_black_queen 
	dq gm_piece_white_king,		gm_piece_black_king

	gm_piece_white_pawn:
	gm_piece_black_pawn:
	gm_piece_white_knight:
	gm_piece_black_knight:
	gm_piece_white_bishop:
	gm_piece_black_bishop:
	gm_piece_white_rook:
	gm_piece_black_rook:
	gm_piece_white_queen:
	gm_piece_black_queen:
	gm_piece_white_king:
	gm_piece_black_king:

	gm_end:
	; compute length with start and end pointers 
	mov rax, rdi
	lea rdi, [rel moves_buffer]
	sub rax, rdi
	mov rdx, [rsp]

	; we have rax potential moves in (byte*) rdi 
	; we want them in (byte*) rdx
	test rax, rax
	jz gm_test_end
	gm_test_move_loop:
		

		inc rdi
		dec rax
		jz gm_test_move_loop

	gm_test_end:
	; get final length in rax
	pop rax
	sub rax, rdx
	neg rax
	ret
