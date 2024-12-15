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


; __fastcall void *memsetK64(
;     void *dest,   -> rcx
;     size_t c,     -> edx
;     size_t count  -> r8
; );

; https://stackoverflow.com/questions/33480999/how-can-the-rep-stosb-instruction-execute-faster-than-the-equivalent-loop
; En las CPU modernas, la implementación microcodificada de rep stosb y 
; rep movsb en realidad usa almacenamientos que son más anchos que 1B, por 
; lo que puede ir mucho más rápido que un byte por reloj.
; (Tenga en cuenta que esto solo se aplica a stos y movs, no a repe cmpsb o 
; repne scasb. Desafortunadamente, siguen siendo lentos, como máximo 2 ciclos 
; por byte en comparación con Skylake, lo cual es patético en comparación con 
; AVX2 vpcmpeqb para implementar memcmp o memchr. Consulte https://agner.org/optimize/ 
; para ver las tablas de instrucciones y otros enlaces de rendimiento en la 
; wiki de etiquetas x86.
; Consulte ¿Por qué este código es 6,5 veces más lento con las optimizaciones 
; habilitadas? para ver un ejemplo de gcc que incorpora de manera imprudente 
; repnz scasb o un bithack escalar menos malo para un strlen que resulta ser 
; grande, y una alternativa SIMD simple).
; rep stos/movs tiene una sobrecarga de arranque significativa, pero aumenta bien para 
; memset/memcpy grandes. (Consulte los manuales de optimización de Intel/AMD para obtener 
; información sobre cuándo usar rep stos en lugar de un bucle vectorizado para buffers pequeños). 
; Sin embargo, sin la función ERMSB, rep stosb está optimizado para memsets medianos a pequeños 
; y es óptimo usar rep stosd o rep stosq (si no va a usar un bucle SIMD).
; 
; Al ejecutar un solo paso con un depurador, rep stos solo realiza una iteración 
; (una disminución de ecx/rcx), por lo que la implementación del microcódigo nunca se 
; pone en marcha. No permita que esto lo engañe y le haga pensar que eso es todo lo que 
; puede hacer.
; 
; Consulte ¿Qué configuración realiza REP? para obtener algunos detalles sobre cómo las 
; microarquitecturas de la familia Intel P6/SnB implementan rep movs.
; 
; Consulte REP MOVSB ​​mejorado para memcpy para conocer las consideraciones sobre el ancho 
; de banda de la memoria con rep movsb en comparación con un bucle SSE o AVX en las CPU 
; Intel con la función ERMSB. (Tenga en cuenta especialmente que las CPU Xeon de varios núcleos 
; no pueden saturar el ancho de banda de la DRAM con un solo subproceso, debido a los 
; límites en la cantidad de errores de caché que se producen a la vez, y también a los 
; protocolos de almacenamiento RFO en comparación con los que no son RFO).
;
; Si su CPU tiene el bit CPUID ERMSB, entonces los comandos rep movsb y rep stosb se ejecutan 
; de manera diferente que en procesadores más antiguos.
; Consulte el Manual de referencia de optimización de Intel, sección 3.7.6 Operación REP MOVSB 
; ​​y REP STOSB mejorada (ERMSB).
; Tanto el manual como mis pruebas muestran que los beneficios de rep stosb en comparación 
; con los movimientos de registro genéricos de 32 bits en una CPU de 32 bits de la 
; microarquitectura Skylake aparecen solo en bloques de memoria grandes, mayores de 
; 128 bytes. En bloques más pequeños, como de 5 bytes, el código que ha mostrado 
; (mov byte [edi],al; inc edi; dec ecx; jnz Clear) sería mucho más rápido, ya que los costos 
; de inicio de rep stosb son muy altos: alrededor de 35 ciclos. Sin embargo, esta diferencia de 
; velocidad ha disminuido en la microarquitectura Ice Lake lanzada en septiembre de 2019, 
; que introdujo la función Fast Short REP MOV (FSRM). Esta característica se puede probar con 
; un bit CPUID. Se pensó que las cadenas de 128 bytes y más cortas fueran rápidas, pero, de 
; hecho, las cadenas de menos de 64 bytes son aún más lentas con rep movsb que con, por ejemplo, 
; una copia de registro simple de 64 bits. Además de eso, FSRM solo se implementa en 64 bits, 
; no en 32 bits. Al menos en mi CPU i7-1065G7, rep movsb solo es rápido para cadenas pequeñas 
; de menos de 64 bits, pero, en 32 bits, las cadenas deben tener al menos 4 KB para que rep 
; movsb comience a superar a otros métodos.
; 
; Para obtener los beneficios de rep stosb en los procesadores con el bit CPUID ERMSB, 
; se deben cumplir las siguientes condiciones:
; 
; - el búfer de destino debe estar alineado con un límite de 16 bytes;
; - si la longitud es un múltiplo de 64, puede producir un rendimiento aún mayor;
; - El bit de dirección debe estar configurado en "adelante" (configurado por la instrucción cld).
; - Según el Manual de optimización de Intel, ERMSB comienza a superar el almacenamiento 
;     de memoria a través de un registro regular en Skylake cuando la longitud del bloque 
;     de memoria es de al menos 128 bytes. 
; 
; Como escribí, hay un alto ERMSB de inicio interno: 
; alrededor de 35 ciclos. ERMSB comienza a superar claramente a otros métodos, incluido el 
; de copia y relleno AVX, cuando la longitud es de más de 2048 bytes. Sin embargo, esto se 
; aplica principalmente a la microarquitectura Skylake y no necesariamente es el caso de 
; las otras microarquitecturas de CPU.
; 
; En algunos procesadores, pero no en otros, cuando el búfer de destino está alineado a 16 
; bytes, REP STOSB que utiliza ERMSB puede funcionar mejor que los enfoques SIMD, es decir, 
; cuando se utilizan registros MMX o SSE. Cuando el búfer de destino está desalineado, el
; rendimiento de memset() utilizando ERMSB puede degradarse alrededor de un 20% en relación 
; con el caso alineado, para procesadores basados ​​en el nombre de código de microarquitectura 
; de Intel Ivy Bridge. En contraste, la implementación SIMD de REP STOSB experimentará una 
; degradación más insignificante cuando el destino está desalineado, según el manual de 
; optimización de Intel.
; 
; Tenga en cuenta que la desventaja de utilizar el registro XMM0 es que tiene 128 bits 
; (16 bytes), mientras que podría haber utilizado el registro YMM0 de 256 bits (32 bytes). 
; De todos modos, stosb utiliza el protocolo no RFO. Intel x86 ha tenido "cadenas rápidas" 
; desde el Pentium Pro (P6) en 1996. Las cadenas rápidas P6 tomaron REP MOVSB ​​y mayores, 
; y las implementaron con cargas y almacenamientos de microcódigo de 64 bits y un protocolo 
; de caché no RFO. No violaron el orden de la memoria, a diferencia de ERMSB en Ivy Bridge. 
; Consulte https://stackoverflow.com/a/33905887/6910868 para obtener más detalles y la fuente.
; 
; De todos modos, incluso si compara solo dos de los métodos que he proporcionado, y aunque 
; el segundo método está lejos de ser ideal, como puede ver, en bloques de 64 bits, 
; rep stosb es más lento, pero a partir de bloques de 128 bytes, rep stosb comienza a 
; superar a otros métodos, y la diferencia es muy significativa a partir de bloques de 
; 512 bytes y más, siempre que esté borrando el mismo bloque de memoria una y otra vez 
; dentro del caché.
; 
; Por lo tanto, para REP STOSB, la velocidad máxima fue de 103957 (ciento tres mil 
; novecientos cincuenta y siete) megabytes por segundo, mientras que con 
; MOVDQA [RCX], XMM0 fue solo de 26569 (veintiséis mil quinientos sesenta y nueve) 
; veintiséis mil quinientos sesenta y nueve.
; Como puede ver, el rendimiento más alto se obtuvo en bloques de 32 000, lo que 
; equivale a 32 000 de caché L1 de la CPU en la que he realizado los benchmarks.
; 
; Ice Lake
; REP STOSB vs AVX-512 store
; También he realizado pruebas en una CPU Intel i7 1065G7, lanzada en agosto de 2019 
; (microarquitectura Ice Lake/Sunny Cove), frecuencia base: 1,3 GHz, frecuencia turbo 
; máxima 3,90 GHz. Es compatible con el conjunto de instrucciones AVX512F. Tiene 4 
; cachés de instrucciones L1 de 32 000 y 4 cachés de datos de 48 000, 4 cachés L2 de 
; 512 000 y 8 MB de caché L3.
; Alineación de destino
; En bloques de 32K puestos a cero por rep stosb, el rendimiento fue de 175231 MB/s 
; para destinos desalineados por 1 byte (p. ej. $7FF4FDCFFFFF) y aumentó rápidamente 
; a 219464 MB/s para alineados por 64 bytes (p. ej. $7FF4FDCFFFC0), y luego aumentó 
; gradualmente a 222424 MB/s para destinos alineados por 256 bytes (Alineados a 256 
; bytes, es decir, $7FF4FDCFFF00). Después de eso, la velocidad no aumentó, incluso 
; si el destino estaba alineado por 32 KB (p. ej. $7FF4FDD00000), y seguía siendo 224850 MB/s.
; 
; No hubo diferencia en la velocidad entre rep stosb y rep stosq.
; En los buffers alineados por 32K, la velocidad del almacenamiento AVX-512 fue 
; exactamente la misma
; Lo mismo que para rep stosb, los bucles for comienzan con 2 almacenamientos en 
; un bucle (227777 MB/seg) y no crecen para los bucles for desenrollados para 4 e 
; incluso 16 almacenamientos. Sin embargo, para un bucle de solo 1 almacenamiento, 
; la velocidad fue un poco menor: 203145 MB/seg.
; 
; Sin embargo, si el búfer de destino estaba desalineado por solo 1 byte, la velocidad 
; del almacenamiento AVX512 disminuía drásticamente, es decir, más de 2 veces, a 93811 
; MB/seg, en contraste con rep stosb en búferes similares, que arrojaba 175231 MB/seg.
 
global memsetK64

section .text
memsetK64:
    %ifdef WIN64
    %elifdef WIN32
    %error "No se admite la arquitectura de 32 bits"
    %elifdef ELF64
    ; para linux:
    ; reajustar los registros:
    mov r8,  rdx
    mov rdx, rsi
    mov rcx, rdi

    %elifdef ELF32
        %error "No se admite la arquitectura de 32 bits"
    %else 
        %error "No se declaro WIN64-WIN32-ELF64-ELF32"
    %endif
    
    cmp r8, 8          ; count es menos que 8?
    jnb      .nottoend ; si no es asi no terminar 
    push qword 0       ; devolver NULL
    jmp .toend
    .nottoend:
    push rcx           ; guardar el puntero de destino para retornarlo en caso de exito

    cmp r8, 32         ; para casos pequeños de 32bytes
    jb    .not_stosq

    mov r10, r8
    and r10, 0b111 ; obtener cuantos bytes no se van a copiar de 8 en 8 y se deberan copiar 1 a 1
    shr r8, 3     ; dividir entre 8 para saber cuantos bytes copiar de 8 en 8

    ; en teoria, esto solo es medianamente rentable si el búfer es mas de 128bytes?
    mov     rdi, rcx   ; memoria a poner a 0
    mov     rcx, r8    ; decrementador
    mov     rax, rdx   ; valor que escribir
    rep     stosq
    ;xchg r10, rdi
    xchg r8, rdi       ; poner el puntero en r8 para el bucle byte a byte
    mov  rcx, r10      ; poner en rcx el numero de bytes que faltan, es la "i" del loop
    mov  rdi, r10      ; se usa para indicar cuantos bytes faltan
    jmp .toend_pancket ; en rdx ya esta el valor a poner

    .not_stosq:
        ;     void *dest,   -> rcx
        ;     size_t count  -> r8
        xchg rcx, r8          ; en rcx a de ir la longitud del buffer para usar la instruccion loop

        test rax, 7           ; Realiza una operación AND entre eax y 7 (111), 8 (1000)
        jnz .no_es_multiplo_8 ; Si el resultado es cero, salta a 'no_es_multiplo_8'

        ; desplazar 3 bits a la derecha, es dividir entre 8,
        ; desplazar 2 bits a la derecha, es dividir entre 4,
        ; desplazar 1 bit a la derecha, es dividir entre 2,
        
        mov rdi, rcx
        and rdi, 0b111 ; obtener cuantos bytes no se van a copiar de 8 en 8 y se deberan copiar 1 a 1
        shr rcx, 3     ; dividir entre 8 para saber cuantos bytes copiar de 8 en 8
        ;mov r9, rcx
        ;shl r9, 3
        ;and rdi, r9
        .es_multiplo8:
            mov [r8], qword rdx
            add r8, 8
            loop .es_multiplo8
            jmp .toend_pancket
        .no_es_multiplo_8:
            test rax, 3          ; Realiza una operación AND entre eax y 3 (11), 4 (100)
            jnz .no_es_multiplo_4 ; Si el resultado es cero, salta a 'no_es_multiplo_4'
            shr rcx, 2
            .es_multiplo4:
                mov [r8], dword edx
                add r8, 4
                loop .es_multiplo4
                jmp .toend_pancket
            .no_es_multiplo_4:
                test rax, 1          ; Realiza una operación AND entre eax y 1 (1), 4 (10)
                jnz .no_es_multiplo_2 ; Si el resultado es cero, salta a 'no_es_multiplo_2'
                shr rcx, 1
                .es_multiplo2:
                    mov [r8], word dx
                    add r8, 2
                    loop .es_multiplo2
                    jmp .toend_pancket
                .no_es_multiplo_2:

                .toend_pancket:
                    test rdi, rdi ; si rdi es 0, no hay mas que copiar
                    jz .toend
                    mov rcx, rdi ; si queda algun byte, copiarlo byte a byte
                .es_multiplo1:
                    mov [r8], byte dl
                    inc r8
                    loop .es_multiplo1

    .toend:
        pop  rax ; obtener el puntero de destino original
        ret