@ECHO OFF

REM ┌────────────────────────────────────────────────┐
REM │ Windows batch script to extract the data files │
REM └────────────────────────────────────────────────┘

@ECHO OFF

REM move to batch dir 
cd /d %~dp0

REM for each sql file execute against the HDM_Research database using MFA Azure AD
forfiles /p extraction-sql /s /m *.sql /c "cmd /c sqlcmd -G -d HDM_Research -i @path -W -s , -h -1 -o @fname"

REM each output file move to data directory and add a .txt extension
forfiles /p extraction-sql /s /m * /c "cmd /c if not @ext==0x22sql0x22 move /y @path ../output-data-files/@fname.txt"

pause