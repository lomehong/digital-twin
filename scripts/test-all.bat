@echo off
rem 全量测试：跑数字分身套件全部插件的测试套件
setlocal
set FAILED=
for %%d in (dsh-actors dsh-computer dsh-im-bot dsh-ledger dsh-memory dsh-redact dsh-regression dsh-twin dsh-yuyi) do (
    echo [test-all] %%d ...
    pushd %%d
    call npm test || set FAILED=%%d
    popd
)
if defined FAILED (echo [test-all] 失败：%FAILED% & exit /b 1)
echo [test-all] 全部通过
