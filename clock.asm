	; Time related utilities: sleep, getting the time
%include "constants.inc"

	section .bss
timespec:	resb 16

	section .text

	global get_time
	global merge_timestamp
	global split_timestamp
	global sleep
	global sleep_until

; Get the current time (monotonic clock)
; cobblers: rdi, rsi, rcx
; rax -> seconds
; rdx -> nano seconds
get_time:
	mov rax, SYS_CLOCK_GETTIME
	mov rdi, CLOCK_MONOTONIC
	lea rsi, [rel timespec]
	syscall
	
	mov rax, [rsi]
 	mov rdx, [rsi + 8]
	
	ret

; Converts s:ns timestamp into a ns timestamp
; cobblers: rdx
; rax <- seconds
; rdx <- nano seconds
; rax -> timestamp (nano seconds)
merge_timestamp:
	push rdx
	mov rdx, 1000000000
	mul rdx
	pop rdx
	add rax, rdx
	ret

; Converts ns timestamp into a s:ns timestamp
; cobblers: rdi
; rax <- timestamp (nano seconds)
; rax -> seconds
; rdx -> nano seconds
split_timestamp:
	xor rdx, rdx
	mov rdi, 1000000000
	div rdi
	ret

; Sleep an ammount of time
; cobblers: rax, rdx, rdi, rsi, rcx, r10
; rax -> seconds to sleep for
; rdx -> nanoseconds to sleep for
sleep:
	lea rdi, [rel timespec]
	mov [rdi], rax
	mov [rdi + 8], rdi

	mov rax, SYS_CLOCK_NANOSLEEP
	mov rdi, CLOCK_MONOTONIC
	xor rsi, rsi
	lea rdx, [rel timespec]
	xor r10, r10
	syscall

	ret

; sleep until timestamp
; cobblers: rax, rdx, rdi, rsi, rcx, r10
; rax -> seconds of timestamp
; rdx -> nanoseconds of timestamp
sleep_until:
	lea rdi, [rel timespec]
	mov [rdi], rax
	mov [rdi + 8], rdx

	mov rax, SYS_CLOCK_NANOSLEEP
	mov rdi, CLOCK_MONOTONIC
	mov rsi, TIMER_ABSTIME
	lea rdx, [rel timespec]
	xor r10, r10
	syscall

	ret
