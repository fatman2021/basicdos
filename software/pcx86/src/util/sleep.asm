;
; BASIC-DOS Sleep Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

CODE    SEGMENT

	org	100h

        ASSUME  CS:CODE, DS:CODE, ES:CODE, SS:CODE
DEFPROC	main
	mov	ax,(DOS_MSC_SETVEC SHL 8) + INT_DOSCTRLC
	mov	dx,offset ctrlc
	int	21h

	mov	ax,2
	mov	si,PSP_CMDTAIL
	cmp	[si],ah
	je	s1
	inc	si
	mov	bl,10
	mov	di,-1		; no ATOI validation
	mov	ax,DOS_UTL_ATOI
	int	21h		; DX:AX = value (# of seconds)

s1:	push	ax
	PRINTF	<"sleeping %d seconds...">,ax
	pop	ax
	mov	dx,1000
	mul	dx		; DX:AX = AX * 1000 (# of milliseconds)
	mov	cx,dx
	xchg	dx,ax		; CX:DX = # of milliseconds
	mov	ax,DOS_UTL_SLEEP
	int	21h
	PRINTF	<13,10,"feeling refreshed!",13,10>
	int	20h
ENDPROC	main

DEFPROC	ctrlc,FAR
	push	ax
	PRINTF	<"CTRL-C intercepted",13,10>
	pop	ax
	iret
ENDPROC	ctrlc

;
; COMHEAP 0 means we don't need a heap, but the system will still allocate
; a minimum amount of heap space, because that's where our initial stack lives.
;
	COMHEAP	0		; COMHEAP (heap size) must be the last item

CODE	ENDS

	end	main
