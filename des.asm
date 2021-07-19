bits 64

section .text

global encrypt

;--------------------
; macro
;--------------------

%macro permute 4

mov rsi, %2
lea rdi, [rel %1]
mov rdx, %3
mov rcx, %4
call permute_bits

%endmacro

%macro sbox 2

shl rax, 4
lea rdi, [rel SBOX%1]
mov rdx, %2
shr rdx, (48-6*%1)
and rdx, 0b111111
movzx r9, BYTE [rdi + rdx]
or rax, r9

%endmacro

;--------------------
; bit permute
;--------------------
; Args
; - rdi: table
; - rsi: input
; - rdx: table size
; - rcx: size
;
; Return
; - rax: output
;--------------------
permute_bits:
  push r12

  xor rax, rax
  mov r9, rax
  mov r10, rdx
  mov r12, rcx

  .permute_loop:
    shl rax, 1
    ;movsxd rcx, DWORD [rbp - 0x4]

    mov dl, BYTE [rdi + r9]
    ;mov cl, BYTE [rbp - 0xc]
    mov cl, r12b
    sub cl, dl

    ; mask
    mov r11, 1
    shl r11, cl

    and r11, rsi
    jz .permute_loop_update

    inc rax

    .permute_loop_update:
      inc r9
      cmp r9, r10
      jne .permute_loop

  pop r12
  ret


;--------------------
; round function
;--------------------
; Args
; - rdi: R
; - rsi: subkey
;--------------------
round_f:
  push r12

  mov r12, rsi

  ; expand
  permute E, rdi, 48, 32

  ; key ^ R
  xor rax, r12

  ; sbox
  mov r10, rax
  xor rax, rax
  sbox 1, r10
  sbox 2, r10
  sbox 3, r10
  sbox 4, r10
  sbox 5, r10
  sbox 6, r10
  sbox 7, r10
  sbox 8, r10

  ; output
  permute P, rax, 32, 32

  pop r12
  ret

;--------------------
; generate subkey
;--------------------
; Args
; - rdi: subkey array
; - rsi: key
;--------------------
subkey_gen:
  push rbp
  mov rbp, rsp
  push r12
  push r13
  push r14
  push r15

  mov r12, rdi
  mov r13, rsi
  xor r14, r14

  ; 64bit key => 56bit
  mov r11, QWORD [r13]
  bswap r11
  permute PC1, r11, 56, 64

  subkey_gen_loop:
    ; split
    mov rdx, rax
    shr rdx, 28
    and eax, 0xfffffff

    ; prepare shift
    lea rdi, [rel SHIFT_TABLE]
    movsx rcx, BYTE [rdi + r14 * 1]
    lea rdi, [rel SHIFT_MASK]
    movsxd r9, [rdi + rcx * 4 - 4]
    mov r10, r9
    mov r8b, cl

    ; shift left part
    ; (left & mask) | (left << shift_width)
    and r9, rdx
    shl rdx, cl
    mov cl, 28
    sub cl, r8b
    shr r9, cl
    or rdx, r9
    and edx, 0xfffffff

    ; shift right part
    ; (right & mask) | (right << shift_width)
    and r10, rax
    mov cl, r8b
    shl rax, cl
    mov cl, 28
    sub cl, r8b
    shr r10, cl
    or rax, r10
    and eax, 0xfffffff

    ; merge
    shl rdx, 28
    or rax, rdx
    mov r15, rax

    ; 56bit => 48bit
    permute PC2, rax, 48, 56
    mov QWORD [r12 + r14 * 8], rax

    mov rax, r15
    inc r14
    cmp r14, 0x10
    jl subkey_gen_loop

  pop r15
  pop r14
  pop r13
  pop r12
  leave
  ret

;--------------------
; Encrypt
;--------------------
; Args
; - rdi: plain text
; - rsi: output
; - rdx: key
;--------------------
encrypt:
  push rbp
  mov rbp, rsp
  sub rsp, 0x100

  push r12
  xor r12, r12

  ; save args
  mov QWORD [rbp-0x8], rdi
  mov QWORD [rbp-0x10], rsi
  mov QWORD [rbp-0x18], rdx

  ; generate subkey
  lea rdi, [rbp-0x100]
  mov rsi, QWORD [rbp-0x18]
  call subkey_gen

  ; initial permutation
  mov r11, [rbp-0x8]
  mov r11, [r11]
  bswap r11
  permute IP, r11, 64, 64

  ; split
  movsxd rdx, eax
  shr rax, 32
  mov DWORD [rbp-0x1c], eax ; left
  mov DWORD [rbp-0x20], edx ; right

  .encrypt_loop:
    movsxd rdi, DWORD [rbp-0x20]
    mov rsi, [rbp-0x100 + r12*8]
    call round_f

    ; left ^ f(right)
    mov edx, DWORD [rbp-0x1c]
    xor edx, eax
    mov eax, DWORD [rbp-0x20]

    cmp r12, 0xf
    je .encrypt_loop_last_block

    ; left <- right
    ; right <- left
    mov DWORD [rbp-0x1c], eax
    mov DWORD [rbp-0x20], edx
    jmp .encrypt_loop_update

    .encrypt_loop_last_block:
      mov DWORD [rbp-0x1c], edx

    .encrypt_loop_update:
      inc r12
      cmp r12, 0x10
      jne .encrypt_loop

  ; merge
  mov eax, DWORD [rbp-0x1c]
  mov edx, DWORD [rbp-0x20]
  shl rax, 32
  or rax, rdx

  ; inverse initial permutation
  permute INV_IP, rax, 64, 64

  ; little endian -> big endian
  bswap rax

  ; write encrypted data
  mov rdi, QWORD [rbp-0x10]
  mov QWORD [rdi], rax

  leave
  ret

section .data

IP:
db 0x3a, 0x32, 0x2a, 0x22, 0x1a, 0x12, 0x0a, 0x02
db 0x3c, 0x34, 0x2c, 0x24, 0x1c, 0x14, 0x0c, 0x04
db 0x3e, 0x36, 0x2e, 0x26, 0x1e, 0x16, 0x0e, 0x06
db 0x40, 0x38, 0x30, 0x28, 0x20, 0x18, 0x10, 0x08
db 0x39, 0x31, 0x29, 0x21, 0x19, 0x11, 0x09, 0x01
db 0x3b, 0x33, 0x2b, 0x23, 0x1b, 0x13, 0x0b, 0x03
db 0x3d, 0x35, 0x2d, 0x25, 0x1d, 0x15, 0x0d, 0x05
db 0x3f, 0x37, 0x2f, 0x27, 0x1f, 0x17, 0x0f, 0x07

INV_IP:
db 0x28, 0x08, 0x30, 0x10, 0x38, 0x18, 0x40, 0x20
db 0x27, 0x07, 0x2f, 0x0f, 0x37, 0x17, 0x3f, 0x1f
db 0x26, 0x06, 0x2e, 0x0e, 0x36, 0x16, 0x3e, 0x1e
db 0x25, 0x05, 0x2d, 0x0d, 0x35, 0x15, 0x3d, 0x1d
db 0x24, 0x04, 0x2c, 0x0c, 0x34, 0x14, 0x3c, 0x1c
db 0x23, 0x03, 0x2b, 0x0b, 0x33, 0x13, 0x3b, 0x1b
db 0x22, 0x02, 0x2a, 0x0a, 0x32, 0x12, 0x3a, 0x1a
db 0x21, 0x01, 0x29, 0x09, 0x31, 0x11, 0x39, 0x19

PC1:
db 0x39, 0x31, 0x29, 0x21, 0x19, 0x11, 0x09, 0x01
db 0x3a, 0x32, 0x2a, 0x22, 0x1a, 0x12, 0x0a, 0x02
db 0x3b, 0x33, 0x2b, 0x23, 0x1b, 0x13, 0x0b, 0x03
db 0x3c, 0x34, 0x2c, 0x24, 0x3f, 0x37, 0x2f, 0x27
db 0x1f, 0x17, 0x0f, 0x07, 0x3e, 0x36, 0x2e, 0x26
db 0x1e, 0x16, 0x0e, 0x06, 0x3d, 0x35, 0x2d, 0x25
db 0x1d, 0x15, 0x0d, 0x05, 0x1c, 0x14, 0x0c, 0x04

PC2:
db 0x0e, 0x11, 0x0b, 0x18, 0x01, 0x05, 0x03, 0x1c
db 0x0f, 0x06, 0x15, 0x0a, 0x17, 0x13, 0x0c, 0x04
db 0x1a, 0x08, 0x10, 0x07, 0x1b, 0x14, 0x0d, 0x02
db 0x29, 0x34, 0x1f, 0x25, 0x2f, 0x37, 0x1e, 0x28
db 0x33, 0x2d, 0x21, 0x30, 0x2c, 0x31, 0x27, 0x38
db 0x22, 0x35, 0x2e, 0x2a, 0x32, 0x24, 0x1d, 0x20

E:
db 0x20, 0x01, 0x02, 0x03, 0x04, 0x05, 0x04, 0x05
db 0x06, 0x07, 0x08, 0x09, 0x08, 0x09, 0x0a, 0x0b
db 0x0c, 0x0d, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11
db 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x14, 0x15
db 0x16, 0x17, 0x18, 0x19, 0x18, 0x19, 0x1a, 0x1b
db 0x1c, 0x1d, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x01

P:
db 0x10, 0x07, 0x14, 0x15, 0x1d, 0x0c, 0x1c, 0x11
db 0x01, 0x0f, 0x17, 0x1a, 0x05, 0x12, 0x1f, 0x0a
db 0x02, 0x08, 0x18, 0x0e, 0x20, 0x1b, 0x03, 0x09
db 0x13, 0x0d, 0x1e, 0x06, 0x16, 0x0b, 0x04, 0x19

SHIFT_TABLE:
db 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1

SHIFT_MASK:
dd 0x8000000, 0xc000000

SBOX1:
db 0x0e, 0x00, 0x04, 0x0f, 0x0d, 0x07, 0x01, 0x04, 0x02, 0x0e, 0x0f, 0x02, 0x0b, 0x0d, 0x08, 0x01
db 0x03, 0x0a, 0x0a, 0x06, 0x06, 0x0c, 0x0c, 0x0b, 0x05, 0x09, 0x09, 0x05, 0x00, 0x03, 0x07, 0x08
db 0x04, 0x0f, 0x01, 0x0c, 0x0e, 0x08, 0x08, 0x02, 0x0d, 0x04, 0x06, 0x09, 0x02, 0x01, 0x0b, 0x07
db 0x0f, 0x05, 0x0c, 0x0b, 0x09, 0x03, 0x07, 0x0e, 0x03, 0x0a, 0x0a, 0x00, 0x05, 0x06, 0x00, 0x0d

SBOX2:
db 0x0f, 0x03, 0x01, 0x0d, 0x08, 0x04, 0x0e, 0x07, 0x06, 0x0f, 0x0b, 0x02, 0x03, 0x08, 0x04, 0x0e
db 0x09, 0x0c, 0x07, 0x00, 0x02, 0x01, 0x0d, 0x0a, 0x0c, 0x06, 0x00, 0x09, 0x05, 0x0b, 0x0a, 0x05
db 0x00, 0x0d, 0x0e, 0x08, 0x07, 0x0a, 0x0b, 0x01, 0x0a, 0x03, 0x04, 0x0f, 0x0d, 0x04, 0x01, 0x02
db 0x05, 0x0b, 0x08, 0x06, 0x0c, 0x07, 0x06, 0x0c, 0x09, 0x00, 0x03, 0x05, 0x02, 0x0e, 0x0f, 0x09

SBOX3:
db 0x0a, 0x0d, 0x00, 0x07, 0x09, 0x00, 0x0e, 0x09, 0x06, 0x03, 0x03, 0x04, 0x0f, 0x06, 0x05, 0x0a
db 0x01, 0x02, 0x0d, 0x08, 0x0c, 0x05, 0x07, 0x0e, 0x0b, 0x0c, 0x04, 0x0b, 0x02, 0x0f, 0x08, 0x01
db 0x0d, 0x01, 0x06, 0x0a, 0x04, 0x0d, 0x09, 0x00, 0x08, 0x06, 0x0f, 0x09, 0x03, 0x08, 0x00, 0x07
db 0x0b, 0x04, 0x01, 0x0f, 0x02, 0x0e, 0x0c, 0x03, 0x05, 0x0b, 0x0a, 0x05, 0x0e, 0x02, 0x07, 0x0c

SBOX4:
db 0x07, 0x0d, 0x0d, 0x08, 0x0e, 0x0b, 0x03, 0x05, 0x00, 0x06, 0x06, 0x0f, 0x09, 0x00, 0x0a, 0x03
db 0x01, 0x04, 0x02, 0x07, 0x08, 0x02, 0x05, 0x0c, 0x0b, 0x01, 0x0c, 0x0a, 0x04, 0x0e, 0x0f, 0x09
db 0x0a, 0x03, 0x06, 0x0f, 0x09, 0x00, 0x00, 0x06, 0x0c, 0x0a, 0x0b, 0x01, 0x07, 0x0d, 0x0d, 0x08
db 0x0f, 0x09, 0x01, 0x04, 0x03, 0x05, 0x0e, 0x0b, 0x05, 0x0c, 0x02, 0x07, 0x08, 0x02, 0x04, 0x0e

SBOX5:
db 0x02, 0x0e, 0x0c, 0x0b, 0x04, 0x02, 0x01, 0x0c, 0x07, 0x04, 0x0a, 0x07, 0x0b, 0x0d, 0x06, 0x01
db 0x08, 0x05, 0x05, 0x00, 0x03, 0x0f, 0x0f, 0x0a, 0x0d, 0x03, 0x00, 0x09, 0x0e, 0x08, 0x09, 0x06
db 0x04, 0x0b, 0x02, 0x08, 0x01, 0x0c, 0x0b, 0x07, 0x0a, 0x01, 0x0d, 0x0e, 0x07, 0x02, 0x08, 0x0d
db 0x0f, 0x06, 0x09, 0x0f, 0x0c, 0x00, 0x05, 0x09, 0x06, 0x0a, 0x03, 0x04, 0x00, 0x05, 0x0e, 0x03

SBOX6:
db 0x0c, 0x0a, 0x01, 0x0f, 0x0a, 0x04, 0x0f, 0x02, 0x09, 0x07, 0x02, 0x0c, 0x06, 0x09, 0x08, 0x05
db 0x00, 0x06, 0x0d, 0x01, 0x03, 0x0d, 0x04, 0x0e, 0x0e, 0x00, 0x07, 0x0b, 0x05, 0x03, 0x0b, 0x08
db 0x09, 0x04, 0x0e, 0x03, 0x0f, 0x02, 0x05, 0x0c, 0x02, 0x09, 0x08, 0x05, 0x0c, 0x0f, 0x03, 0x0a
db 0x07, 0x0b, 0x00, 0x0e, 0x04, 0x01, 0x0a, 0x07, 0x01, 0x06, 0x0d, 0x00, 0x0b, 0x08, 0x06, 0x0d

SBOX7:
db 0x04, 0x0d, 0x0b, 0x00, 0x02, 0x0b, 0x0e, 0x07, 0x0f, 0x04, 0x00, 0x09, 0x08, 0x01, 0x0d, 0x0a
db 0x03, 0x0e, 0x0c, 0x03, 0x09, 0x05, 0x07, 0x0c, 0x05, 0x02, 0x0a, 0x0f, 0x06, 0x08, 0x01, 0x06
db 0x01, 0x06, 0x04, 0x0b, 0x0b, 0x0d, 0x0d, 0x08, 0x0c, 0x01, 0x03, 0x04, 0x07, 0x0a, 0x0e, 0x07
db 0x0a, 0x09, 0x0f, 0x05, 0x06, 0x00, 0x08, 0x0f, 0x00, 0x0e, 0x05, 0x02, 0x09, 0x03, 0x02, 0x0c

SBOX8:
db 0x0d, 0x01, 0x02, 0x0f, 0x08, 0x0d, 0x04, 0x08, 0x06, 0x0a, 0x0f, 0x03, 0x0b, 0x07, 0x01, 0x04
db 0x0a, 0x0c, 0x09, 0x05, 0x03, 0x06, 0x0e, 0x0b, 0x05, 0x00, 0x00, 0x0e, 0x0c, 0x09, 0x07, 0x02
db 0x07, 0x02, 0x0b, 0x01, 0x04, 0x0e, 0x01, 0x07, 0x09, 0x04, 0x0c, 0x0a, 0x0e, 0x08, 0x02, 0x0d
db 0x00, 0x0f, 0x06, 0x0c, 0x0a, 0x09, 0x0d, 0x00, 0x0f, 0x03, 0x03, 0x05, 0x05, 0x06, 0x08, 0x0b