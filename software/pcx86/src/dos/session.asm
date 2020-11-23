;
; BASIC-DOS Session Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
	include	bios.inc
	include	dos.inc

DOS	segment word public 'CODE'

;
; Global SCB status variables:
;
; scb_locked is -1 if the current SCB is unlocked, >= 0 if it's locked;
; locked means that SCB switching is disabled.
;
; scb_stoked normally points to scb_return (ie, a RET) but if a yield
; operation notices that another SCB is ready to run BUT the current SCB is
; locked, then scb_stoked will be set to scb_stoke instead, triggering a yield
; on the next unlock.
;
; That is, thus far, the extent of our extremely simple scheduler.
;
	EXTBYTE	<scb_locked,def_switchar>
	EXTWORD	<scb_active,scb_stoked>
	EXTLONG	<scb_table>
	EXTNEAR	<dos_exit,load_command,psp_term_exitcode>
	EXTNEAR	<sfh_add_ref,sfh_context,sfh_close>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_getnum
;
; Inputs:
;	None
;
; Outputs:
;	AL = SCB # of scb_active
;
; Modifies:
;	AX
;
DEFPROC	scb_getnum,DOS
	ASSUME	ES:NOTHING
	push	bx
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	mov	al,[bx].SCB_NUM
gsn9:	pop	bx
	ret
ENDPROC	scb_getnum

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_load
;
; Load a program into an available session.
;
; Inputs:
;	REG_ES:REG_BX -> SPB (Session Parameter Block)
;
; Outputs:
;	Carry clear if successful:
;		REG_CL = session (SCB) #
;		REG_AX = program size (if SPB_ENVSEG is -1)
;		REG_ES:REG_BX -> program data (if SPB_ENVSEG is -1)
;	Carry set if error, AX = error code (eg, no SCB, no program, etc)
;
; Modifies:
;	AX, BX, CX, DX, SI, DI, DS, ES
;
DEFPROC	scb_load,DOS
	mov	cl,-1
	call	scb_lock		; lock a free SCB
	jc	sl8
	push	ax			; save previous SCB
	mov	di,[bp].REG_BX
	mov	es,[bp].REG_ES		; ES:DI -> SPB
	ASSUME	ES:NOTHING
	call	init_scb		; initialize the SCB
	push	bx			; save SCB
	mov	bx,es:[di].SPB_ENVSEG
	push	bx			; BX = ENVSEG, if any
	lds	si,es:[di].SPB_CMDLINE
	ASSUME	DS:NOTHING
	call	load_command		; DS:SI -> command line
	push	cs
	pop	ds
	ASSUME	DS:DOS
	pop	cx			; CX = ENVSEG
	pop	bx			; BX -> current SCB again
	jc	sl7			; exit on load error
;
; If successful, load_command returns the initial program stack in DX:AX.
;
; In addition, it records cache information in the TMP registers, which most
; most callers can/will ignore, but which sysinit uses to speed up successive
; LOAD requests.
;
	mov	[bx].SCB_STACK.OFF,ax	; DX:AX == initial stack
	mov	[bx].SCB_STACK.SEG,dx
	or	[bx].SCB_STATUS,SCSTAT_LOAD
	mov	al,[bx].SCB_NUM
	mov	[bp].REG_CL,al		; REG_CL = session (SCB) #
	inc	cx			; was ENVSEG -1?
	jnz	sl7			; no, leave REG_AX, REG_ES:REG_BX alone
	mov	ax,[bp].TMP_CX
	mov	[bp].REG_AX,ax		; REG_AX = program size
	mov	ax,[bp].TMP_BX
	mov	[bp].REG_BX,ax
	mov	ax,[bp].TMP_ES
	mov	[bp].REG_ES,ax		; REG_ES:REG_BX -> program data

sl7:	pop	cx			; recover previous SCB
	call	scb_unlock		; unlock
sl8:	jnc	sl9
	mov	[bp].REG_AX,ax		; return error code to caller
sl9:	ret
ENDPROC	scb_load

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	inc	[scb_locked]
	call	get_scb
	jc	sk9
	mov	ax,bx			; AX = current SCB
	xchg	bx,[scb_active]		; BX -> previous SCB, if any
	test	bx,bx
	jz	sk8
	ASSERT	STRUCT,[bx],SCB
sk8:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
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
	ret
sk9:	dec	[scb_locked]
	ret
ENDPROC	scb_lock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unlock
;
; Restore the previous SCB and lock state.
;
; Inputs:
;	BX -> current SCB
;	CX -> previous SCB
;
; Modifies:
;	BX
;
; Preserves:
;	Flags
;
DEFPROC	scb_unlock,DOS
	ASSUME	ES:NOTHING
	pushf
	ASSERT	STRUCT,[bx],SCB
	mov	[scb_active],cx
	jcxz	su9
	mov	bx,cx			; BX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
su9:	dec	[scb_locked]
	popf
	ret
ENDPROC	scb_unlock

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_release
;
; Handler invoked via UNLOCK_SCB to unlock the SCB and check for a deferred
; yield request if we're completely unlocked.
;
; Inputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_release,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	dec	[scb_locked]
	jge	scb_return
	ASSERT	Z,<cmp [scb_locked],-1>
	jmp	[scb_stoked]
ENDPROC	scb_release

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stoke
;
; Handler invoked via UNLOCK_SCB to perform a deferred yield request.
;
; Inputs:
;	None
;
; Modifies:
;	None
;
DEFPROC	scb_stoke,DOS
	ASSUME	DS:NOTHING, ES:NOTHING
	mov	[scb_stoked],offset scb_return
	push	ax
	DOSUTIL	YIELD
	pop	ax
	DEFLBL	scb_return,near
	ret
ENDPROC	scb_stoke

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_start
;
; Start the specified session (actual starting will handled by scb_switch).
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, BX -> SCB
;	Carry set on error (eg, invalid SCB #), AX = error code
;
DEFPROC	scb_start,DOS
 	call	get_scb
 	jc	ss9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	ss8
	or	[bx].SCB_STATUS,SCSTAT_START
	ret
ss8:	mov	ax,ERR_BADSESSION
	stc
ss9:	ret
ENDPROC	scb_start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_stop
;
; TODO: Stop (ie, suspend) the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success
;	Carry set on error (eg, invalid SCB #)
;
DEFPROC	scb_stop,DOS
	DBGBRK
	ret
ENDPROC	scb_stop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_unload
;
; Unload the current program from the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success (AX = 0)
;	Carry set on error (eg, invalid SCB #), AX = error code
;
; Modifies:
;	AX, BX, CX, DX, SI
;
DEFPROC	scb_unload,DOS
	ASSUMES	<DS,DOS>,<ES,NOTHING>
	call	get_scb
 	jc	sud9
	mov	cx,5			; close this session's system handles
	push	bx
	lea	si,[bx].SCB_SFHIN
sud1:	mov	bl,SFH_NONE
	xchg	bl,[si]
	call	sfh_close
	inc	si
	loop	sud1
	pop	bx
	xchg	ax,cx			; make sure AX is zero
	and	[bx].SCB_STATUS,NOT (SCSTAT_LOAD OR SCSTAT_START)
;
; In case another session was waiting for this session to unload, call endwait.
;
	mov	di,bx
	mov	dx,ds			; DX:DI = SCB address (the wait ID)
	call	scb_endwait
	clc
sud9:	ret
ENDPROC	scb_unload

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_end
;
; TODO: End the current program in the specified session.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success (AX = 0)
;	Carry set on error (eg, invalid SCB #)
;
; Modifies:
;
DEFPROC	scb_end,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
sc9:	ret
ENDPROC	scb_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_waitend
;
; Wait for all programs in the specified session to end.
;
; Inputs:
;	CL = SCB #
;
; Outputs:
;	Carry clear on success, set on error
;
; Modifies:
;
DEFPROC	scb_waitend,DOS
	ASSUMES	<DS,DOS>,<ES,DOS>
	call	get_scb
	jc	sc9
	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	sc9
;
; Turn this call into a standard scb_wait call, where the wait ID in DX:DI
; is the target SCB address (instead of the usual driver packet address).
;
	mov	di,bx
	mov	dx,ds
	jmp	scb_wait
ENDPROC	scb_waitend

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_yield
;
; Asynchronous interface to decide which session should run next.
;
; There are currently two conditions to consider:
;
;	1) A DOSUTIL YIELD request
;	2) A DOSUTIL WAIT request
;
; In the first case, we want to return if no other SCB is ready; this
; is important when we're called from an interrupt handler.
;
; In the second case, we never return; at best, we will simply switch to the
; current SCB when its wait condition is satisfied.
;
; Inputs:
;	AX = scb_active when called from DOSUTIL YIELD, zero otherwise
;
; Modifies:
;	BX, DX
;
DEFPROC	scb_yield,DOS
	sti
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
	inc	[scb_locked]
	jz	scb_switch		; we were not already locked, so switch
	test	ax,ax			; yield?
	jz	sy8			; no
	mov	[scb_stoked],offset scb_stoke
sy8:	dec	[scb_locked]
sy9:	ASSERT	NC
	ret
ENDPROC	scb_yield

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; scb_switch
;
; Switch to the specified session.  SCB locking is used to prevent switches
; whenever global data structures are being modified (eg, disk buffers), but
; all per-session data should be stored in the SCB, so that no global state
; needs to be copied in or out.
;
; The kinds of apps we ultimately want to support in BASIC-DOS sessions will
; determine whether we need to adopt additional measures, such as "swapping"
; global data (eg, BIOS data) in or out of the SCB.
;
; Our CONSOLE driver is a good example.  For now, it performs some minor BIOS
; updates on the relatively infrequent "focus" switches that can occur between
; contexts on different video adapters, but if that proves to be ineffective,
; we may need to perform session-switch notifications to the drivers, so that
; they can do their own "state swapping" every time we're about to switch to a
; new SCB.
;
; The incentives for avoiding that are high, because these switches will become
; very expensive, and IBM PCs are not all that fast.
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
	jz	sw6
	ASSERT	STRUCT,[bx],SCB
	add	sp,2			; toss 1 near-call return address
	mov	[bx].SCB_STACK.SEG,ss
	mov	[bx].SCB_STACK.OFF,sp
sw6:	xchg	bx,ax			; BX -> current SCB, AX -> previous SCB
	ASSERT	STRUCT,[bx],SCB
	mov	ss,[bx].SCB_STACK.SEG
	mov	sp,[bx].SCB_STACK.OFF
;
; TODO: Finish support for the RESET bit.
;
	test	[bx].SCB_STATUS,SCSTAT_RESET
	jz	sw8
sw7:	sti
	and	[bx].SCB_STATUS,NOT SCSTAT_RESET
	PRINTF	<"Reset request detected",13,10>
	mov	ax,(EXTYPE_RESET SHL 8) OR 0FFh
	call	psp_term_exitcode	; attempt reset

sw8:	ASSERT	NC
	jmp	dos_exit		; we'll let dos_exit turn interrupts on
sw9:	sti
	ret
ENDPROC	scb_switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
	cmc
	jnc	se1
se9:	sti
	ret
ENDPROC	scb_endwait

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_scb
;
; Returns the specified SCB.
;
; Inputs:
;	CL = SCB # (-1 for first free SCB)
;
; Outputs:
;	On success, carry clear, BX -> SCB
;	On failure, carry set, AX = error code
;
; Modifies:
;	AX, BX
;
DEFPROC	get_scb,DOS
	cmp	cl,-1
	je	get_free_scb
	mov	al,size SCB
	mul	cl
	add	ax,[scb_table].OFF
	cmp	ax,[scb_table].SEG
	jae	gs8
	xchg	bx,ax
	test	[bx].SCB_STATUS,SCSTAT_INIT
	jnz	gs9
gs8:	mov	ax,ERR_BADSESSION
	stc
gs9:	ret
ENDPROC	get_scb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_free_scb
;
; Returns the first free (unloaded) SCB.
;
; Inputs:
;	None
;
; Outputs:
;	On success, carry clear, BX -> SCB
;	On failure, carry set (SCB unavailable), AX = ERR_NOSESSION
;
; Modifies:
;	BX
;
DEFPROC	get_free_scb,DOS
	mov	bx,[scb_table].OFF
fs1:	test	[bx].SCB_STATUS,SCSTAT_LOAD
	jz	fs9
	add	bx,size SCB
	cmp	bx,[scb_table].SEG
	jb	fs1
	mov	ax,ERR_NOSESSION
	stc
fs9:	ret
ENDPROC	get_free_scb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; init_scb
;
; Initialize the SCB in preparation for program loading.  Now that
; COMMAND.COM is using the LOAD interface to start background processes,
; more initialization is required (eg, copying the current SCB's settings,
; such as SCB_CURDRV).
;
; Inputs:
;	AX = previous SCB
;	DS:BX -> SCB (Session Control Block)
;	ES:DI -> SPB (Session Parameter Block)
;
; Modifies:
;	AX, CX, DX, SI
;
DEFPROC	init_scb,DOS
	push	di
	ASSUME	ES:NOTHING
	ASSERT	STRUCT,[bx],SCB
;
; Before we overlay the SCB handles with those from the SPB, we start by
; copying the current SCB's handles (if any).  Ditto for the SCB's parent
; (if any), switch character, current drive, etc.
;
	mov	[bx].SCB_PARENT,ax	; TODO: What shall we do with this?
	xchg	si,ax			; DS:SI -> previous SCB
	mov	al,0			; AL = CURDRV
	mov	ah,[def_switchar]	; AH = SWITCHAR
	test	si,si
	jz	si0
	lodsw				; DS:SI -> SFHIN of previous SCB
	lodsw				; load SFHIN, SFHOUT
	mov	word ptr [bx].SCB_SFHIN,ax
	lodsw				; load SFHERR, SFHAUX
	mov	word ptr [bx].SCB_SFHERR,ax
	lodsw				; load SFHPRN
	mov	[bx].SCB_SFHPRN,al
	lodsw				; load CURDRV, SWITCHAR
si0:	mov	word ptr [bx].SCB_CURDRV,ax
;
; Now copy any valid SFHs from the SPB into the SCB.
;
	mov	cx,5
	mov	dx,es:[di].SPB_ENVSEG
	lea	si,[di].SPB_SFHIN	; ES:SI -> 1st SFH in the SPB
	lea	di,[bx].SCB_SFHIN	; DS:DI -> 1st SFH in the SCB
si1:	lods	byte ptr es:[si]
	cmp	al,SFH_NONE		; was an SFH supplied?
	je	si2			; no
	mov	[di],al			; update the SCB
si2:	cmp	dx,-1			; is SPB_ENVSEG -1 (from sysinit)?
	je	si3			; yes, so leave SFH alone
	mov	al,[di]			; AL = SFH (no harm if SFH_NONE)
	mov	ah,1			; add 1 session ref
	call	sfh_add_ref		; (in addition to any program refs)
si3:	inc	di
	loop	si1
;
; Now that we're done fiddling with SFHs, get the CONSOLE context from SFHOUT.
;
	mov	al,[bx].SCB_SFHOUT
	call	sfh_context
	mov	[bx].SCB_CONTEXT,ax

	or	[bx].SCB_STATUS,SCSTAT_INIT
	pop	di
	ret
ENDPROC	init_scb

DOS	ends

	end
