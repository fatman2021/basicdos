;
; BASIC-DOS Device Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Device driver commands (see DDP_CMD)
;
DDC_INIT	equ	0	; Init
DDC_MEDIACHK	equ	1	; Media Check (block devices only)
DDC_BUILDBPB	equ	2	; Build BPB (block devices only)
DDC_IOCTLIN	equ	3	; IOCTL Input (only called if device has IOCTL)
DDC_READ	equ	4	; Input (Read)
DDC_NDREAD	equ	5	; Non-destructive Read, No Wait (char devices only)
DDC_INSTATUS	equ	6	; Input Status (char devices only)
DDC_INFLUSH	equ	7	; Input Flush (char devices only)
DDC_WRITE	equ	8	; Output (Write)
DDC_WRITEV	equ	9	; Output (Write) with Verify
DDC_OUTSTATUS	equ	10	; Output Status (char devices only)
DDC_OUTFLUSH	equ	11	; Output Flush (char devices only)
DDC_IOCTLOUT	equ	12	; IOCTL Output (only called if device has IOCTL)
DDC_OPEN	equ	13	; Device Open (only called if Open/Close/Removable Media bit set)
DDC_CLOSE	equ	14	; Device Close (only called if Open/Close/Removable Media bit set)
DDC_REMOVABLE	equ	15	; Removable Media (only called if Open/Close/Removable Media bit set and device is block)
DDC_OUTBUSY	equ	16	; Output Until Busy (only called if bit 13 is set on character devices)
DDC_GENIOCTL	equ	19	; Generic IOCTL Request
DDC_GETLOGDEV	equ	23	; Get Logical Device
DDC_SETLOGDEV	equ	24	; Set Logical Device

;
; Device driver packets, starting with the 13-byte packet header (DDP).
;
; Strangely, PC DOS defined only the first 5 bytes (through DDP_STATUS),
; leaving one to wonder what the other 8 bytes were used for.  BASIC-DOS
; puts them to good use, however.  For example, the DDP_CONTEXT field
; provides critical context (ie, session) information to our CONSOLE driver.
;
DDP		struc
DDP_LEN		db	?	; 00h: length of packet
DDP_UNIT	db	?	; 01h: unit # (block devices only)
DDP_CMD		db	?	; 02h: command # (see DDC_*)
DDP_STATUS	dw	?	; 03h: status
DDP_CODE	db	?	; 05h: sub-function code, if IOCTL
DDP_CONTEXT	dw	?	; 06h: device context, if any
DDP_PTR		dd	?	; 08h: optional driver-specific pointer
DDP_SIG		db	?	; 0Ch (holds SIG_DDP in DEBUG builds)
DDP		ends
SIG_DDP		equ	'D'

DDSTAT_ERROR	equ	8000h
DDSTAT_DONE	equ	0100h
DDSTAT_BUSY	equ	0200h
DDSTAT_ERRCODE	equ	00FFh

DDERR_WP	equ	0	; Write protect violation
DDERR_UNKUNIT	equ	1	; Unknown unit
DDERR_NOTREADY	equ	2	; Drive not ready
DDERR_UNKCMD	equ	3	; Unknown command
DDERR_CRC	equ	4	; CRC error
DDERR_BADREQ	equ	5	; Bad drive request structure length
DDERR_SEEK	equ	6	; Seek error
DDERR_UNKMEDIA	equ	7	; Unknown media
DDERR_NOSECTOR	equ	8	; Sector not found
DDERR_NOPAPER	equ	9	; Printer out of paper
DDERR_WRFAULT	equ	10	; Write fault
DDERR_RDFAULT	equ	11	; Read fault
DDERR_GENFAIL	equ	12	; General failure
DDERR_INVDSKCHG	equ	15	; Invalid disk change

;
; Device driver packet for the INIT command
;
DDPI		struc
DDPI_HDR	db	size DDP dup(?)
DDPI_UNITS	db	?	; 0Dh: # of units (ie, drives)
DDPI_END	dd	?	; 0Eh: end of driver
DDPI_BPBPTR	dd	?	; 12h: not used
DDPI_BLKDEV	db	?	; 16h: not used
DDPI		ends

;
; MEDIACHK values returned in the CONTEXT field
;
MC_UNCHANGED	equ	1
MC_UNKNOWN	equ	0
MC_CHANGED	equ	-1

;
; Device driver packet for IOCTL/READ/WRITE/MEDIACHK/BUILDBPB commands
;
DDPRW		struc
DDPRW_HDR	db	size DDP dup(?)
DDPRW_ID	db	?	; 0Dh: media ID (for block devices)
DDPRW_ADDR	dd	?	; 0Eh: transfer address
DDPRW_LBA	dw	?	; 12h: starting sector number
DDPRW_OFFSET	dw	?	; 14h: starting offset within sector
DDPRW_LENGTH	dw	?	; 16h: transfer length (in bytes)
DDPRW_BPB	dd	?	; 18h: pointer to BPB
DDPRW		ends

DDP_MAXSIZE	equ	((size DDPRW + 1) AND 0FFFEh)

;
; Helper macro to define the overall length of a device driver;
; especially helpful when the driver includes headers for multiple devices
; that share a common INIT handler.
;
DEFLEN	macro	symbol,vars,add
symbol	=	0
	IRP	var,<vars>
symbol 	=	symbol + (((var&&_end - &&var) + 15) AND 0FFF0h)
	ENDM
	IFNB	<add>
symbol	=	symbol + add
	ENDIF
	endm
