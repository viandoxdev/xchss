; Keyboard, terminal based agent
%use ifunc
%include "constants.inc"

	global pc_setup
	global pc_process

	extern pop_keystroke
	extern db_features
	extern drawing_board

pc_setup:
	ret

; process agent
; cobblers: rax, rdx, rcx, rdi, rsi
; rax -> AGENT_ value
pc_process:
	pcp_input_loop:
		call pop_keystroke
		test rax, rax
		jz pcp_end

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

		; get file/rank in rax, and 1 if FLIP_BOARD_BIT is set, 0 if not in rdx
		xor eax, eax
		mov rdx, FLIP_BOARD_BIT
		mov al, byte [rsi + 10 + %2]
		and dx, word [rsi + 8]
		shr rdx, ilog2(FLIP_BOARD_BIT)

		; dec rdx and or with 1 to get -1 or +1
		dec rdx
		or rdx, 1

		; conditional flip for up/down and left/right
		%if %3
		neg rdx
		%endif
		
		; prepare for cmov
		xor edi, edi
		mov rcx, 7
		; add offset and cmov to correct
		add rax, rdx
		cmovs rax, rdi
		cmp rax, 8
		cmove rax, rcx
		
		; update value
		mov byte [rsi + 10 + %2], al

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
		; update DRAW_TARGET_BIT:
		; If selected = target square
		;  DRAW_TARGET_BIT is flipped
		; Else
		;  DRAW_TARGET_BIT is set unconditionally
		xor word [rsi + 8], DRAW_TARGET_BIT ; always flip
		; compare selected and target squares
		mov rdx, DRAW_TARGET_BIT ; prepare rdx for cmov
		mov ax, word [rsi + 10]
		; sub instead of a compare so that we get 0 in rax if they are equal
		sub ax, word [rsi + 12]
		; if different set DRAW_TARGET_BIT
		cmovne rax, rdx
		or word [rsi + 8], ax

		; set target square to be the selected square
		mov ax, word [rsi + 10]
		mov word [rsi + 12], ax
		end_key

		begin_key ENTER
		end_key

		begin_key A
		xor word [rel db_features], FLIP_BOARD_BIT
		end_key

		pcpil_key_done:
		jmp pcp_input_loop

	pcp_end:
	mov rax, AGENT_CONTINUE
	ret
