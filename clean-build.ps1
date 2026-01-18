Remove-Item -Path ".\windows\prebuilt"  -Recurse -Force
Remove-Item -Path ".\example\build"  -Recurse -Force
flutter clean
.\scripts\build_all.ps1 > output.log 2>&1
Set-Location .\example
flutter clean
flutter run -d windows --release 2>&1 | Tee-Object -FilePath output.log