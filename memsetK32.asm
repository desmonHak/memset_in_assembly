; __cdecl void *memsetK32(
;     void *dest,
;     size_t c,
;     size_t count
; );
global _memsetK32

section .text
_memsetK32:
    push edi
    push esi
    push ebx

    mov edi, [esp+16]  ; dest
    movzx eax, byte [esp+20]  ; c (extendido a 32 bits)
    mov ecx, [esp+24]  ; count

    mov edx, edi  ; Guardar el puntero de destino original para retornarlo

    cmp ecx, 4
    jb .byte_set

    ; Rellenar EAX con el byte c repetido 4 veces
    mov al, [esp+20]
    mov ah, al
    shl eax, 16
    mov al, [esp+20]
    mov ah, al

    ; Alinear EDI a 4 bytes si es necesario
    mov ebx, edi
    and ebx, 3
    jz .aligned_set
    neg ebx
    add ebx, 4
    sub ecx, ebx
    rep stosb

    .aligned_set:
        mov ebx, ecx
        shr ecx, 2
        and ebx, 3
        rep stosd
        mov ecx, ebx

    .byte_set:
        rep stosb

        mov eax, edx  ; Retornar el puntero de destino original

        pop ebx
        pop esi
        pop edi
        ret