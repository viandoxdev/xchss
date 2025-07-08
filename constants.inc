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
