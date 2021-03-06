;
; BASIC-DOS ROM BIOS Interface and Data Area Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Standard PC BIOS vectors (first few are really standard 8086 vectors)
;
; Page numbers are from the first IBM 5150 Technical Reference Manual (1981)
;
	IFDEF	BIOSEQU
INT_PRTSC	equ	05h	; PRINT_SCREEN (p. A-79)
INT_HW_TMR	equ	08h	;
INT_HW_KBD	equ	09h	;
INT_HW_COM2	equ	0Bh	; default vector for COM2
INT_HW_COM1	equ	0Ch	; default vector for COM1
INT_VIDEO	equ	10h	; VIDEO_IO (p. A-43)
INT_EQUIP	equ	11h	; EQUIPMENT_DETERMINATION (p. A-67)
INT_MEMORY	equ	12h	; MEMORY_SIZE_DETERMINE (p. A-67)
INT_FDC		equ	13h	; DISKETTE_IO (p. A-32)
INT_COM		equ	14h	; RS232_IO (p. A-20)
INT_CASSETTE	equ	15h	; CASSETTE_IO (p. A-68)
INT_KBD		equ	16h	; KEYBOARD_IO (p. A-23)
INT_LPT		equ	17h	; PRINTER_IO (p. A-42)
INT_BASIC	equ	18h	;
INT_REBOOT	equ	19h	; BOOT_STRAP (p. A-20)
INT_TIME	equ	1Ah	; TIME_OF_DAY (p. A-77)
INT_BREAK	equ	1Bh	; CTRL_BREAK
INT_TICK	equ	1Ch	; TIMER TICK
INT_VPT		equ	1Dh	; VIDEO PARAMETER TABLE
INT_DPT		equ	1Eh	; DISKETTE PARAMETER TABLE
INT_VGCDATA	equ	1Fh	; VIDEO GRAPHICS CHARACTER DATA

;
; INT_VIDEO functions
;
VIDEO_SETMODE	equ	00h	; AL=mode
VIDEO_SETCTYPE	equ	01h	; CH=cursor top, CL=cursor bottom
VIDEO_SCROLL	equ	06h	; AL=# lines, BH=fill attribute, CX/DX=coords
VIDEO_TTYOUT	equ	0Eh	; AL=char, BH=display page

MODE_CO80	equ	03h
MODE_MONO	equ	07h

;
; INT_FDC (Floppy Drive Controller) and INT_HDC (Hard Drive Controller)
; functions
;
FDC_READ	equ	02h	;
FDC_WRITE	equ	03h	;
HDC_GETPARMS	equ	08h	; DL=80h; DL:=# drives (if carry clear)

FDCERR_BADCMD	equ	01h	; bad (BIOS) command
FDCERR_BADMARK	equ	02h	; bad address mark
FDCERR_WP	equ	03h	; write-protect error
FDCERR_NOSECTOR	equ	04h	; sector not found
FDCERR_DMAOVR	equ	08h	; DMA overrun error
FDCERR_DMA64K	equ	09h	; DMA (64K) boundary error
FDCERR_CRC	equ	10h	; CRC error
FDCERR_CTRL	equ	20h	; controller failure
FDCERR_SEEK	equ	40h	; seek failure
FDCERR_NOTREADY	equ	80h	; aka timeout

;
; INT_KBD functions
;
KBD_READ	equ	00h	; returns char code in AL, scan code in AH
KBD_CHECK	equ	01h	; returns ZF set if no key

;
; BIOS-generated keyboard char codes and scan codes that we care about.
;
SCAN_TAB	equ	0Fh
SCAN_F1		equ	3Bh
SCAN_F2		equ	3Ch
SCAN_F3		equ	3Dh
SCAN_F4		equ	3Eh
SCAN_F5		equ	3Fh
SCAN_F6		equ	40h
SCAN_F7		equ	41h
SCAN_F8		equ	42h
SCAN_F9		equ	43h
SCAN_F10	equ	44h
SCAN_HOME	equ	47h	; home
SCAN_UP		equ	48h	; up-arrow
SCAN_PGUP	equ	49h	; page-up
SCAN_LEFT	equ	4Bh	; left-arrow
SCAN_RIGHT	equ	4Dh	; right-arrow
SCAN_END	equ	4Fh	; end
SCAN_DOWN	equ	50h	; down-arrow
SCAN_PGDN	equ	51h	; page-down
SCAN_INS	equ	52h	; insert
SCAN_DEL	equ	53h	; delete
SCAN_CTRL_LEFT	equ	73h	; ctrl-left-arrow
SCAN_CTRL_RIGHT	equ	74h	; ctrl-right-arrow
SCAN_CTRL_END	equ	75h	; ctrl-end
SCAN_CTRL_PGDN	equ	76h	; ctrl-page-down
SCAN_CTRL_HOME	equ	77h	; ctrl-home
SCAN_CTRL_PGUP	equ	84h	; ctrl-page-up

;
; INT_TIME functions
;
TIME_GETTICKS	equ	00h	; returns CX:DX, and AL != 0 if wrapped
	ENDIF	; BIOSEQU

;
; Diskette Parameter Table (11 bytes pointed by INT_DSKPARMS (1Eh))
;
; Early utilities (like SPEEDUP; see https://www.pcjs.org/blog/2017/07/21/)
; changed:
;
;	DPT_SPECIFY1:	from CFh to DFh (step rate from 8ms to 6ms)
;	DPT_HEADSETTLE:	from 19h to 00h (head settle from 25ms to 0ms)
;
DPT		struc
DP_SPECIFY1	db	?	; CFh: SRT=C, HD UNLOAD=0F (1ST SPECIFY BYTE)
DP_SPECIFY2	db	?	; 02h: HD LOAD=1, MODE=DMA (2ND SPECIFY BYTE)
DP_MOTOROFF	db	?	; 25h: WAIT AFTER OPN TIL MOTOR OFF
DP_BPS		db	?	; 02h: 512 BYTES/SECTOR
DP_SPT		db	?	; 08h: EOT (LAST SECTOR ON TRACK)
DP_GAP		db	?	; 2Ah: GAP LENGTH
DP_DTL		db	?	; FFh: DTL
DP_GAP3		db	?	; 50h: GAP LENGTH FOR FORMAT
DP_FILL		db	?	; F6h: FILL BYTE FOR FORMAT
DP_HEADSETTLE	db	?	; 19h: HEAD SETTLE TIME (MS)
DP_MOTORON	db	?	; 04h: MOTOR-ON START TIME (1/8 SECS)
DPT		ends

;
; This internal BUFHDR structure precedes each allocated disk buffer.
;
BUFHDR		struc		; 16-byte buffer header
BUF_PREV	dw	?	; 00h: prev buffer header paragraph
BUF_NEXT	dw	?	; 02h: next buffer header paragraph
BUF_SIZE	dw	?	; 04h: size of buffer (in bytes)
BUF_DRIVE	db	?	; 06h: drive number of buffer data
BUF_SIG		db	?	; 07h: (holds SIG_BUF in DEBUG builds)
		dw	?	; 08h: padding
BUF_LBA		dw	?	; 0Ah: LBA of buffer data
BUF_TIMESTAMP	dd	?	; 0Ch: timestamp of buffer data
BUFHDR		ends
SIG_BUF		equ	'B'

;
; ROM BIOS DATA AREA (RBDA)
;
; We'll assume that all 256 bytes from 40:00h to 40:FFh are used or reserved.
;
; I've also made the strategic decision to NOT use segment value 40h to access
; ROM BIOS data, as 00h is more useful.
;
BIOS		segment at 0
IVT		dd    256 DUP(?);
RS232_BASE	dw	4 DUP(?); 400h: ADDRESSES OF RS232 ADAPTERS
PRINTER_BASE	dw	4 DUP(?); 408h: ADDRESSES OF PRINTERS
EQUIP_FLAG	dw	?	; 410h: INSTALLED HARDWARE
;
; EQUIP_FLAG bits
;
	IFDEF	BIOSEQU
EQ_NUM_PRINT	equ	0C000h	; NUMBER OF PRINTERS ATTACHED
EQ_GAME_CTRL	equ	1000h	; GAME I/O ATTACHED
EQ_NUM_RS232	equ	0E00h	; NUMBER OF RS232 CARDS ATTACHED
EQ_NUM_DRIVES	equ	00C0h	; NUMBER OF DISKETTE DRIVES
				; (00=1,01=2,10=3,11=4) ONLY IF IPL_DRIVE SET
EQ_VIDEO_MODE	equ	0030h	; INITIAL VIDEO MODE (see below)
EQ_VIDEO_CO40	equ	0010h	;
EQ_VIDEO_CO80	equ	0020h	;
EQ_VIDEO_MONO	equ	0030h	;
EQ_RAM_SIZE	equ	00C0h	; PLANAR RAM SIZE (00=16K,01=32K,10=48K,11=64K)
EQ_IPL_DRIVE	equ	0001h	; IPL (Initial Program Load) FROM DISKETTE
				; (ie, diskette drives exist)
	ENDIF	; BIOSEQU

MFG_TEST	db	?	; 412h: INITIALIZATION FLAG
MEMORY_SIZE	dw	?	; 413h: MEMORY SIZE IN K BYTES
IO_RAM_SIZE	dw	?	; 415h: MEMORY IN I/O CHANNEL
KB_FLAG		db	?	; 417h: FIRST BYTE OF KEYBOARD STATUS
;
; KB_FLAG bits
;
	IFDEF	BIOSEQU
INS_STATE	equ	80h	; INSERT STATE IS ACTIVE
CAPS_STATE	equ	40h	; CAPS LOCK STATE HAS BEEN TOGGLED
NUM_STATE	equ	20h	; NUM LOCK STATE HAS BEEN TOGGLED
SCROLL_STATE	equ	10h	; SCROLL LOCK STATE HAS BEEN TOGGLED
ALT_SHIFT	equ	08h	; ALTERNATE SHIFT KEY DEPRESSED
CTL_SHIFT	equ	04h	; CONTROL SHIFT KEY DEPRESSED
LEFT_SHIFT	equ	02h	; LEFT SHIFT KEY DEPRESSED
RIGHT_SHIFT	equ	01h	; RIGHT SHIFT KEY DEPRESSED
	ENDIF	; BIOSEQU

KB_FLAG_1	db	?	; 418h: SECOND BYTE OF KEYBOARD STATUS
ALT_INPUT	db	?	; 419h: STORAGE FOR ALTERNATE KEYPAD ENTRY
BUFFER_HEAD	dw	?	; 41Ah: POINTER TO HEAD OF KEYBOARD BUFFER
BUFFER_TAIL	dw	?	; 41Ch: POINTER TO TAIL OF KEYBOARD BUFFER
KB_BUFFER	dw     16 DUP(?); 41Eh: ROOM FOR 15 ENTRIES

SEEK_STATUS	db	?	; 43Eh: DRIVE RECALIBRATION STATUS
                        	;	BIT 3-0 = DRIVE 3-0 NEEDS RECAL BEFORE
                        	;	NEXT SEEK IF BIT IS = 0
INT_FLAG	equ	80h	;	INTERRUPT OCCURRENCE FLAG
MOTOR_STATUS	db	?	; 43Fh: MOTOR STATUS
				;	BIT 3-0 = DRIVE 3-0 IS CURRENTLY RUNNING
				;	BIT 7 = CURRENT OPERATION IS A WRITE, REQUIRES DELAY
MOTOR_COUNT	db	?	; 440h: TIME OUT COUNTER FOR DRIVE TURN OFF
                        	;	37 = TWO SECONDS OF COUNTS FOR MOTOR TURN OFF
DISKETTE_STATUS	db	?	; 441h: SINGLE BYTE OF RETURN CODE INFO FOR STATUS
;
; DISKETTE_STATUS bits
;
	IFDEF	BIOSEQU
TIME_OUT	equ	80h	; ATTACHMENT FAILED TO RESPOND
BAD_SEEK	equ	40h	; SEEK OPERATION FAILED
BAD_NEC		equ	20h	; NEC CONTROLLER HAS FAILED
BAD_CRC		equ	10h	; BAD CRC ON DISKETTE READ
DMA_BOUNDARY	equ	09h	; ATTEMPT TO DMA ACROSS 64K BOUNDARY
BAD_DMA		equ	08h	; DMA OVERRUN ON OPERATION
RECORD_NOT_FND	equ	04h	; REQUESTED SECTOR NOT FOUND
WRITE_PROTECT	equ	03h	; WRITE ATTEMPTED ON WRITE PROT DISK
BAD_ADDR_MARK	equ	02h	; ADDRESS MARK NOT FOUND
BAD_CMD		equ	01h	; BAD COMMAND PASSED TO DISKETTE I/O
	ENDIF	; BIOSEQU

NEC_STATUS	db	7 DUP(?); 442h: STATUS BYTES FROM NEC
;
; VIDEO DISPLAY DATA AREA
;
CRT_MODE	db	?	; 449h: CURRENT CRT MODE
CRT_COLS	dw	?	; 44Ah: NUMBER OF COLUMNS ON SCREEN
CRT_LEN		dw	?	; 44Ch: LENGTH OF REGEN IN BYTES
CRT_START	dw	?	; 44Eh: STARTING ADDRESS IN REGEN BUFFER
CURSOR_POSN	dw	8 DUP(?); 450h: CURSOR FOR EACH OF UP TO 8 PAGES
CURSOR_MODE	dw	?	; 460h: CURRENT CURSOR MODE SETTING
ACTIVE_PAGE	db	?	; 462h: CURRENT PAGE BEING DISPLAYED
ADDR_6845	dw	?	; 463h: BASE ADDRESS FOR ACTIVE DISPLAY CARD
CRT_MODE_SET	db	?	; 465h: CURRENT SETTING OF THE 3X8 REGISTER
CRT_PALLETTE	db	?	; 466h: CURRENT PALLETTE SETTING COLOR CARD
;
; CASSETTE DATA AREA
;
EDGE_CNT	dw	?	; 467h: PC: TIME COUNT AT DATA EDGE (word)
CRC_REG		dw	?	; 469h: PC: CRC REGISTER (word)
LAST_VAL	db	?	; 46Bh: PC: LAST INPUT VALUE (byte)
;
; TIMER DATA AREA
;
TIMER_LOW	dw	?	; 46Ch: LOW WORD OF TIMER COUNT
TIMER_HIGH	dw	?	; 46Eh: HIGH WORD OF TIMER COUNT
TIMER_OFL	db	?	; 470h: TIMER HAS ROLLED OVER SINCE LAST READ
;
; SYSTEM DATA AREA
;
BIOS_BREAK	db	?	; 471h: BIT 7 = 1 IF BREAK KEY HAS BEEN DEPRESSED
RESET_FLAG	dw	?	; 472h: SET TO 0x1234 IF KEYBOARD RESET UNDERWAY
;
; RESET_FLAG marks the traditional end of the RBDA, as defined by the IBM PC.
; We'll add future definitions below, mostly out of "historical" interest.
;
		db	13h DUP(?)
EGA_MISC_INFO	db	?	; 487h: bit 0=cursor emulation, etc.
EGA_MISC_INFO2	db	?	; 488h: EGA DIP switches and feature bits
		db    	77h DUP(?)
;
; Define BASIC-DOS low memory usage, starting at offset 500h.
;
; Unfortunately, there's a byte at 500h (STATUS_BYTE) used by the ROM BIOS
; PRINT_SCREEN function.  There was also a DOS convention for using the byte
; at 504h to indicate whether the diskette drive in a single-drive system was
; operating as "logical drive" A (00h) or drive B (01h).

; Apparently the ROM BASIC can use bytes from 510h through 51Dh (or maybe
; through 521h); we play it safe and assume the latter.
;
; Some DOS boot sectors would read the first directory sector into 500h,
; which would result in the starting clusters of IO.SYS and MSDOS.SYS residing
; in 51Ah and 53Ah, respectively.  Our boot sector does read root directory
; sectors into low memory, but at 760h, not 500h, and no assumptions are made
; about directory entries or starting clusters.
;
; Other boot sectors would create an 11-byte copy of the BIOS Diskette
; Parameters Table (DPT) at 522h.  Updating the DPT as early as possible with
; faster values is useful, so we do the same.
;
		db	4 dup (?)	; 500h: reserved
LOGICAL_DRIVE	db	?		; 504h: (00h for A: or 01h for B:)
FDC_UNITS	db	?		; 505h: # floppy drives
FDC_DEVICE	dd	?		; 506h: FDC driver header
DD_LIST		dd	?		; 50Ah: head of device driver list
		db	20 dup (?)	; 50Eh: reserved
DPT_ACTIVE	DPT	<>		; 522h: active DPT
BOOT_KEY	dw	?		; 52Dh: set by boot sector
		db	1 dup (?)	; 52Fh: paragraph padding
DDINT_ENTER	db	5 dup (?)	; 530h: room for a 5-byte far jump
DDINT_LEAVE	db	5 dup (?)	; 535h: room for a 5-byte far jump
		db	6 dup (?)	; 53Ah: paragraph padding
;
; We move the boot sector from BOOT_SECTOR to FAT_SECTOR.
;
BOOT_SECTOR	equ	7C00h
BOOT_SECTOR_LO	equ	550h
FAT_BUFHDR	BUFHDR	<>		; 540h
FAT_SECTOR	db	512 dup (?)	; 550h

DIR_BUFHDR	BUFHDR	<>		; 750h
DIR_SECTOR_OFF	equ	760h
DIR_SECTOR	db	512 dup (?)	; 760h
		ASSERT 	<offset IVT + DIR_SECTOR_OFF>,EQ,<offset DIR_SECTOR>

BIOS_END	label	byte		; 960h

BIOS		ends

;
; The ROM stores some BIOS offsets relative to segment 40h (eg, BUFFER_HEAD
; and BUFFER_TAIL), so if we want to use those offsets within BIOS segment 00h,
; we must add BIOS_DATA (ie, 400h) to them.
;
BIOS_DATA	equ	RS232_BASE
