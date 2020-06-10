@ECHO OFF

REM move to this directory
cd /d %~dp0

ECHO Last chance to abort - tell them what is about to happen
pause

SET DB=DataFromSIR

REM for each sql file execute against db
forfiles /p sql-queries /s /m dx*.sql /c "cmd /c sqlcmd -E -d %DB% -i @path -W -s , -h -1 -o @fname"

REM each output file move to data directory and add a .txt extension
forfiles /p sql-queries /s /m dx* /c "cmd /c if not @ext==0x22sql0x22 move /y @path ../data/@fname.txt"

pause