@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo   BUILD NFC STUDENT SCANNER APK
echo ============================================================
echo.

where flutter >nul 2>&1
if errorlevel 1 (
  echo [LOI] Khong tim thay lenh flutter.
  echo.
  echo Cai Flutter Stable va Android Studio truoc, sau do mo terminal moi.
  echo Kiem tra bang: flutter doctor
  echo.
  pause
  exit /b 1
)

echo [1/6] Kiem tra Flutter...
call flutter --version
if errorlevel 1 goto :error

echo.
echo [2/6] Tao Android project theo dung Flutter dang cai...
if exist "build_project" rmdir /s /q "build_project"
call flutter create --platforms=android --org com.studentdemo --project-name nfc_scanner "build_project"
if errorlevel 1 goto :error

echo.
echo [3/6] Chep source NFC scanner...
copy /Y "source\pubspec.yaml" "build_project\pubspec.yaml" >nul
copy /Y "source\main.dart" "build_project\lib\main.dart" >nul
copy /Y "source\AndroidManifest.xml" "build_project\android\app\src\main\AndroidManifest.xml" >nul

echo.
echo [4/6] Tai dependencies...
pushd "build_project"
call flutter pub get
if errorlevel 1 (
  popd
  goto :error
)

echo.
echo [5/6] Build APK release...
call flutter build apk --release
if errorlevel 1 (
  popd
  goto :error
)
popd

echo.
echo [6/6] Copy APK ra thu muc hien tai...
if exist "NFCStudentScanner.apk" del /q "NFCStudentScanner.apk"
copy /Y "build_project\build\app\outputs\flutter-apk\app-release.apk" "NFCStudentScanner.apk" >nul
if errorlevel 1 goto :error

echo.
echo ============================================================
echo   BUILD THANH CONG
echo ============================================================
echo APK:
echo %CD%\NFCStudentScanner.apk
echo.
echo Cai qua ADB:
echo adb install -r NFCStudentScanner.apk
echo.
pause
exit /b 0

:error
echo.
echo ============================================================
echo   BUILD THAT BAI
echo ============================================================
echo Chay "flutter doctor -v" va sua cac muc Android toolchain bi loi.
echo Sau do chay lai build_apk.bat.
echo.
pause
exit /b 1
