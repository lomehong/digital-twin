@echo off
setlocal
title Suite Release
rem ============================================================
rem digital-twin suite plugin releaser -- release discipline as a script.
rem
rem Usage:   scripts\release.bat ^<plugin-dir^> ^<patch^|minor^|major^|x.y.z^>
rem Example: scripts\release.bat dsh-twin patch
rem
rem Discipline is enforced by the script, not by memory:
rem   1. releases only from branch main;
rem   2. working tree must be clean (uncommitted changes = reject);
rem   3. local "npm test" must pass (failure = reject);
rem   4. version bump + commit + tag in one step via npm version
rem      (tag always equals the new version);
rem   5. pushing main + tag triggers the repo's release CI (build, audit,
rem      attach tarball to GitHub Release). A tag that does not match
rem      package.json version is rejected by the CI audit.
rem ============================================================

if "%~2"=="" (
    echo usage: %~nx0 ^<plugin-dir^> ^<patch^|minor^|major^|x.y.z^>
    echo   e.g. %~nx0 dsh-twin patch
    exit /b 1
)
set "DIR=%~1"
set "BUMP=%~2"

if not exist "%DIR%\package.json" (
    echo [release] not found: %DIR%\package.json
    exit /b 1
)

pushd "%DIR%"

for /f "delims=" %%b in ('git branch --show-current') do set "BRANCH=%%b"
if not "%BRANCH%"=="main" (
    echo [release] current branch is "%BRANCH%" - releases are only allowed from main
    popd
    exit /b 1
)

git diff --quiet >nul 2>&1
if errorlevel 1 (
    echo [release] working tree has uncommitted changes - commit first
    popd
    exit /b 1
)

echo [release] running npm test ...
call npm test
if errorlevel 1 (
    echo [release] tests failed - release rejected
    popd
    exit /b 1
)

echo [release] bumping version %BUMP% ...
for /f "delims=" %%v in ('call npm version %BUMP%') do set "NEWTAG=%%v"
if not defined NEWTAG (
    echo [release] npm version failed - nothing released
    popd
    exit /b 1
)

echo [release] pushing main + %NEWTAG% - this triggers the release CI ...
git push origin main
git push origin %NEWTAG%
if errorlevel 1 (
    echo [release] push FAILED - finish manually: git push ^&^& git push %NEWTAG%
) else (
    echo [release] done. When CI finishes, the tarball lands on the GitHub Release page.
    echo [release] reminder: update the meta-repo submodule pointer: git add %DIR% ^&^& git commit
)

popd
exit /b 0
