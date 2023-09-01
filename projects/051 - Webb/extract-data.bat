@ECHO OFF

REM ┌────────────────────────────────────────────────┐
REM │ Windows batch script to extract the data files │
REM └────────────────────────────────────────────────┘

REM move to batch dir 
cd /d %~dp0

REM Call npm install to ensure up to date
cd scripts
call npm i --quiet

REM Return to project root
cd ..

REM Main script called via npm start
call node scripts/main.js

pause

REM OLD WAY KEEP FOR NOW
REM set USERNAME=richard.williams@grhapp.com
REM set /p USERNAME=Enter your username (e.g. richard.williams@grhapp.com):
REM REM for each sql file execute against the HDM_Research database using MFA Azure AD
REM forfiles /p extraction-sql /s /m *.sql /c "cmd /c sqlcmd -S GM-ccbi-live-01.database.windows.net -G -U %USERNAME% -l 30 -d HDM_Research -i @path -W -s , -h -1 -o @fname"
REM REM each output file move to data directory and add a .txt extension
REM forfiles /p extraction-sql /s /m * /c "cmd /c if not @ext==0x22sql0x22 move /y @path ../output-data-files/@fname.txt"
REM pause