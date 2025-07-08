; Terminal utilities: raw mode, moving cursor, clearing screen, getting size, ...
%include "constants.inc"

	section .bss


termios:	resb 60
winsize:	resb 8
width:		resb 8
height:		resb 8

	section .text

c_show:		db 0x1B, "[?25h"
c_hide:		db 0x1B, "[?25l"
c_save:		db 0x1B, "7"
c_restore:	db 0x1B, "8"
alt_enter:	db 0x1B, "[?47h"
alt_leave:	db 0x1B, "[?47l"
s_clear:	db 0x1B, "[2J"
csi:		db 0x1B, "["
smcln:		db ";"
H:		db "H"

	global width
	global height
	global set_raw
	global unset_raw
	global get_size
	global enter_alt
	global leave_alt
	global clear_screen
	global set_cursor
	global hide_cursor
	global show_cursor

	extern qprint_unsigned


; Print string
; cobblers: rax, rdi, rsi, rdx, rcx
; %1 -> symbol pointing to the string
; %2 -> length
%macro print 2
	mov rax, SYS_WRITE
	mov rdi, STDOUT
	lea rsi, [rel %1]
	mov rdx, %2
	syscall
%endmacro

; move cursor
; cobblers: rax, rcx, rdx, rdi, rsi, r8, r9
; rax -> column to move to
; rdx -> line to move to
set_cursor:
; the escape sequence we're using is 1 indexed
	inc rax
	inc rdx
	push rax
	push rdx

	print csi, 2

	pop rax
	call qprint_unsigned

	print smcln, 1

	pop rax
	call qprint_unsigned

	print H, 1

	ret

; Get term size, &width is in rax, &height in rdi
; cobblers: rax, rcx, rdx, rdi, rsi
; rax <- pointer to width qword
; rdi <- pointer to height qword
get_size:
	mov rax, SYS_IOCTL
	mov rdi, STDOUT
	mov rsi, TIOCGWINSZ
	lea rdx, [rel winsize]
	syscall

	lea rax, [rel height]
	lea rdi, [rel width]
	mov si, word [rdx]
	mov word [rax], si
	mov si, word [rdx + 2]
	mov word [rdi], si
	ret
; Clear screen
; cobblers: rax, rcx, rdx, rdi, rsi
clear_screen:
	print s_clear, 4
	ret
; Save cursor
; cobblers: rax, rcx, rdx, rdi, rsi
save_cursor:
	print c_save, 2
	ret
; Restore cursor
; cobblers: rax, rcx, rdx, rdi, rsi
restore_cursor:
	print c_restore, 2
	ret
; Enter alt
; cobblers: rax, rcx, rdx, rdi, rsi
enter_alt:
	call save_cursor
	print alt_enter, 6
	call clear_screen
	ret
; Leave alt
; cobblers: rax, rcx, rdx, rdi, rsi
leave_alt:
	call clear_screen
	print alt_leave, 6
	call restore_cursor
	ret
; Hide cursor
; cobblers: rax, rcx, rdx, rdi, rsi
hide_cursor:
	print c_hide, 6
	ret
; Show cursor
; cobblers: rax, rcx, rdx, rdi, rsi
show_cursor:
	print c_show, 6
	ret
; Get termios
; cobblers: rax, rcx, rdx, rdi, rsi
; rdx <- pointer to termios
get_termios:
	mov rax, SYS_IOCTL
	mov rdi, STDIN
	mov rsi, TCGETS
	lea rdx, [rel termios]
	syscall
	ret
; Get termios (state is what was pointed by rdx after get_termios call)
; cobblers: rax, rcx, rdx, rdi, rsi
set_termios:
	mov rax, SYS_IOCTL
	mov rdi, STDIN
	mov rsi, TCSETS
	lea rdx, [rel termios]
	syscall
	ret
; Set raw mode
; cobblers: rax, rcx, rdx, rdi, rsi
set_raw:
	call get_termios
	and dword [rdx + 12], 0xFFFFFFF5
	call set_termios
	ret
; Unset raw mode
; cobblers: rax, rcx, rdx, rdi, rsi
unset_raw:
	call get_termios
	or dword [rdx + 12], 0x00000000A
	call set_termios
	ret
