@ECHO OFF

REM ┌─────────────────────────────────────────────────────────────────────────┐
REM │ Windows batch script to stitch the template SQL into the extraction SQL │
REM │ It also constructs a README.md file for the project listing all code    │
REM │ sets used in the creation of the SQL and any other useful info too      │
REM └─────────────────────────────────────────────────────────────────────────┘

REM move to batch dir 
cd /d %~dp0
SET PROJECT_DIR=%CD%

REM move to project root
cd ../..

REM Call npm install to ensure up to date
call npm i --quiet

REM Return to project root
cd %PROJECT_DIR%

node ../../scripts/main.js stitch

pause