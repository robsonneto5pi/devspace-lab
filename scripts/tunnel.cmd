@echo off
REM ============================================================
REM tunnel.cmd — Abre o tunel SSH para o workspace Dev Spaces
REM
REM Uso:
REM   tunnel.cmd <namespace> <porta-local>
REM   tunnel.cmd robson-neto-dev 48778
REM
REM Pre-requisitos:
REM   - oc.exe no PATH
REM   - Ter feito oc login antes (oc login --token=... --server=...)
REM   - Workspace "bob-lab" deve estar rodando
REM ============================================================

setlocal

set "NS=%~1"
set "LOCAL_PORT=%~2"

if "%NS%"=="" set "NS=robson-neto-dev"
if "%LOCAL_PORT%"=="" set "LOCAL_PORT=48778"

echo.
echo [tunnel.cmd] Namespace    : %NS%
echo [tunnel.cmd] Porta local  : %LOCAL_PORT%
echo.

REM Localiza o deploy do workspace bob-lab (nome fixo no devfile)
echo [tunnel.cmd] Procurando deployment do workspace bob-lab...
for /f "tokens=*" %%D in ('oc get deploy -n %NS% -o name 2^>^&1 ^| findstr /i "bob-lab"') do (
    set "DEPLOY=%%D"
)

if "%DEPLOY%"=="" (
    echo [ERRO] Nenhum deployment "bob-lab" encontrado em %NS%.
    echo        Verifique se o workspace esta rodando: oc get dw -n %NS%
    exit /b 1
)

echo [tunnel.cmd] Deployment encontrado: %DEPLOY%
echo [tunnel.cmd] Iniciando port-forward %LOCAL_PORT% -^> 2022 (SSH) ...
echo [tunnel.cmd] Pressione Ctrl+C para encerrar o tunel.
echo.

oc port-forward -n %NS% %DEPLOY% %LOCAL_PORT%:2022 --address 127.0.0.1

endlocal
