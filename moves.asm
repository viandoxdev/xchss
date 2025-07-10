; This handles all moves related logic (generation, applying, ...)
%use ifunc
%include "constants.inc"
	section .bss
	align 8
moves_buffer:	resb 32
board:		resb 64
	section .text

	global resolve_immediate_attacks
	global apply_move
	global generate_moves

; Set all the immediate attacks bits of a board, used for full move resolution
; cobblers: rbx, rcx, rdx, rdi, rsi, r8, r9
; rax <- board address
resolve_immediate_attacks:
	xor ebx, ebx

	; make 64 bit mask that gets rid of a whole rank's attack bits
	; get mask in rdx (can't use 64bit immediates on and)
	mov rdx, (PIECE_BITS ^ PIECE_ATTACK_BITS) * BROADCAST_BQ

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

	; get source file in rax and source rank in rdi
	xor edi, edi
	mov al, r8b
	mov al, ah
	mov dil, al
	xor eax, eax
	mov al, r8b

	; save moving piece on stack, we will need it later
	; to update the special bits after the moves
	lea rdx, [rsi + rdi * 8]
	mov dl, byte [rdx + rax]
	movzx rdx, dl
	push rdx

	; get destination file and ranks
	; dl <- move (not promotion)
	; r8 -> destination file
	; r9 -> destination rank
	%macro unpack_dest 0
	xor r8d, r8d
	xor r9d, r9d

	mov r8b, dl
	mov r9b, dl
	and r8b, MOVE_FILE_BITS
	and r9b, MOVE_RANK_BITS
	shr r8b, MOVE_FILE_OFFSET
	shr r9b, MOVE_RANK_OFFSET
	%endmacro

	am_move_move:
	cmp rcx, MOVE_TYPE_MOVE
	jne am_move_capture

		unpack_dest

		; load piece in cl
		lea rdx, [rsi + rdi * 8]
		mov cl, byte [rdx + rax]

		mov rdx, PIECE_TYPE_BITS
		and dl, cl
		cmp dl, PIECE_PAWN
		jne ammm_continue

		mov rdx, rdi
		sub rdx, r9 ; get rank difference into rdx
		test rdx, 1
		jnz ammm_continue ; check parity of result

		; even number of squares : double advance
		or cl, PIECE_SPECIAL_BIT ; enable special bit (for en passant)
		
		ammm_continue:

		; apply move
		lea rdx, [rsi + rdi * 8]
		mov byte [rdx + rax], 0 ; remove piece
		lea rdx, [rsi + r9 * 8]
		mov byte [rdx + r8], cl ; put it back

		jmp am_move_end

	am_move_capture:
	cmp rcx, MOVE_TYPE_CAPTURE
	jne am_move_castle

		unpack_dest

		; get source piece into cl
		lea rdx, [rsi + rdi * 8]
		mov cl, byte [rdx + rax]

		; save piece color in rbx
		mov rbx, PIECE_COLOR_BIT
		and bl, cl

		; remove source piece from square
		mov byte [rdx + rax], 0

		; swap source piece and destination piece (if any)
		lea rdx, [rsi + r9 * 8]
		xchg cl, byte [rdx + r8]

		; test if we captured on an empty square
		test cl, cl
		jnz am_move_end

		; we have, we must be taking en passant.

		; get -1 if piece is white, +1 if piece is black in rbx
		dec rbx
		or rbx, 1

		; compute position of taken pawn
		sub r9, rbx

		; remove pawn
		lea rdx, [rsi + r9 * 8]
		mov byte [rdx + r8], 0

		jmp am_move_end

	am_move_castle:
	cmp rcx, MOVE_TYPE_CASTLE
	jne am_move_promotion

		unpack_dest

		; get signum of the difference between
		; source file and destination file, if king
		; castles to the left rbx is -1. otherwise it is +1
		mov rbx, r8
		sub rbx, rax
		sar rbx, 63
		or rbx, 1

		; take king from source square
		lea rdx, [rsi + rdi * 8]
		lea rdx, [rdx + rax]
		mov cl, byte [rdx]
		mov byte [rdx], 0

		; place king back 2 squares away from source
		mov cl, byte [rdx + rbx * 2]

		; take rook from destination square
		lea r9, [rsi + r9 * 8]
		mov cl, byte [r9 + r8]
		mov byte [r9 + r8], 0

		; put rook 1 square away from source
		mov byte [rdx + rbx], cl
		jmp am_move_end

	am_move_promotion:
	cmp rcx, MOVE_TYPE_PROMOTION
	jne am_move_end
		
		; overwrite piece type
		lea rdx, [rsi + rdi * 8]
		and byte [rdx + rax], (PIECE_BITS ^ PIECE_TYPE_BITS)
		and dl, PIECE_TYPE_BITS
		or byte [rdx + rax], dl
		
		jmp am_move_end

	am_move_end:

	; get moving piece into cl
	mov rcx, [rsp]

	; check if piece is a king
	mov dl, PIECE_TYPE_BITS
	and dl, cl
	cmp dl, PIECE_KING
	jne am_reset_pawn_en_passant

	; king moved, unset castling rights

	; turns off the special bits of all the friendly or enemy pieces
	; of a certain type
	; cobblers: rcx, xmm1, xmm2, xmm3, xmm4, xmm5
	; %1 <- type of piece
	; %2 <- 0 for friendly, 1 for enemy pieces
	; rsi <- board address
	;
	; stack arguments: 
	;  (0:1) moving piece
	;  (1:7) padding
	%macro disable_special_bit 2
	; get a special piece of the same or opposing color in cl
	mov rcx, [rsp]
	and cl, PIECE_COLOR_BIT
	%if %2
	xor cl, PIECE_COLOR_BIT
	%endif
	or cl, %1 | PIECE_SPECIAL_BIT

	; broadcast piece into xmm3
	movd xmm3, ecx
	punpcklbw xmm3, xmm3
	punpcklwd xmm3, xmm3
	pshufd xmm3, xmm3, 0

	; get mask (discard attack bits)
	mov rcx, (PIECE_BITS ^ PIECE_ATTACK_BITS) * BROADCAST_BQ
	movq xmm2, rcx
	punpckldq xmm2, xmm2

	; get mask (flips special bit)
	mov rcx, (PIECE_BITS ^ PIECE_ATTACK_BITS) * BROADCAST_BQ
	movq xmm4, rcx
	punpckldq xmm4, xmm4

	%assign off 0
	%rep 4

	; load 2 ranks
	movdqu xmm1, [rsi + off]
	; discard attack bits
	pand xmm1, xmm2
	; compare each byte, matching bytes become 0xFF, otherwise 0x00
	; -> makes a mask
	pcmpeqb xmm1, xmm3
	; get final mask (all special bits of friendly/enemy pieces)
	pand xmm1, xmm4
	; load ranks again
	movdqu xmm5, [rsi + off]
	; flip the special bits
	pxor xmm1, xmm5
	; store the changed ranks back
	movdqu [rsi + off], xmm1
	%assign off off+16
	%endrep
	%endmacro

	disable_special_bit PIECE_ROOK, 0

	am_reset_pawn_en_passant:
	disable_special_bit PIECE_PAWN, 1

	add rsp, 8

	mov rax, rsi
	call resolve_immediate_attacks
	ret

; generate moves from a position and a piece
; cobblers: rax, rcx, rdx, r8, r9
;  ax <- piece square
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
	lea rdx, [rsi + r9 * 8]
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

	; Add move with offset (if legal)
	; cobblers: rcx, rbx
	; %1 <- x offset
	; %2 <- y offset
	; %3 <- mode: 
	;        - move only [1], 
	;        - attack only (+ en passant) [2],
	;        - move and attack [3]
	; dl <- piece
	; r8 <- piece file
	; r9 <- piece rank
	; rsi <- board address
	%macro move_off 3
	; test x bounds
	%if %1 < 0
		cmp r8, -%1
		jl %%skip_move
	%elif %1 > 0
		cmp r8, 7-%1
		jg %%skip_move
	%endif

	; test y bounds
	%if %2 < 0
		cmp r9, -%2
		jl %%skip_move
	%elif %2 > 0
		cmp r9, 7-%2
		jg %%skip_move
	%endif

	; check if destination is occupied
	lea rcx, [rsi + r9 * 8 + %2 * 8]
	mov cl, byte [rcx + r8 + %1]
	test cl, PIECE_TYPE_BITS

	%if %3 = 1 ; move only

		jnz %%skip_move ; if occupied, skip
		; if not continue into the free block

	%elif %3 = 2 ; attack only (+ en passant)

		jnz %%occupied ; attack if we can
		; if not handle en passant

		; load piece at square one before destination
		lea rcx, [rsi + r9 * 8 + (%2 - 1) * 8]
		mov cl, byte [rcx + r8 + %1]
		and cl, (PIECE_BITS ^ PIECE_ATTACK_BITS) ; discard attack information

		; get piece match in bl, we want a pawn of the opposing color that
		; has the special bit set (can be taken en passant)
		mov bl, PIECE_COLOR_BIT
		and bl, cl
		xor bl, PIECE_COLOR_BIT ; get opposing color bit in bl
		or bl, PIECE_PAWN | PIECE_SPECIAL_BIT

		; check for such a piece, discard move if not
		cmp cl, bl
		jne %%skip_move

		; can take en passant
		
		; get move in cl
		mov rcx, r9
		add rcx, %2
		shl rcx, MOVE_RANK_OFFSET
		or rcx, r8
		add rcx, %1
		or rcx, MOVE_TYPE_CAPTURE

		; push move
		mov byte [rdi], cl
		inc rdi

		jmp %%skip_move
	%else ; can move and attack
		jnz %%occupied ; capture if possible
		
		; otherwise fall through with move
	%endif

	%if %3 != 2
		; no piece on destination square
		; get move in cl
		mov rcx, r9
		add rcx, %2
		shl rcx, MOVE_RANK_OFFSET
		or rcx, r8
		add rcx, %1
		or rcx, MOVE_TYPE_MOVE

		; push move
		mov byte [rdi], cl
		inc rdi
		
		%if %3 = 3
		jmp %%skip_move
		%endif
	%endif

	%if %3 > 1 ; only on attack only and attack and move modes
		%%occupied:
		; compare pieces color
		xor cl, dl
		test cl, PIECE_COLOR_BIT
		jz %%skip_move ; they are the same, can't move
		; there is an opposing piece on the target square

		; get move in cl
		mov rcx, r9
		add rcx, %2
		shl rcx, MOVE_RANK_OFFSET
		or rcx, r8
		add rcx, %1
		or rcx, MOVE_TYPE_CAPTURE

		; push move
		mov byte [rdi], cl
		inc rdi
	%endif

	%%skip_move:
	%endmacro

	; Add move with direction (if available)
	; cobblers: rcx, rbx
	; %1 <- x increment
	; %2 <- y increment
	; dl <- piece
	; r8 <- piece file
	; r9 <- piece rank
	; rsi <- board address
	%macro move_dir 2
	push_many r8, r9
	%%loop:
		; x bounds check
		%if %1 < 0
			cmp r8, -%1
			jl %%end
		%elif %1 > 0
			cmp r8, 7-%1
			jg %%end
		%endif

		; y bounds check
		%if %2 < 0
			cmp r9, -%2
			jl %%end
		%elif %2 > 0
			cmp r9, 7-%2
			jg %%end
		%endif

		; increment
		add r8, %1
		add r9, %2

		; get square in cl
		lea rcx, [rsi + r9 * 8]
		mov cl, byte [rcx + r8]
		
		test cl, PIECE_TYPE_BITS
		jz %%free

		; square is occupied

		; compare pieces color
		xor cl, dl
		test cl, PIECE_COLOR_BIT
		jz %%end ; same color -> can't move

		; get move in cl
		mov rcx, r9
		shl rcx, MOVE_RANK_OFFSET
		or rcx, r8
		or rcx, MOVE_TYPE_CAPTURE

		; push move
		mov byte [rdi], cl
		inc rdi

		jmp %%end

		%%free:
		; square is free, we can move onto

		; get move in cl
		mov rcx, r9
		shl rcx, MOVE_RANK_OFFSET
		or rcx, r8
		or rcx, MOVE_TYPE_MOVE

		; push move
		mov byte [rdi], cl
		inc rdi

		jmp %%loop
	%%end:
	pop_many r8, r9
	%endmacro

	gm_piece_white_pawn:
		%macro pawn_moves 1
		move_off -1, %1, 2
		move_off  1, %1, 2
		move_off  0, %1, 1

		%if %1 = -1
			test r9, r9
			jz %%promote
			cmp r9, 6
			jne %%end
		%else
			cmp r9, 7
			je %%promote
			cmp r9, 1
			jne %%end
		%endif
		
		; double advance
		move_off 0, %eval(2 * %1), 1
		jmp %%end

		%%promote:

		%assign i 1
		%rep 4
		; get move in cl
		mov rcx, %eval(%sel(i, PIECE_KNIGHT, PIECE_BISHOP, PIECE_ROOK, PIECE_QUEEN))
		or rcx, MOVE_TYPE_PROMOTION

		; push move
		mov byte [rdi], cl
		inc rdi

		%assign i i+1
		%endrep

		%%end:
		%endmacro

		pawn_moves -1
		jmp gm_end
	gm_piece_black_pawn:
		pawn_moves 1
		jmp gm_end
	gm_piece_white_knight:
	gm_piece_black_knight:
		move_off -1, -2, 3
		move_off  1, -2, 3
		move_off -1,  2, 3
		move_off  1,  2, 3
		move_off -2, -1, 3
		move_off  2, -1, 3
		move_off -2,  1, 3
		move_off  2,  1, 3
		jmp gm_end
	gm_piece_white_bishop:
	gm_piece_black_bishop:
		move_dir -1, -1
		move_dir  1, -1
		move_dir -1,  1
		move_dir  1,  1
		jmp gm_end
	gm_piece_white_rook:
	gm_piece_black_rook:
		move_dir  0, -1
		move_dir  0,  1
		move_dir -1,  0
		move_dir  1,  0
		jmp gm_end
	gm_piece_white_queen:
	gm_piece_black_queen:
		move_dir -1, -1
		move_dir  1, -1
		move_dir -1,  1
		move_dir  1,  1
		move_dir  0, -1
		move_dir  0,  1
		move_dir -1,  0
		move_dir  1,  0
		jmp gm_end
	gm_piece_white_king:
	gm_piece_black_king:
		move_off -1, -1, 3
		move_off  0, -1, 3
		move_off  1, -1, 3
		move_off -1,  0, 3
		move_off  1,  0, 3
		move_off -1,  1, 3
		move_off  0,  1, 3
		move_off  1,  1, 3

		%macro castles 1
		; get color in cl
		mov dl, cl
		and cl, PIECE_COLOR_BIT
		; get ATTACK bit mask for the whole rank
		mov rbx, PIECE_ATTACK_BLACK * BROADCAST_BQ
		shr rbx, cl

		; load attack bits into rbx
		and rbx, qword [rsi + r9 * 8]
		shl rbx, cl ; collapse branches
		
		; we want to get only the 3 squares we care about
		; in the low bytes of rbx:
		; king square, passing square, destination square

		%if %1 < 0 ; compute shifts depending on side
			mov rcx, r8
			sub rcx, 2
		%else
			; same logic
			mov rcx, r8
		%endif

		; shift and test
		shl rcx, 3
		shr rbx, cl
		and rbx, 0xFFFFFF
		; check if any of the opposing attak bits are set on these squares
		test rbx, rbx
		jnz %%skip_castle ; can't castle if under attack

		mov rbx, r8
		%%loop:
			; load piece in cl, discard attack information
			lea rcx, [rsi + r9 * 8]
			mov cl, byte [rcx + rbx]
			and cl, (PIECE_BITS ^ PIECE_ATTACK_BITS)
			
			; build match rook
			push rbx
			mov bl, PIECE_COLOR_BIT
			and bl, cl ; load piece color in bl
			or bl, PIECE_SPECIAL_BIT | PIECE_ROOK

			cmp cl, bl
			jne %%next

			; we found such a rook

			; get move in cl
			mov rcx, r9
			shl rcx, MOVE_RANK_OFFSET
			or cl, byte [rsp]
			or rcx, MOVE_TYPE_CASTLE

			; push move
			mov byte [rdi], cl
			inc rdi

			%%next:
			pop rbx
			add rbx, %1
			
			%if %1 < 0
				jns %%loop
			%else
				cmp rbx, 7
				jle %%loop
			%endif

		%%skip_castle:
		
		%endmacro

		castles -1 ; left
		castles  1 ; right
		jmp gm_end

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
		push_many rax, rdx, rdi, rsi, r8, r9
		
		; get move in dl
		mov dl, byte [rdi]

		; get position in ax
		mov al, r9b
		mov ah, al
		mov al, r8b

		; copy board and put address in rsi
		lea rdi, [rel board]
		mov_position rdi, rsi
		mov rsi, rdi

		call apply_move

		; now we need to check if the resulting board is valid.

		; first clear the special and attack bits (of the piece's own color)

		mov rax, PIECE_ATTACK_WHITE * BROADCAST_BQ

		; get piece color in cl
		mov r9, qword [rsp]
		mov r8, qword [rsp + 8]
		mov rsi, qword [rsp + 16]
		lea rdx, [rsi + r9 * 8]
		mov cl, byte [rdx + r8]
		and cl, PIECE_COLOR_BIT
		
		; update attack mask depending on color
		shl rax, cl
		mov rdx, PIECE_SPECIAL_BIT * BROADCAST_BQ
		or rax, rdx
		not rax
		; we now have the mask in rax

		; clear the bits
		%assign i 0
		%rep 8
		and qword [rsi + i], rax
		%assign i i+8
		%endrep

		; load attacked king in dl
		xor edx, edx
		mov dl, PIECE_ATTACK_BLACK ; set attack by other side bit
		shr dl, cl
		or dl, PIECE_KING ; set king type
		or dl, cl ; set color

		; broadcast piece into xmm1
		movd xmm1, edx
		punpcklbw xmm1, xmm1
		punpcklwd xmm1, xmm1
		pshufd xmm1, xmm1, 0

		xor edx, edx
		
		%assign off 0
		%rep 4
		; load 2 ranks into xmm2
		movdqu xmm2, [rsi + off]
		pcmpeqb xmm2, xmm1 ; compare each pieces
		pmovmskb eax, xmm2 ; get bitmask of matches
		or edx, eax ; or with result
		%assign off off+16
		%endrep

		; check if match, if any, this move is illegal
		test edx, edx
		jnz gmtml_end

		; move is legal!

		; get buffer addresses in rdi and rdx
		mov rdi, [rsp + 24]
		mov rdx, [rsp + 32]
		
		mov al, byte [rdi] ; get move
		mov byte [rdx], al ; push into final buffer
		inc qword [rsp + 32] ; increment pointer
		
		gmtml_end:
		
		pop_many rax, rdx, rdi, rsi, r8, r9

		inc rdi
		dec rax
		jnz gm_test_move_loop

	gm_test_end:
	; get final length in rax
	pop rax
	sub rax, rdx
	neg rax
	ret
