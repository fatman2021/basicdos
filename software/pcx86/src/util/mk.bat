MAKE MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
COPY COMMAND.COM A:
COPY PRIMES.COM A:
COPY TESTS.COM A:
IF "%1"=="" GOTO EXIT
CD ..
:EXIT