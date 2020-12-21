;
; BASIC-DOS Library Console Functions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	cmd.inc

CODE    SEGMENT

	EXTNEAR	<parseDOS,freeStr>
	EXTSTR	<STR_ON,STR_OFF>

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; callDOS
;
; Process DOS command generated by genDOS.
;
; Inputs:
;	[pHandler] -> handler offset
;	[idKeyword] -> keyword ID
;	[cbCmdLine] == length of command line
;	[pCmdLine] -> seg:off of command line
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, ES
;
DEFPROC	callDOS,FAR
	ARGVAR	pHandler,word
	ARGVAR	idKeyword,word
	ARGVAR	cbCmdLine,word
	ARGVAR	pCmdLine,dword
	ENTER
	push	ds
	push	[idKeyword]
	mov	dx,[pHandler]
	mov	cx,[cbCmdLine]		; CX = length
	lds	si,[pCmdLine]		; DS:SI -> command
;
; The line at DS:SI may be sitting in LINEBUF, which is large enough to
; accommodate lines up to 255 characters.  However, DOS commands (at least
; external commands) are more constrained; for example, command tails
; are limited to 127 characters (see PSP_CMDTAIL).
;
; Since cmdFile (the function that processes external commands) also wants
; to use LINEBUF, we're going to copy as much as we can to space available
; in the PSP; but instead of starting at PSP_CMDTAIL, we'll start at PSP_FCB2,
; which provides enough room for a filename plus a command tail.
;
	push	ss
	pop	es
	mov	di,PSP_FCB2		; ES:DI -> PSP_FCB2
	cmp	cx,size PSP - PSP_FCB2 - 1
	jbe	cd1
	mov	cx,size PSP - PSP_FCB2 - 1
cd1:	push	cx
	push	es
	push	di
	rep	movsb
	mov	al,0			; null-terminate for good measure
	stosb
	pop	si
	pop	ds			; DS:SI -> PSP_FCB2
	pop	cx
	mov	bx,es:[PSP_HEAP]
	lea	di,[bx].TOKENBUF	; ES:DI -> TOKENBUF
	mov	[di].TOK_MAX,(size TOK_DATA) / (size TOKLET)
	DOSUTIL	TOKEN1
	ASSERT	NC
	pop	ax			; AX = keyword ID, if any
	mov	cl,[di].TOK_DATA[0].TOKLET_LEN
	call	parseDOS		; CX = length of first token only
	pop	ds
	LEAVE
	RETURN
ENDPROC	callDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; clearScreen
;
; Used by "CLS".
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX
;
DEFPROC	clearScreen,FAR
	mov	bx,STDOUT
	sub	cx,cx
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SCROLL
	int	21h
	ret
ENDPROC	clearScreen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printArgs
;
; Used by "PRINT [args]"
;
; Since expressions are evaluated left-to-right, their results are pushed
; left-to-right as well.  Since the number of parameters is variable, we
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

pa1:	mov	al,[bp]			; AL = arg type
	test	al,al
	jz	pa3
pa2:	push	bp
	lea	bp,[bp+2]
	cmp	al,VAR_LONG		; if AL < VAR_LONG that's trouble
	jb	pa1
	lea	bp,[bp+4]
	cmp	al,VAR_DOUBLE
	jb	pa1
	ASSERT	Z			; if AL > VAR_DOUBLE that's trouble
	lea	bp,[bp+4]		; because we don't know how to print
	jmp	pa1			; VAR_FUNC or VAR_ARRAY variables

pa3:	mov	al,VAR_NEWLINE
	lea	bp,[bp+2]
	sub	bp,bx
	mov	bx,bp			; BX = # bytes to clean off stack

pa4:	pop	bp
	test	bp,bp			; end-of-args marker?
	jz	pa8			; yes

	mov	al,[bp]			; AL = arg type
	cmp	al,VAR_SEMI
	je	pa4a
	cmp	al,VAR_COMMA
	jne	pa5
	PRINTF	<CHR_TAB>
pa4a:	mov	al,VAR_NONE		; if we end on this, there's no NEWLINE
	jmp	pa4
;
; Check for numeric types first.  VAR_LONG is it for now.
;
pa5:	cmp	al,VAR_LONG
	jne	pa6
	mov	ax,[bp+2]
	mov	dx,[bp+4]
;
; As the itoa code in sprintf.asm explains, we use the '#' (hash) flag with
; decimal output to signify that a space should precede positive values.
;
	PRINTF	<"%#ld ">,ax,dx		; DX:AX = 32-bit value
	jmp	pa4
;
; Check for string types next.  VAR_STR is a normal string reference (eg,
; a string constant in a code block, or a string variable in a string block),
; whereas VAR_TSTR is a temporary string (eg, the result of some string
; operation) which we must free after printing.
;
pa6:	cmp	al,VAR_TSTR
	jbe	pa7
	ASSERT	NEVER			; more types may be supported someday
	jmp	pa4

pa7:	push	ax
	push	ds
	lds	si,[bp+2]
;
; Write AX bytes from DS:SI to STDOUT.  PRINTF would be simpler, but it's
; not a good idea, largely because the max length of string is greater than
; our default PRINTF buffer, and because it would be slower with no benefit.
;
	call	writeStr

	pop	ds
	pop	ax
	cmp	al,VAR_TSTR		; if it's not VAR_TSTR
	jne	pa4			; then we're done

	push	ds
	pop	es
	lea	di,[si-1]
	call	freeStr			; ES:DI -> string data to free
	jmp	pa4
;
; We've reached the end of arguments, wrap it up.
;
pa8:	test	al,al			; unless AL is zero
	jz	pa9			; we want to end on a new line
	PRINTF	<13,10>

pa9:	pop	dx			; remove return address
	pop	cx
	add	sp,bx			; clean the stack
	push	cx			; restore the return address
	push	dx
	ret
ENDPROC	printArgs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printEcho
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX
;
DEFPROC	printEcho,FAR
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].CMD_FLAGS,CMD_NOECHO
	mov	bx,offset STR_ON
	jz	pe1
	mov	bx,offset STR_OFF
pe1:	PRINTF	<"ECHO is %ls",13,10>,bx,cs
	ret
ENDPROC	printEcho

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printLine
;
; Inputs:
;	Pointer to length-prefixed string pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	printLine,FAR
	mov	bx,ss:[PSP_HEAP]
	test	ss:[bx].CMD_FLAGS,CMD_NOECHO
	jz	pl1
	ret	4
pl1:	PRINTF	<13,10>			; fall into printStr
ENDPROC	printLine

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; printStr
;
; Inputs:
;	Pointer to length-prefixed string pushed on stack
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	printStr,FAR
	ARGVAR	pStr,dword
	ENTER
	push	ds
	lds	si,[pStr]		; DS:SI -> length-prefixed string
	call	writeStrCRLF
	pop	ds
	LEAVE
	RETURN
ENDPROC	printStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeStr
;
; Inputs:
;	DS:SI -> length-prefixed string
;
; Outputs:
;	AX = # bytes printed
;	SI updated to end of string
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	writeStr
	push	bx
	lodsb				; AL = string length (255 max)
	mov	ah,0
	xchg	cx,ax			; CX = length
	mov	dx,si			; DS:DX -> data
	add	si,cx
	mov	bx,STDOUT
	mov	ah,DOS_HDL_WRITE
	int	21h
	pop	bx
	ret
ENDPROC	writeStr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; writeStrCRLF
;
; Inputs:
;	DS:SI -> length-prefixed string
;
; Outputs:
;	AX = # bytes written
;	SI updated to end of string
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	writeStrCRLF
	call	writeStr
	PRINTF	<13,10>
	ret
ENDPROC	writeStrCRLF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setColor
;
; Used by "COLOR fgnd[,bgnd[,border]]"
;
; Inputs:
;	N numeric expressions pushed on stack (only 1st 3 are processed)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI, DI
;
DEFPROC	setColor,FAR
	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_GETCOLOR
	mov	bx,STDOUT
	int	21h			; DX = current colors
	ASSERT	NC			; (assuming success)
	pop	si
	pop	di			; DI:SI = return address
	pop	cx			; CX = # args
sc1:	cmp	cl,4
	jb	sc2
	pop	ax
	pop	bx
	dec	cx
	jmp	sc1
sc2:	cmp	cl,3
	jne	sc3
	pop	ax
	pop	bx
	mov	dh,al
	dec	cx
sc3:	cmp	cl,2
	jne	sc4
	pop	ax
	pop	bx
	and	al,0Fh
	and	dl,0Fh
	shl	al,cl
	shl	al,cl
	or	dl,al
	dec	cx
sc4:	cmp	cl,1
	jne	sc5
	pop	ax
	pop	bx
	and	al,0Fh
	and	dl,0F0h
	or	dl,al
sc5:	mov	ax,(DOS_HDL_IOCTL SHL 8) OR IOCTL_SETCOLOR
	mov	bx,STDOUT
	mov	cx,dx			; CX = new colors
	int	21h
	push	di			; push return address back on stack
	push	si
	ret
ENDPROC	setColor

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; setFlags
;
; If AL contains a single bit, that bit will be set in CMD_FLAGS;
; otherwise, AL will be used as a mask to clear bit(s) in CMD_FLAGS.
;
; Inputs:
;	AL = bit to set (eg, CMD_NOECHO) or clear (eg, NOT CMD_ECHO)
;
; Outputs:
;	None
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	setFlags,FAR
	mov	bx,ss:[PSP_HEAP]
	mov	ah,al
	dec	ah			; AH = flags - 1
	and	ah,al			; if (flags - 1) AND flags is zero
	jz	sf1			; then AL contains a single bit to set
	and	ss:[bx].CMD_FLAGS,al
	xor	al,al
sf1:	or	ss:[bx].CMD_FLAGS,al
	ret
ENDPROC	setFlags

CODE	ENDS

	end
