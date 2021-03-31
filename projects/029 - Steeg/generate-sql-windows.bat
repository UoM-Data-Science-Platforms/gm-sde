@ECHO OFF

REM ┌─────────────────────────────────────────────────────────────────────────┐
REM │ Windows batch script to stitch the template SQL into the extraction SQL │
REM └─────────────────────────────────────────────────────────────────────────┘

node ../../scripts/main.js stitch

pause