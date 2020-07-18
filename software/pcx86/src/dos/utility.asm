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

	EXTERNS	<chk_devname,dev_request,write_string>,near
	EXTERNS	<scb_load,scb_start,scb_stop,scb_unload>,near
	EXTERNS	<scb_yield,scb_delock,scb_wait,scb_endwait>,near
	EXTERNS	<mem_query>,near
	EXTERNS	<psp_term_exitcode>,near
	EXTERNS	<itoa,sprintf>,near

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active>,word
	EXTERNS	<scb_table,clk_ptr>,dword

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strlen (AX = 1800h or 1824h)
;
; Returns the length of the REG_DS:SI string in AX, using the terminator in AL.
;
; Modifies:
;	AX
;
DEFPROC	utl_strlen,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	call	strlen
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
	DEFLBL	strlen,near		; for internal calls (no REG_FRAME)
	push	cx
	push	di
	push	es
	push	ds
	pop	es
	mov	di,si
	mov	cx,di
	not	cx			; CX = largest possible count
	repne	scasb
	je	sl8
	sub	ax,ax			; operation failed
	stc				; return carry set and zero length
	jmp	short sl9
sl8:	sub	di,si
	lea	ax,[di-1]		; don't count the terminator character
sl9:	pop	es
	pop	di
	pop	cx
	ret
ENDPROC	utl_strlen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strstr (AX = 1801h)
;
; Find string (DS:SI) in string (ES:DI)
;
; Inputs:
;	REG_DS:REG_SI = source string
;	REG_ES:REG_DI = target string
;
; Outputs:
;	On match, carry clear, and REG_DI is updated with position of match
;	Otherwise, carry set (no registers modified)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	utl_strstr,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_ES
	ASSUME	DS:NOTHING
	xchg	si,di
	mov	al,0
	call	strlen
	xchg	dx,ax			; DX = length of target string
	xchg	si,di
	mov	es,[bp].REG_ES
	ASSUME	ES:NOTHING
	mov	ds,[bp].REG_DS
	mov	al,0
	call	strlen
	xchg	bx,ax			; BX = length of source string

	lodsb				; AX = first char of source
	test	al,al
	stc
	jz	ss9

	mov	cx,dx
ss1:	repne	scasb			; scan all remaining target chars
	stc
	jne	ss9
	clc				; clear the carry in case CX is zero
	push	cx			; (in that case, cmpsb won't clear it)
	mov	cx,bx
	dec	cx
	push	si
	push	di
	rep	cmpsb			; compare all remaining source chars
	pop	di
	pop	si
	pop	cx
	je	ss8			; match (and carry clear)
	mov	dx,cx
	jmp	ss1

ss8:	dec	di
	mov	[bp].REG_DI,di

ss9:	ret
ENDPROC	utl_strstr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_strupr (AX = 1803h)
;
; Makes the string at REG_DS:SI with length CX upper-case; use length 0
; if null-terminated.
;
; Outputs:
;	None
;
; Modifies:
;	AX (but not REG_AX)
;
DEFPROC	utl_strupr,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	DEFLBL	strupr,near		; for internal calls (no REG_FRAME)
	push	si
su1:	mov	al,[si]
	test	al,al
	jz	su9
	cmp	al,'a'
	jb	su2
	cmp	al,'z'
	ja	su2
	sub	al,20h
	mov	[si],al
su2:	inc	si
	loop	su1
su9:	pop	si
	ret
ENDPROC	utl_strupr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi16 (AX = 1806h)
;
; Convert string at DS:SI to number in AX using base BL, using validation
; values at ES:DI.
;
; ES:DI must point to a triplet of (def,min,max) 16-bit values; and like SI,
; DI will be advanced, making it easy to parse a series of values, each with
; their own set of (def,min,max) values.
;
; Returns:
;	AX = value, DS:SI -> next character (after any non-digit)
;	Carry will be set on a validation error, but AX will ALWAYS be valid
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi16,DOS
	sti
	mov	bl,[bp].REG_BL		; BL = base (eg, 10)
	mov	bh,0
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY

	mov	ah,-1			; cleared when digit found
	sub	cx,cx			; CX:DX = value
	sub	dx,dx			; (will be returned in DX:AX)
	push	bp
	sub	bp,bp			; BP will be negative if # is negative

ai0:	lodsb				; skip any leading whitespace
	cmp	al,CHR_SPACE
	je	ai0
	cmp	al,CHR_TAB
	je	ai0

	cmp	al,'-'			; minus sign?
	jne	ai1			; no
	test	bp,bp			; already negated?
	jl	ai6			; yes, not good
	dec	bp			; make a note to negate later
	jmp	short ai4

ai1:	cmp	al,'a'			; remap lower-case
	jb	ai2			; to upper-case
	sub	al,20h
ai2:	cmp	al,'A'			; remap hex digits
	jb	ai3			; to characters above '9'
	cmp	al,'F'
	ja	ai6			; never a valid digit
	sub	al,'A'-'0'-10
ai3:	cmp	al,'0'			; convert ASCII digit to value
	jb	ai5
	sub	al,'0'
	cmp	al,bl			; outside the requested base?
	jae	ai6			; yes
	cbw				; clear AH (digit found)
;
; Multiply CX:DX by the base in BX before adding the digit value in AX.
;
	push	ax
	push	di
	mov	ax,dx
	mul	bx
	xchg	ax,cx
	mov	di,dx
	mul	bx
	add	ax,di
	adc	dx,0			; DX:AX:CX contains the result
	xchg	ax,cx			; DX:CX:AX now
	xchg	ax,dx			; AX:CX:DX now
	pop	di
	pop	ax			; CX:DX = CX:DX * BX

	add	dx,ax			; add the digit value in AX now
	adc	cx,0
ai4:	lodsb				; fetch the next character
	jmp	ai1			; and continue the evaluation

ai5:	test	al,al			; normally we skip the first non-digit
	jnz	ai6			; but if it's a null
	dec	si			; rewind

ai6:	test	bp,bp
	jge	ai6a
	neg	cx
	neg	dx
	sbb	cx,0
ai6a:	pop	bp

	cmp	di,-1			; validation data provided?
	jne	ai6b			; yes
	add	ah,1			; (carry clear if one or more digits)
	jmp	short ai9
ai6b:	test	ah,ah			; any digits?
	jz	ai6c			; yes
	mov	dx,es:[di]		; no, get the default value
	stc
	jmp	short ai8
ai6c:	cmp	dx,es:[di+2]		; too small?
	jae	ai7			; no
	mov	dx,es:[di+2]		; yes (carry set)
	jmp	short ai8
ai7:	cmp	es:[di+4],dx		; too large?
	jae	ai8			; no
	mov	dx,es:[di+4]		; yes (carry set)
ai8:	lea	di,[di+6]		; advance DI in case there are more
	mov	[bp].REG_DI,di		; update REG_DI
	jmp	short ai9a

ai9:	mov	[bp].REG_DX,cx		; update REG_DX if no validation data
ai9a:	mov	[bp].REG_AX,dx		; update REG_AX
	mov	[bp].REG_SI,si		; update caller's SI, too
	ret
ENDPROC utl_atoi16

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_atoi32 (AX = 1807h)
;
; Convert string at DS:SI to number in DX:AX using base BL.
;
; Returns:
;	Carry clear if one or more digits, set otherwise
;	DX:AX = value, DS:SI -> next character (after any non-digit)
;
; Modifies:
;	AX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_atoi32,DOS
	mov	di,-1			; setting no validation allows
	jmp	utl_atoi16		; atoi16 to return a 32-bit value
ENDPROC utl_atoi32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_itoa (AX = 1808h)
;
; Convert the value DX:SI to a string representation at ES:DI, using base BL,
; flags BH (see itoa for PF definitions), minimum length CX (0 for no minimum).
;
; Returns:
;	ES:DI filled in
;	AL = # of digits
;
; Modifies:
;	AX, CX, DX, ES
;
DEFPROC	utl_itoa,DOS
	sti
	xchg	ax,si			; DX:AX is now the value
	mov	es,[bp].REG_ES		; ES:DI -> buffer
	ASSUME	ES:NOTHING
	call	itoa
	mov	[bp].REG_AX,ax		; update REG_AX
	ret
ENDPROC	utl_itoa

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_printf (AX = 1809h)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; See utl_sprintf for more details.
;
; Inputs:
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters printed
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	utl_printf,DOS
	sti
	push	ss
	pop	es
	ASSUME	ES:NOTHING
	sub	sp,BUFLEN + offset SPF_CALLS
	mov	cx,BUFLEN		; CX = length
	mov	di,sp			; ES:DI -> buffer on stack
	mov	bx,[bp].REG_IP
	mov	ds,[bp].REG_CS		; DS:BX -> format string
	ASSUME	DS:NOTHING
	call	sprintf
	mov	si,sp
	push	ss
	pop	ds			; DS:SI -> buffer on stack
	xchg	cx,ax			; CX = # of characters
	call	write_string
	add	sp,BUFLEN + offset SPF_CALLS
	mov	[bp].REG_AX,cx		; update REG_AX with count in CX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	ret
ENDPROC	utl_printf endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sprintf (AX = 180Ah)
;
; A semi-CDECL-style calling convention is assumed, where all parameters
; EXCEPT for the format string are pushed from right to left, so that the
; first (left-most) parameter is the last one pushed.  The format string
; is stored in the CODE segment following the INT 21h, which we automatically
; skip, and the next instruction should be an "ADD SP,N*2", assuming N word
; parameters.
;
; When printing 32-bit values, list the low word first, then the high word,
; so that the high word is pushed first.
;
; The code relies on SPF_FRAME, which must accurately reflect the number of
; additional bytes pushed onto the stack since REG_FRAME was created.
; Obviously that could be calculated at run-time, but it's preferable to know
; the value at assembly-time so that we can use constant displacements and
; simplify register usage.
;
; Inputs:
;	DS:BX -> format string
;	ES:DI -> output buffer
;	CX = length of buffer
;	format string follows the INT 21h
;	all other parameters must be pushed onto the stack, right to left
;
; Outputs:
;	REG_AX = # of characters generated
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
; See sprintf.asm for a list of supported format specifiers.
;
DEFPROC	utl_sprintf,DOS
	sti
	mov	ds,[bp].REG_DS
	mov	es,[bp].REG_ES
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	bx,[bp].REG_BX		; DS:BX -> format string
	sub	sp,offset SPF_CALLS
	call	sprintf
	add	sp,offset SPF_CALLS
	mov	[bp].REG_AX,ax		; update REG_AX with count in AX
	add	[bp].REG_IP,bx		; update REG_IP with length in BX
	ret
ENDPROC	utl_sprintf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokify (AX = 180Bh)
;
; Inputs:
;	REG_AL = token type (TODO)
;	REG_DS:REG_SI -> BUF_INPUT
;	REG_ES:REG_DI -> BUF_TOKENS
;
; Outputs:
;	AX = # tokens; token buffer updated
;
; Modifies:
;	AX
;
DEFPROC	utl_tokify,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> BUF_INPUT
	mov	es,[bp].REG_ES		; ES:DI -> BUF_TOKENS
	ASSUME	DS:NOTHING, ES:NOTHING

	LOCVAR	pStart,word
	ENTER

	sub	bx,bx			; BX = token index
	add	si,offset INP_BUF	; SI -> 1st character
	mov	[pStart],si		; BP = starting position
	lodsb				; preload the first character
	jmp	tf8			; and dive in
;
; Skip all whitespace in front of the next token.
;
tf1:	lodsb
tf2:	cmp	al,CHR_RETURN
	je	tf9
	cmp	al,CHR_SPACE
	je	tf1
	cmp	al,CHR_TAB
	je	tf1
;
; For the next token word-pair, we need to record the offset and the length;
; we know the offset already (SI-pStart-1), so put that in DX.
;
	lea	dx,[si-1]
	sub	dx,[pStart]		; DX = offset of next token
;
; Skip over the next token. This is complicated by additional rules, such as
; treating all quoted sequences as a single token.
;
	mov	ah,0			; AH = 0 (or quote char)
	cmp	al,'"'
	je	tf3
	cmp	al,"'"
	jne	tf4
tf3:	mov	ah,al
tf4:	lodsb
	cmp	al,CHR_RETURN
	je	tf6
	test	ah,ah			; did we start with a quote?
	jz	tf5			; no
	cmp	al,ah			; yes, so have we found another?
	jnz	tf4			; no
	lodsb				; yes, preload the next character
	jmp	short tf6		; and record the token length
tf5:	cmp	al,CHR_SPACE
	je	tf6
	cmp	al,CHR_TAB
	jne	tf4

tf6:	lea	cx,[si-1]
	sub	cx,[pStart]
	sub	cx,dx			; CX = length of token
;
; DX:CX has our next token pair; store it at the token index in BX
;
	add	bx,bx
	mov	es:[di+bx].TOK_BUF,dl
	mov	es:[di+bx+1].TOK_BUF,cl
	shr	bx,1
	inc	bx			; increment token index

tf8:	cmp	bl,es:[di].TOK_MAX	; room for more tokens?
	jb	tf2			; yes

tf9:	LEAVE

	mov	es:[di].TOK_CNT,bl	; update # tokens
	mov	[bp].REG_AX,bx		; return # tokens in AX, too
	ret
ENDPROC	utl_tokify

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_tokid (AX = 180Ch)
;
; Inputs:
;	REG_CX = token length
;	REG_DS:REG_SI -> token
;	REG_ES:REG_DI -> DEF_TOKENs
; Outputs:
;	If carry clear, AX = token ID (TOK_ID), DX = token data (TOK_DATA)
;	If carry set, token not found
;
; Modifies:
;	AX
;
DEFPROC	utl_tokid,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	mov	ds,[bp].REG_DS		; DS:SI -> token (length CX)
	mov	es,[bp].REG_ES		; ES:DI -> DEF_TOKENs
	ASSUME	DS:NOTHING, ES:NOTHING

	push	bp
	sub	bp,bp			; BP = top index
	mov	dx,es:[di]		; DX = number of tokens in DEF_TOKENs
	add	di,2

td0:	mov	ax,-1
	cmp	bp,dx
	stc
	je	td9
	mov	bx,dx
	add	bx,bp
	shr	bx,1			; BX = midpoint index

	push	bx
	IF	SIZE DEF_TOKEN EQ 6
	mov	ax,bx
	add	bx,bx
	add	bx,ax
	add	bx,bx
	ELSE
	ASSERT	B,<cmp bl,256>
	mov	al,size DEF_TOKEN
	mul	bl
	mov	bx,ax
	ENDIF
	mov	ch,es:[di+bx].TOK_LEN	; CH = length of current token
	mov	ax,cx			; CL is saved in AL
	push	si
	push	di
	mov	di,es:[di+bx].TOK_OFF	; ES:DI -> current token
td1:	cmpsb				; compare input to current
	jne	td2
	sub	cx,0101h
	jz	td2			; match!
	test	cl,cl
	stc
	jz	td2			; if CL exhausted, input < current
	test	ch,ch
	jz	td2			; if CH exhausted, input > current
	jmp	td1

td2:	pop	di
	pop	si
	jcxz	td8
;
; If carry is set, set the bottom range to BX, otherwise set the top range
;
	pop	bx			; BX = index of token we just tested
	xchg	cx,ax			; restore CL from AL
	jnc	td3
	mov	dx,bx			; new bottom is middle
	jmp	td0
td3:	inc	bx
	mov	bp,bx			; new top is middle + 1
	jmp	td0

td8:	sub	ax,ax			; zero AX (and carry, too)
	mov	al,es:[di+bx].TOK_ID	; AX = token ID
	mov	dx,es:[di+bx].TOK_DATA	; DX = user-defined token data
	pop	bx			; toss BX from stack

td9:	pop	bp
	jc	td9a
	mov	[bp].REG_DX,dx
	mov	[bp].REG_AX,ax
td9a:	ret
ENDPROC	utl_tokid

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_getdev (AX = 1810h)
;
; Returns DDH in ES:DI for device name at DS:DX.
;
; Inputs:
;	DS:DX -> device name
;
; Outputs:
;	ES:DI -> DDH if success; carry set if not found
;
; Modifies:
;	AX, CX, DI, ES (ie, whatever chk_devname modifies)
;
DEFPROC	utl_getdev,DOS
	sti
	mov	ds,[bp].REG_DS
	ASSUME	DS:NOTHING
	and	[bp].REG_FL,NOT FL_CARRY
	mov	si,dx
	call	chk_devname		; DS:SI -> device name
	jc	gd9
	mov	[bp].REG_DI,di
	mov	[bp].REG_ES,es
gd9:	ret
ENDPROC	utl_getdev

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_ioctl (AX = 1811h)
;
; Inputs:
;	REG_BX = IOCTL command (BH = driver command, BL = IOCTL command)
;	REG_ES:REG_DI -> DDH
;	Other registers will vary
;
; Modifies:
;	AX, DI, ES
;
DEFPROC	utl_ioctl,DOS
	sti
	mov	ax,[bp].REG_BX		; AX = command codes from BH,BL
	mov	es,[bp].REG_ES		; ES:DI -> DDH
	call	dev_request		; call the driver
	ret
ENDPROC	utl_ioctl

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_load (AX = 1812h)
;
; Inputs:
;	REG_CL = SCB #
;	REG_DS:REG_DX = name of program (or command-line)
;
; Outputs:
;	Carry clear if successful
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, DI, DS, ES
;
DEFPROC	utl_load,DOS
	sti
	mov	es,[bp].REG_DS
	and	[bp].REG_FL,NOT FL_CARRY
	ASSUME	DS:NOTHING		; CL = SCB #
	jmp	scb_load		; ES:DX -> name of program
ENDPROC	utl_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_start (AX = 1813h)
;
; "Start" the specified session (actual starting will handled by scb_switch)
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful, BX -> SCB
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_start,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
 	jmp	scb_start
ENDPROC	utl_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_stop (AX = 1814h)
;
; "Stop" the specified session
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_stop,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_stop
ENDPROC	utl_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unload (AX = 1815h)
;
; Unload the current program from the specified session
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear if successful
;	Carry set if error (eg, invalid SCB #)
;
DEFPROC	utl_unload,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_unload
ENDPROC	utl_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_yield (AX = 1816h)
;
; Asynchronous interface to decide which SCB should run next.
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_yield,DOS
	sti
	mov	ax,[scb_active]
	jmp	scb_yield
ENDPROC	utl_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_sleep (AX = 1817h)
;
; Converts DX from milliseconds (1000/second) to ticks (18.2/sec) and
; issues an IOCTL to the CLOCK$ driver to wait the corresponding # of ticks.
;
; 1 tick is equivalent to approximately 55ms, so that's the granularity of
; sleep requests.
;
; Inputs:
;	REG_CX:REG_DX = # of milliseconds to sleep
;
; Modifies:
;	AX, BX, CX, DX, DI, ES
;
DEFPROC	utl_sleep,DOS
	sti
	add	dx,27			; add 1/2 tick (as # ms) for rounding
	adc	cx,0
	mov	bx,55			; BX = divisor
	xchg	ax,cx			; AX = high dividend
	mov	cx,dx			; CX = low dividend
	sub	dx,dx
	div	bx			; AX = high quotient
	xchg	ax,cx			; AX = low dividend, CX = high quotient
	div	bx			; AX = low quotient
	xchg	dx,ax			; CX:DX = # ticks
	mov	ax,(DDC_IOCTLIN SHL 8) OR IOCTL_WAIT
	les	di,clk_ptr
	call	dev_request		; call the driver
	ret
ENDPROC	utl_sleep

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_wait (AX = 1818h)
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	utl_wait,DOS
	jmp	scb_wait
ENDPROC	utl_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_endwait (AX = 1819h)
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	REG_DX:REG_DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	utl_endwait,DOS
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	scb_endwait
ENDPROC	utl_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_hotkey (AX = 181Ah)
;
; Inputs:
;	REG_CX = CONSOLE context
;	REG_DL = char code, REG_DH = scan code
;
; Outputs:
;	Carry clear if successful, set if unprocessed
;
; Modifies:
;	AX
;
DEFPROC	utl_hotkey,DOS
	sti
	xchg	ax,dx			; AL = char code, AH = scan code
	and	[bp].REG_FL,NOT FL_CARRY
;
; Find the SCB with the matching context; that's the one with focus.
;
	mov	bx,[scb_table].OFF
hk1:	cmp	[bx].SCB_CONTEXT,cx
	je	hk2
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	hk1
	stc
	jmp	short hk9

hk2:	cmp	al,CHR_CTRLC
	jne	hk3
	or	[bx].SCB_CTRLC_ACT,1

hk3:	cmp	al,CHR_CTRLP
	clc
	jne	hk9
	xor	[bx].SCB_CTRLP_ACT,1

hk9:	ret
ENDPROC	utl_hotkey

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_lock (AX = 181Bh)
;
; Asynchronous interface to lock the current SCB
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_lock,DOS
	LOCK_SCB
	ret
ENDPROC	utl_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_unlock (AX = 181Ch)
;
; Asynchronous interface to unlock the current SCB
;
; Inputs:
;	None
;
; Modifies:
;	AX, BX, DX
;
DEFPROC	utl_unlock,DOS
	UNLOCK_SCB
	ret
ENDPROC	utl_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_qrymem (AX = 181Dh)
;
; Query info about memory blocks
;
; Inputs:
;	REG_CX = memory block # (0-based)
;	REG_DL = memory block type (0 for any, 1 for free, 2 for used)
;
; Outputs:
;	On success, carry clear:
;		REG_ES:0 -> MCB
;		REG_AX = owner ID (eg, PSP)
;		REG_DX = size (in paragraphs)
;		REG_DS:REG_BX -> owner name, if any
;	On failure, carry set (ie, no more blocks of the requested type)
;
; Modifies:
;	AX, BX, CX, DS, ES
;
DEFPROC	utl_qrymem,DOS
	sti
	and	[bp].REG_FL,NOT FL_CARRY
	jmp	mem_query
ENDPROC	utl_qrymem

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; utl_abort (AX = 181Fh)
;
; Inputs:
;	REG_DL = exit code
;	REG_DH = exit type
;
; Outputs:
;	None
;
DEFPROC	utl_abort,DOS
	xchg	ax,dx			; AL = exit code, AH = exit type
	jmp	psp_term_exitcode
ENDPROC	utl_abort

DOS	ends

	end
