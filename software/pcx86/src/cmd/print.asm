;
; BASIC-DOS Printing Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTERNS	<freeStr>,near

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printArgs
;
; Since expressions are evaluated left-to-right, their results are pushed
; left-to-right as well.  Since the number of parameters is variable, we must
; walk the stacked parameters back to the beginning, pushing the offset of
; each as we go, and then popping and printing our way back to the end again.
;
; Inputs:
;	N pairs of variable types/values pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	printArgs,FAR
	mov	bp,sp
	add	bp,4
	sub	bx,bx
	push	bx			; push end-of-args marker
	mov	bx,bp

p1:	mov	al,[bp]			; AL = arg type
	test	al,al
	jz	p3
p2:	push	bp
	lea	bp,[bp+2]
	cmp	al,VAR_INT
	jb	p1
	lea	bp,[bp+2]
	je	p1
	lea	bp,[bp+2]
	cmp	al,VAR_DOUBLE
	jb	p1
	lea	bp,[bp+4]
	jmp	p1

p3:	mov	al,VAR_NEWLINE
	lea	bp,[bp+2]
	sub	bp,bx
	mov	cs:[nPrintArgsRet],bp	; modify the RETF N with proper N

p4:	pop	bp
	test	bp,bp			; end-of-args marker?
	jz	p8			; yes
	mov	al,[bp]			; AL = arg type
	cmp	al,VAR_SEMI
	je	p4
	cmp	al,VAR_COMMA
	jne	p5
	PRINTF	<CHR_TAB>
	jmp	p4

p5:	cmp	al,VAR_LONG
	jne	p6
	push	ax
	mov	ax,[bp+2]
	mov	dx,[bp+4]
	PRINTF	<"%#ld ">,ax,dx		; DX:AX = 32-bit value
	pop	ax
	jmp	p4

p6:	cmp	al,VAR_STR
	je	p7
	cmp	al,CLS_STR
	jne	p4			; TODO: error instead?
p7:	push	ax
	lds	si,[bp+2]
	lodsb
	mov	ah,0			; AX = string length (255 max)
;
; TODO: The default PRINTF buffer is smaller than the maximum string size,
; so this function will need to SPRINTF to an internal buffer and then use a
; standard DOS call to write to STDOUT.
;
	PRINTF	<"%.*ls ">,ax,si,ds	; DS:SI -> string
	push	ds
	pop	es
	mov	di,si
	call	freeStr			; ES:DI -> string data to free
	pop	ax
	jmp	p4

p8:	cmp	al,VAR_NEWLINE		; did we want to start a new line?
	jb	p9			; no
	PRINTF	<13,10>
p9:	db	OP_RETF_N
	DEFLBL	nPrintArgsRet,word
	dw	0
ENDPROC	printArgs

CODE	ENDS

	end
