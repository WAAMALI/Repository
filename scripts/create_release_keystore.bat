@echo off
setlocal
where keytool >nul 2>nul
if errorlevel 1 (
  echo ERROR: keytool was not found. Install JDK 17 and add its bin folder to PATH.
  pause
  exit /b 1
)

set "KEYSTORE=%~dp0..\android\app\tvexp-release-key.jks"
for %%I in ("%KEYSTORE%") do set "KEYSTORE=%%~fI"

if exist "%KEYSTORE%" (
  echo A keystore already exists:
  echo %KEYSTORE%
  echo Do not overwrite it. Keep using the existing key for all future updates.
  pause
  exit /b 1
)

echo Creating a private Android release keystore.
echo Remember the passwords. Losing this key/password can prevent future app updates.
echo Use a strong password and keep an offline backup.
echo.
keytool -genkeypair -v -keystore "%KEYSTORE%" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias tvexp
if errorlevel 1 (
  if exist "%KEYSTORE%" del "%KEYSTORE%"
  echo Keystore creation failed.
  pause
  exit /b 1
)

echo.
echo Keystore created:
echo %KEYSTORE%
echo Back it up securely. Do not upload the JKS file to GitHub.
pause
endlocal
