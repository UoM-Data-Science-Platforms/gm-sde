@ECHO OFF

REM Call npm install to ensure up to date
call npm i --quiet --production

REM Main script called via npm start
call npm start

pause