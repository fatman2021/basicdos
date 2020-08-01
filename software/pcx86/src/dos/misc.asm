;
; BASIC-DOS Miscellaneous Services
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	dos.inc

DOS	segment word public 'CODE'

	EXTERNS	<scb_active>,word
	EXTERNS	<tty_read,write_string,dos_restart>,near
	EXTSTR	<STR_CTRLC>
	IF REG_CHECK
	EXTERNS	<dos_check>,near
	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setvec (REG_AH = 25h)
;
; Inputs:
;	REG_AL = vector #
;	REG_DS:REG_DX = address for vector
;
; Outputs:
;	None
;
; Modifies:
;	AX, DI, ES
;
; Notes:
; 	Too bad this function wasn't defined to also return the original vector.
;
DEFPROC	msc_setvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	msv1
	sub	di,di
	mov	es,di
	ASSUME	ES:BIOS
msv1:	xchg	di,ax			; ES:DI -> vector to write
	cli
	mov	ax,[bp].REG_DX
	stosw
	mov	ax,[bp].REG_DS
	stosw
	sti
	clc
	ret
ENDPROC	msc_setvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getver (REG_AH = 30h)
;
; Inputs:
;	None
;
; Outputs:
;	REG_AL = major version #
;	REG_AH = minor version #
;	REG_BH = OEM serial #
;	REG_BL:REG_CX = 24-bit serial number
;
; Modifies:
;	None
;
DEFPROC	msc_getver,DOS
	mov	[bp].REG_AX,0002h	; hard-coded to simulate v2.00
	mov	[bp].REG_BX,0
	mov	[bp].REG_CX,0
	clc
	ret
ENDPROC	msc_getver

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_setctrlc (REG_AH = 33h)
;
; Inputs:
;	REG_AL = 0 to get current CTRLC state in REG_DL
;	REG_AL = 1 to set current CTRLC state in REG_DL
;
; Outputs:
;	REG_DL = current state if REG_AL = 1, or 0FFh if REG_AL neither 0 nor 1
;
DEFPROC	msc_setctrlc,DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	sub	al,1
	jae	msc1
	mov	al,[bx].SCB_CTRLC_ALL]	; AL was 0
	mov	[bp].REG_DL,al		; so return CTRLC_ALL in REG_DL
	clc
	jmp	short msc9
msc1:	jnz	msc2			; jump if AL was neither 0 nor 1
	mov	al,[bp].REG_DL		; AL was 1
	sub	al,1			; so convert REG_DL to 0 or 1
	sbb	al,al
	inc	ax
	mov	[bx].SCB_CTRLC_ALL,al
	clc
	jmp	short msc9
msc2:	mov	al,0FFh
	stc
msc9:	ret
ENDPROC	msc_setctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_sigctrlc
;
; Inputs:
;	None
;
; Outputs:
;	None
;
; Modifies:
;	Any; this function does not return directly to the caller
;
DEFPROC	msc_sigctrlc,DOSFAR
	ASSUME	DS:NOTHING, ES:NOTHING
	push	cs
	pop	ds
	ASSUME	DS:DOS
	mov	bx,[scb_active]
	ASSERT	NZ,<test bx,bx>		; TODO: verify there's an SCB
	jmp	short msg0

	DEFLBL	msc_sigctrlc_read,near
	ASSERT	STRUCT,[bx],SCB
	cmp	[bx].SCB_CTRLC_ACT,0
	je	msg1
	call	tty_read		; remove CTRLC from the input buffer
msg0:	mov	[bx].SCB_CTRLC_ACT,0
;
; Make sure that whatever function we're interrupting has not violated
; our BP convention; some functions prefer to use BP as an extra register,
; and that's OK as long as 1) they're not an interruptable function and 2)
; they restore BP when they're done.
;
msg1:	IF REG_CHECK
	ASSERT	Z,<cmp word ptr [bp-2],offset dos_check>
	ENDIF

	mov	cx,STR_CTRLC_LEN
	mov	si,offset STR_CTRLC
	call	write_string
;
; Use the REG_WS workspace on the stack to create two "call frames",
; allowing us to RETF to the CTRLC handler, and allowing the CTRLC handler
; to IRET back to us.
;
	mov	ax,[bp].REG_FL		; FL_CARRY is clear in REG_FL
	mov	[bp].REG_WS.RET_FL,ax
	mov	[bp].REG_WS.RET_CS,cs
	mov	[bp].REG_WS.RET_IP,offset dos_restart
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
;
; At this point, we're effectively issuing an INT 23h (INT_DOSCTRLC), but it
; has to be simulated, because we're using the SCB CTRLC address rather than the
; IVT CTRLC address; they should be the same thing, as long as everyone uses
; DOS_MSC_SETVEC to set vector addresses.
;
; As explained in the SCB definition, we do this only because we'd rather not
; swap IVT vectors on every SCB switch, hence the use of "shadow" vectors inside
; the SCB.
;
	mov	ax,[bx].SCB_CTRLC.SEG
	mov	[bp].REG_WS.JMP_CS,ax
	mov	ax,[bx].SCB_CTRLC.OFF
	mov	[bp].REG_WS.JMP_IP,ax

	mov	sp,bp
	pop	bp
	pop	di
	pop	es
	pop	si
	pop	ds
	ASSUME	DS:NOTHING
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDPROC	msc_sigctrlc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getvec (REG_AH = 35h)
;
; Inputs:
;	REG_AL = vector #
;
; Outputs:
;	REG_ES:REG_BX = address from vector
;
; Modifies:
;	AX, SI, DS
;
DEFPROC	msc_getvec,DOS
	call	get_vecoff		; AX = vector offset
	jnc	mgv1
	sub	si,si
	mov	ds,si
	ASSUME	DS:BIOS
mgv1:	xchg	si,ax			; DS:SI -> vector to read
	cli
	lodsw
	mov	[bp].REG_BX,ax
	lodsw
	mov	[bp].REG_ES,ax
	sti
	clc
	ret
ENDPROC	msc_getvec

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; msc_getswc (REG_AH = 37h)
;
; Get/set the current switch character ("switchar").
;
; Inputs:
;	If REG_AL = 0, returns current switch character in REG_DL
;	If REG_AL = 1, set the current switch character from REG_DL
;	Otherwise, set REG_AL to 0FFh to indicate unsupported subfunction
;
; Outputs:
;	See above
;
; Modifies:
;	AX
;
DEFPROC	msc_getswc,DOS
	mov	bx,[scb_active]
	ASSERT	STRUCT,[bx],SCB
	test	al,al
	jnz	gsw1
	mov	al,[bx].SCB_SWITCHAR
	mov	[bp].REG_DL,al		; DL = "switchar"
	jmp	short gsw9
gsw1:	dec	al
	jnz	gsw2
	mov	[bx].SCB_SWITCHAR,dl	; update "switchar"
	jmp	short gsw9
gsw2:	mov	byte ptr [bp].REG_AL,0FFh; (unsupported subfunction)
gsw9:	ret
ENDPROC	msc_getswc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; get_vecoff
;
; Inputs:
;	AL = vector #
;
; Outputs:
;	AX = vector offset (carry set if IVT, clear if SCB)
;
; Modifies:
;	AX
;
DEFPROC	get_vecoff,DOS
	mov	ah,0			; AX = vector #
	add	ax,ax
	add	ax,ax			; AX = vector # * 4
	cmp	ax,INT_DOSEXRET * 4
	jb	gv9			; use IVT (carry set)
	cmp	ax,INT_DOSERROR * 4 + 4
	cmc
	jb	gv9			; use IVT (carry set)
	sub	ax,(INT_DOSEXRET * 4) - offset SCB_EXRET
	add	ax,[scb_active]		; AX = vector offset in current SCB
	ASSERT	NC
gv9:	ret
ENDPROC	get_vecoff

DOS	ends

	end
