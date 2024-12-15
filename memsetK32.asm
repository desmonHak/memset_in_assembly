; Licencia Apache, Versión 2.0 con Modificación
; 
; Copyright 2023 Desmon (David)
; Se concede permiso, de forma gratuita, a cualquier persona que obtenga una copia de este software y archivos
; de documentación asociados (el "Software"), para tratar el Software sin restricciones, incluidos, entre otros,
; los derechos de uso, copia, modificación, fusión, publicación, distribución, sublicencia y/o venta de copias del
; Software, y para permitir a las personas a quienes se les proporcione el Software hacer lo mismo, sujeto a las
; siguientes condiciones:
; El anterior aviso de copyright y este aviso de permiso se incluirán en todas las copias o partes sustanciales del Software.
; EL SOFTWARE SE PROPORCIONA "TAL CUAL", SIN GARANTÍA DE NINGÚN TIPO, EXPRESA O IMPLÍCITA, INCLUYENDO PERO NO
; LIMITADO A LAS GARANTÍAS DE COMERCIABILIDAD, IDONEIDAD PARA UN PROPÓSITO PARTICULAR Y NO INFRACCIÓN. EN
; NINGÚN CASO LOS TITULARES DEL COPYRIGHT O LOS TITULARES DE LOS DERECHOS DE AUTOR SERÁN RESPONSABLES DE
; NINGÚN RECLAMO, DAÑO U OTRA RESPONSABILIDAD, YA SEA EN UNA ACCIÓN DE CONTRATO, AGRAVIO O DE OTRA MANERA, QUE SURJA
; DE, FUERA DE O EN CONEXIÓN CON EL SOFTWARE O EL USO U OTRO TIPO DE ACCIONES EN EL SOFTWARE.
; Además, cualquier modificación realizada por terceros se considerará propiedad del titular original de los derechos
; de autor. Los titulares de derechos de autor originales no se responsabilizan de las modificaciones realizadas por terceros.
; Queda explícitamente establecido que no es obligatorio especificar ni notificar los cambios realizados entre versiones,
; ni revelar porciones específicas de código modificado.

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