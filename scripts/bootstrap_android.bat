
@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "TMP=%TEMP%\tvexp_wrapper_seed"

where flutter >nul 2>nul
if errorlevel 1 (
    echo ERROR: Flutter SDK is required.
    exit /b 1
)

if exist "%TMP%" rmdir /s /q "%TMP%"

flutter create --platforms=android --project-name tvexp_iptv "%TMP%" >nul
if errorlevel 1 (
    echo ERROR: Flutter wrapper generation failed.
    exit /b 1
)

if not exist "%ROOT%\android\gradle\wrapper" (
    mkdir "%ROOT%\android\gradle\wrapper"
)

copy /y "%TMP%\android\gradlew" "%ROOT%\android\gradlew" >nul
if errorlevel 1 goto :fail

copy /y "%TMP%\android\gradlew.bat" "%ROOT%\android\gradlew.bat" >nul
if errorlevel 1 goto :fail

xcopy /e /i /y "%TMP%\android\gradle\wrapper" "%ROOT%\android\gradle\wrapper" >nul
if errorlevel 1 goto :fail

> "%ROOT%\android\gradle\wrapper\gradle-wrapper.properties" (
    echo distributionBase=GRADLE_USER_HOME
    echo distributionPath=wrapper/dists
    echo distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-all.zip
    echo zipStoreBase=GRADLE_USER_HOME
    echo zipStorePath=wrapper/dists
)

if errorlevel 1 goto :fail

rmdir /s /q "%TMP%"

echo Android Gradle wrapper installed successfully.
echo Gradle: 8.14.3
echo AGP: 8.11.1
exit /b 0

:fail
echo ERROR: Android Gradle wrapper installation failed.
if exist "%TMP%" rmdir /s /q "%TMP%"
exit /b 1
