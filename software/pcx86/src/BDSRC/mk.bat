DEL A:*.COM
MAKE MAKEFILE
IF ERRORLEVEL 1 GOTO END
COPY DEV\IBMBIO.COM A:
COPY DOS\IBMDOS.COM A:
ECHO REM THIS IS A TEST>A:CONFIG.SYS
ECHO FILES=20>>A:CONFIG.SYS
ECHO CONSOLE=80,25>>A:CONFIG.SYS
:END
