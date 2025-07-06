; vi: ft=asm
%include "syscalls.inc"

%define STDIN 0
%define STDOUT 1

%define TIOCGWINSZ 0x5413
%define TCGETS 0x5401
%define TCSETS 0x5402
