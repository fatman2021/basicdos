;
; BASIC-DOS Session Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<scb_locked>,byte
	EXTERNS	<scb_active,psp_active>,word
	EXTERNS	<scb_table>,dword
	EXTERNS	<dos_exit,load_program>,near

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_scb
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	On success, carry clear, BX -> specified SCB
;	On failure, carry set (if SCB invalid or not initialized for use)
;
; Modifies:
;	AX, BX
;
DEFPROC	get_scb,DOS
	mov	al,size SCB
	mul	cl
	add	ax,[scb_table].OFF
	cmp	ax,[scb_table].SEG
	cmc
	jb	gs9
	mov	bx,ax
	test	[bx].SCB_STATUS,SCSTAT_INIT
	jnz	gs9
	stc
gs9:	ret
ENDPROC	get_scb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_scbnum
;
; Inputs:
;	None
;
; Outputs:
;	AL = SCB # of scb_active (-1 if error)
;
; Modifies:
;	AX
;
DEFPROC	get_scbnum,DOS
	ASSUME	ES:NOTHING
	mov	ax,[scb_active]
	sub	ax,[scb_table].OFF
	ASSERT	NC
	jnc	gsn1
	sbb	ax,ax
	jmp	short gsn9
gsn1:	push	dx
	mov	dl,size SCB
	div	dl
	pop	dx
gsn9:	ret
ENDPROC	get_scbnum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_load
;
; Loads a program into the specified session.
;
; Inputs:
;	CL = SCB #
;	ES:DX -> name of program (or command-line)
;
; Outputs:
;	Carry set if error, AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	scb_load,DOS
	ASSUME	ES:NOTHING
	call	scb_lock
	jc	sl9
	push	ax			; save previous SCB
	call	load_program
	push	cs
	pop	ds
	ASSUME	DS:DOS
	jc	sl8
	mov	bx,[scb_active]
	call	scb_init
sl8:	pop	ax			; recover previous SCB
	call	scb_unlock		; unlock
sl9:	ret
ENDPROC	scb_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_init
;
; Mark the specified session as "loaded" and ready to start.
;
; Inputs:
;	BX -> SCB
;	DX:DI = initial stack pointer
;
; Modifies:
;	AX, BX, CX, ES, DI
;
DEFPROC	scb_init,DOS
	ASSUME	ES:NOTHING
	ASSERT	STRUCT,[bx],SCB
	mov	[bx].SCB_STACK.OFF,di
	mov	[bx].SCB_STACK.SEG,dx
	or	[bx].SCB_STATUS,SCSTAT_LOAD
	ret
ENDPROC	scb_init

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_lock
;
; Activate and lock the specified SCB
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	On success, carry clear, AX -> previous SCB, BX -> current SCB
;	On failure, carry set (if SCB invalid or not initialized for use)
;
; Modifies:
;	AX, BX, CX, SI, DI
;
DEFPROC	scb_lock,DOS
	ASSUME	ES:NOTHING
	call	get_scb
	jc	sk9
	inc	[scb_locked]
	push	dx
	xchg	bx,[scb_active]		; BX -> previous SCB, if any
	test	bx,bx
	jz	sk8
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
sk8:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
	push	ds
	push	es
	push	ds
	pop	es
	ASSUME	ES:DOS
	lea	di,[bx].SCB_EXRET	; ES:DI -> SCB vectors
	sub	si,si
	mov	ds,si
	ASSUME	DS:BIOS
	mov	si,INT_DOSEXRET * 4	; DS:SI -> IVT vectors
	mov	cx,6			; move 3 vectors (6 words)
	rep	movsw
	pop	es
	pop	ds
	ASSUME	DS:DOS
	pop	dx
sk9:	ret
ENDPROC	scb_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unlock
;
; Restore the previous SCB and lock state
;
; Inputs:
;	AX -> previous SCB
;	BX -> current SCB
;
; Modifies:
;	BX, DX (but not carry)
;
DEFPROC	scb_unlock,DOS
	pushf
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
	mov	[scb_active],ax
	test	ax,ax
	jz	su9
	xchg	bx,ax			; BX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
su9:	dec	[scb_locked]
	popf
	ret
ENDPROC	scb_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_start
;
; "Start" the specified session (actual starting will handled by scb_switch).
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, BX -> SCB
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_start,DOS
 	call	get_scb
 	jc	ss9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	stc
	jz	ss9
	or	[bx].SCB_STATUS,SCSTAT_START
ss9:	ret
ENDPROC	scb_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stop
;
; "Stop" the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_stop,DOS
	int 3
	ret
ENDPROC	scb_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unload
;
; Unload the current program from the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_unload,DOS
	int 3
	ret
ENDPROC	scb_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_yield
;
; Asynchronous interface to decide which session should run next.
;
; There are currently two conditions to consider:
;
;	1) A DOS_UTL_YIELD request
;	2) A DOS_UTL_WAIT request
;
; In the first case, we want to return if no other SCB is ready; this
; is important when we're called from an interrupt handler.
;
; In the second case, we never return; at best, we will simply switch to the
; current SCB when its wait condition is satisfied.
;
; Inputs:
;	AX = scb_active when called from DOS_UTL_YIELD, zero otherwise
;
; Modifies:
;	BX, DX
;
DEFPROC	scb_yield,DOS
	sti
	inc	[scb_locked]
	jnz	sy9
	mov	bx,[scb_active]
	test	bx,bx
	jz	sy2
	test	ax,ax			; is this yield due to a WAIT?
	jz	sy1			; yes, so spin until we find an SCB
	mov	bx,ax
	ASSERT	STRUCT,[bx],SCB
sy1:	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	sy3
sy2:	mov	bx,[scb_table].OFF
sy3:	cmp	bx,ax			; have we looped to where we started?
	je	sy9			; yes
	test	[bx].SCB_STATUS,SCSTAT_START
	jz	sy1			; ignore this SCB, hasn't been started
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[bx].SCB_WAITID.OFF
	or	dx,[bx].SCB_WAITID.SEG
	jnz	sy1
	jmp	scb_switch
sy9:	dec	[scb_locked]
	ASSERT	NC
	ret
ENDPROC	scb_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_switch
;
; Switch to the specified session.
;
; Inputs:
;	BX -> SCB
;
DEFPROC	scb_switch,DOS
	cli
	dec	[scb_locked]
	cmp	bx,[scb_active]		; is this SCB already active?
	je	sw9			; yes
	mov	ax,bx
	xchg	bx,[scb_active]		; BX -> previous SCB
	test	bx,bx
	jz	sw8
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[psp_active]
	mov	[bx].SCB_CURPSP,dx
	add	sp,2			; toss 1 near-call return address
	mov	[bx].SCB_STACK.SEG,ss
	mov	[bx].SCB_STACK.OFF,sp
sw8:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	mov	dx,[bx].SCB_CURPSP
	mov	[psp_active],dx
	mov	ss,[bx].SCB_STACK.SEG
	mov	sp,[bx].SCB_STACK.OFF
	ASSERT	NC
	jmp	dos_exit
sw9:	sti
	ret
ENDPROC	scb_switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_wait
;
; Synchronous interface to mark current SCB as waiting for the specified ID.
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	None
;
DEFPROC	scb_wait,DOS
	cli
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	ASSERT	Z,<cmp [bx].SCB_WAITID.SEG,0>
	mov	[bx].SCB_WAITID.OFF,di
	mov	[bx].SCB_WAITID.SEG,dx
	sti
	sub	ax,ax
	jmp	scb_yield
ENDPROC	scb_wait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_endwait
;
; Asynchronous interface to examine all SCBs for the specified ID and clear it.
;
; Inputs:
;	DX:DI == wait ID
;
; Outputs:
;	Carry clear if found, set if not
;
DEFPROC	scb_endwait,DOS
	cli
	mov	bx,[scb_table].OFF
se1:	ASSERT	STRUCT,[bx],SCB
	cmp	[bx].SCB_WAITID.OFF,di
	jne	se2
	cmp	[bx].SCB_WAITID.SEG,dx
	jne	se2
	mov	[bx].SCB_WAITID.OFF,0
	mov	[bx].SCB_WAITID.SEG,0
	jmp	short se9
se2:	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	se1
	stc
se9:	sti
	ret
ENDPROC	scb_endwait

DOS	ends

	end