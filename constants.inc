; vi: ft=asm
%include "syscalls.inc"

%define STDIN 0
%define STDOUT 1

%define TIOCGWINSZ 0x5413
%define TCGETS 0x5401
%define TCSETS 0x5402

%define CLOCK_MONOTONIC 1
%define TIMER_ABSTIME 1

%define POLLIN 1

%define FLIP_BOARD_BIT 0b1000000
%define DRAW_CAPTURES_BIT 0b100000
%define DRAW_MOVES_BIT 0b10000
%define DRAW_TARGET_BIT 0b1000
%define DRAW_SELECTED_BIT 0b100

%define DRAW_SCREEN_BITS 0b11
%define SCREEN_MAIN_MENU 0b00
%define SCREEN_PLAYING 0b01
%define SCREEN_PAUSED 0b10

; enum for agent_process return value
%define AGENT_CONTINUE 0 ; agent isn't finished with turn, continue
%define AGENT_FINISHED 1 ; move has been decided
%define AGENT_EXIT 2 ; agent wants to exit

; piece bitfield : 
;  0b0000000
;    ││││││└─ color
;    │││└┴┴─ piece type
;    ││└─ special bit (en passant / castling right)
;    │└─ under immediate white attack
;    └─ under immediate black attack

%define PIECE_BITS		0b11111111
%define PIECE_COLOR_BIT		0b00000001
%define PIECE_WHITE		0b00000000
%define PIECE_BLACK		0b00000001
%define PIECE_TYPE_OFFSET	1
%define PIECE_TYPE_BITS		0b00001110
%define PIECE_PAWN		0b00000010
%define PIECE_KNIGHT		0b00000100
%define PIECE_BISHOP		0b00000110
%define PIECE_ROOK		0b00001000
%define PIECE_QUEEN		0b00001010
%define PIECE_KING		0b00001100
%define PIECE_SPECIAL_BIT	0b00010000
%define PIECE_ATTACK_BITS	0b11000000
%define PIECE_ATTACK_WHITE	0b01000000
%define PIECE_ATTACK_BLACK	0b10000000

; move bitfield : 
;  0b00000000
;    │││││└┴┴─ destination file
;    ││└┴┴ destination rank
;    └┴─ type (moves [00], captures [01], castling [10])
;  0b11000000
;    ││  └┴┴── piece type
;    └┴─ type (promotion [11])

%define MOVE_FILE_BITS		0b00000111
%define MOVE_RANK_BITS		0b00111000
%define MOVE_FILE_OFFSET	0
%define MOVE_RANK_OFFSET	3
%define MOVE_PIECE_TYPE_BITS	0b00001110
%define MOVE_TYPE_BITS		0b11000000
%define MOVE_TYPE_MOVE		0b00000000
%define MOVE_TYPE_CAPTURE	0b01000000
%define MOVE_TYPE_CASTLE	0b10000000
%define MOVE_TYPE_PROMOTION	0b11000000

%macro define_pieces 2
%define P_%1 %eval(0 | %2)
%define Pp%1 %eval(PIECE_BLACK | PIECE_PAWN | %2)
%define Pn%1 %eval(PIECE_BLACK | PIECE_KNIGHT | %2)
%define Pb%1 %eval(PIECE_BLACK | PIECE_BISHOP | %2)
%define Pr%1 %eval(PIECE_BLACK | PIECE_ROOK | PIECE_SPECIAL_BIT | %2)
%define Pq%1 %eval(PIECE_BLACK | PIECE_QUEEN | %2)
%define Pk%1 %eval(PIECE_BLACK | PIECE_KING | %2)
%define PP%1 %eval(PIECE_WHITE | PIECE_PAWN | %2)
%define PN%1 %eval(PIECE_WHITE | PIECE_KNIGHT | %2)
%define PB%1 %eval(PIECE_WHITE | PIECE_BISHOP | %2)
%define PR%1 %eval(PIECE_WHITE | PIECE_ROOK | PIECE_SPECIAL_BIT | %2)
%define PQ%1 %eval(PIECE_WHITE | PIECE_QUEEN | %2)
%define PK%1 %eval(PIECE_WHITE | PIECE_KING | %2)
%endmacro

define_pieces   , 0
define_pieces __, 0
define_pieces w_, PIECE_ATTACK_WHITE
define_pieces _b, PIECE_ATTACK_BLACK
define_pieces wb, PIECE_ATTACK_WHITE | PIECE_ATTACK_BLACK

; keystrokes

; define macros for keystrokes:
;  - KEY_[name]: the numeric id of the keystroke
;  - KEY_[id]_LEN: the length in bytes of the keystroke
;  - KEY_[id]_BYTES_[n]: the nth (1 indexed) byte of the keystroke's byte sequence
; The only important one here being the KEY_[name] macro, the rest are implementation
; details used in 'keystrokes.asm'.
;
; No key has id 0
%assign key_count 0
%macro define_key 2-*
	%assign key_count key_count+1

	%define KEY_%1 %[key_count]
	%define KEY_%[key_count]_LEN %0 - 1

	%assign i 1
	%rep %0 - 1
		%define KEY_%[key_count]_BYTES_%[i] %[%sel(i, %{2:-1})]
		%assign i i+1
	%endrep
%endmacro

; order matters ! keys which are prefixes of other keys should come after.
;          name,        [..bytes, ]
define_key UP_ARROW,	0x1b, '[', 'A'
define_key DOWN_ARROW,	0x1b, '[', 'B'
define_key RIGHT_ARROW,	0x1b, '[', 'C'
define_key LEFT_ARROW,	0x1b, '[', 'D'
define_key ESC,		0x1b ; needs to be put after any other key starting with 0x1b
define_key A,		'a'
define_key SPACE,	' '
define_key ENTER,	0x10

; Move one position into another
; cobblers: r8
; %1 <- destination address
; %2 <- source address
%macro mov_position 2
	%assign i 0
	%rep 8
	mov r8, qword [%2 + i * 8]
	mov qword [%1 + i * 8], r8
	%assign i i+1
	%endrep
%endmacro

; Compare two positions (sets ZF=1 if equal)
; cobblers: r8, r9
; %1 <- register storing one position's address
; %2 <- register storing the other position's address
; ZF -> 1 if they are equal
%macro cmp_position 2
	xor r9, r9

	%assign i 0
	%rep 8
	mov r8, [%1 + i * 8]
	xor r8, [%2 + i * 8]
	or r9, r8
	%assign i i+1
	%endrep

	test r8, r8
%endmacro
