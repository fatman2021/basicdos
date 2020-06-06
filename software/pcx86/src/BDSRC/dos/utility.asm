;
; BASIC-DOS Utility Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	DEFLBL	UTILTBL,word
	dw	util_strlen,util_decimal			; 00h-03h
	DEFABS	UTILTBL_SIZE,<($ - UTILTBL) SHR 1>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; util_func (REG_AH = 18h)
;
; Inputs:
;	REG_AL = utility function (eg, UTIL_DECIMAL)
;
; Outputs:
;	Varies
;
DEFPROC	util_func,DOS
	mov	bl,[bp].REG_AL		; BL = utility function
	cmp	bl,UTILTBL_SIZE
	cmc
	jb	dc9
	mov	bh,0
	add	bx,bx
	lds	si,dword ptr [bp].REG_SI
	les	di,dword ptr [bp].REG_DI
	ASSUME	DS:NOTHING,ES:NOTHING
	call	UTILTBL[bx]
	mov	[bp].REG_SI,si
	mov	[bp].REG_DI,di
	mov	[bp].REG_AX,ax		; update REG_AX and return CARRY
dc9:	ret
ENDPROC	util_func

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Returns the length of the null-terminated DS:SI string in AX.
;
; Modifies:
;	AX
;
DEFPROC	util_strlen
	push	di
	mov	di,si
	push	ds
	pop	es
	mov	al,0
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	je	usl9
	stc				; error if we didn't end on a match
usl9:	sub	di,si
	lea	ax,[di-1]		; don't count the ending null
	pop	di
	ret
ENDPROC	util_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Convert string at ES:DI to decimal, then validate using values at DS:SI.
;
; Returns:
;	AX = value, ES:DI -> next character (after non-decimal digit)
;	Carry will be set if there was an error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, SI, DI
;
DEFPROC	util_decimal
	push	cx
	push	dx
	sub	ax,ax
	cwd
	mov	cx,10
ud1:	mov	dl,es:[di]
	sub	dl,'0'
	jb	ud6
	cmp	dl,cl
	jae	ud6
	inc	di
	push	dx
	mul	cx
	pop	dx
	add	ax,dx
	jmp	ud1
ud6:	test	dl,dl
	jz	ud7
	inc	di
ud7:	cmp	ax,[si]			; too small?
	jae	ud8			; no
	mov	ax,[si]
	jmp	short ud9
ud8:	cmp	[si+2],ax		; too large?
	jae	ud9			; no
	mov	ax,[si+2]
ud9:	lea	si,[si+4]		; advance SI in case there are more
	pop	dx
	pop	cx
	ret
ENDPROC util_decimal

DOS	ends

	end