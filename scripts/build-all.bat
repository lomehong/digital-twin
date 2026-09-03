@echo off
rem 全量构建：按依赖顺序构建数字分身套件全部插件
setlocal
for %%d in (dsh-actors dsh-computer dsh-im-bot dsh-ledger dsh-memory dsh-redact dsh-regression dsh-twin dsh-yuyi) do (
    echo [build-all] %%d ...
    pushd %%d
    call npm run build || (echo [build-all] %%d 构建失败 & popd & exit /b 1)
    popd
)
echo [build-all] 全部完成
