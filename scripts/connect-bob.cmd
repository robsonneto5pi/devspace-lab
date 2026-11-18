@echo off
REM ============================================================
REM connect-bob.cmd — Abre o tunel para o IBM Bob Desktop
REM
REM O Dev Spaces ja gerou o bloco "Host bob-lab" em devspaces.conf
REM com a porta local correta. Este script le essa porta e abre
REM o oc port-forward correto — sem configuracao manual.
REM
REM Uso:
REM   connect-bob.cmd
REM   connect-bob.cmd <namespace>
REM   connect-bob.cmd robson-neto-dev
REM
REM Pre-requisito:
REM   - oc.exe no PATH e oc login ja feito
REM ============================================================

setlocal enabledelayedexpansion

set "NS=%~1"
if "%NS%"=="" set "NS=robson-neto-dev"

set "CONF=%USERPROFILE%\.ssh\devspaces.conf"

echo.
echo [connect-bob] Lendo %CONF%...

REM Ler a porta do primeiro bloco "Host bob-lab" no devspaces.conf
set "LOCAL_PORT="
set "IN_BOB_HOST=0"
for /f "usebackq tokens=1,2" %%A in ("%CONF%") do (
    if /i "%%A"=="Host" (
        if /i "%%B"=="bob-lab" (
            set "IN_BOB_HOST=1"
        ) else (
            set "IN_BOB_HOST=0"
        )
    )
    if "!IN_BOB_HOST!"=="1" if /i "%%A"=="Port" (
        if "!LOCAL_PORT!"=="" set "LOCAL_PORT=%%B"
    )
)

if "!LOCAL_PORT!"=="" (
    echo [ERRO] Nenhum bloco "Host bob-lab" encontrado em %CONF%
    echo        Certifique-se de que o workspace foi criado com o tile IBM Bob.
    exit /b 1
)

echo [connect-bob] Porta local do bob-lab: !LOCAL_PORT!

REM Verificar fase do workspace e reiniciar se necessario
echo [connect-bob] Verificando workspace bob-lab em %NS%...

REM Usar powershell para obter a fase sem artefatos de CR/LF
for /f "usebackq tokens=*" %%F in (`powershell -NoProfile -Command "oc get dw bob-lab -n %NS% -o jsonpath='{.status.phase}' 2>$null"`) do set "PHASE=%%F"
REM Remover aspas simples que o powershell pode adicionar
set "PHASE=!PHASE:'=!"
echo [connect-bob] Workspace fase: !PHASE!

REM Verificar se esta Stopped — reiniciar
echo !PHASE! | findstr /i "Stopped" >nul
if not errorlevel 1 (
    echo [connect-bob] Workspace parado. Reiniciando...
    set "PATCH_FILE=%TEMP%\dw-patch.json"
    echo {"spec":{"started":true}}> "!PATCH_FILE!"
    oc patch dw bob-lab -n %NS% --type=merge --patch-file "!PATCH_FILE!" >nul
    echo [connect-bob] Aguardando workspace ficar Running...
    :waitloop
    timeout /t 5 /nobreak >nul
    for /f "usebackq tokens=*" %%F in (`powershell -NoProfile -Command "oc get dw bob-lab -n %NS% -o jsonpath='{.status.phase}' 2>$null"`) do set "PHASE=%%F"
    set "PHASE=!PHASE:'=!"
    echo [connect-bob]   Phase: !PHASE!
    echo !PHASE! | findstr /i "Running" >nul
    if errorlevel 1 goto waitloop
    echo [connect-bob] Workspace Running!
    goto prosseguir
)

REM Verificar se esta Running — OK
echo !PHASE! | findstr /i "Running" >nul
if not errorlevel 1 goto prosseguir

REM Fase inesperada
echo [ERRO] Workspace em fase inesperada: !PHASE!
echo        Verifique: oc get dw bob-lab -n %NS%
exit /b 1

:prosseguir

REM Localizar o pod atual do workspace bob-lab
echo [connect-bob] Localizando pod em namespace %NS%...
set "POD="
for /f "tokens=1" %%P in ('oc get pods -n %NS% --no-headers -o custom-columns^=NAME:.metadata.name 2^>nul ^| findstr /i "workspace"') do (
    if "!POD!"=="" set "POD=%%P"
)

if "!POD!"=="" (
    echo [ERRO] Nenhum pod de workspace encontrado em %NS%.
    echo        Verifique: oc get pods -n %NS%
    exit /b 1
)

echo [connect-bob] Pod: !POD!
echo.

REM Instalar chave publica no pod (silencioso se ja existir)
set "PUBKEY_FILE=%USERPROFILE%\.ssh\id_ed25519.pub"
if exist "!PUBKEY_FILE!" (
    echo [connect-bob] Instalando chave publica no pod...
    set /p PUBKEY=<"!PUBKEY_FILE!"
    oc exec -n %NS% !POD! -c udi -- bash -c "mkdir -p /home/user/.ssh && chmod 700 /home/user/.ssh && grep -qxF '!PUBKEY!' /home/user/.ssh/authorized_keys 2>/dev/null || echo '!PUBKEY!' >> /home/user/.ssh/authorized_keys && chmod 600 /home/user/.ssh/authorized_keys" >nul 2>&1
    echo [connect-bob] Chave instalada.
) else (
    echo [AVISO] Chave %PUBKEY_FILE% nao encontrada. Conexao pode falhar.
)

echo.
echo ========================================================
echo  Tunel aberto: 127.0.0.1:!LOCAL_PORT! ^<-^> pod:2022
echo  No IBM Bob Desktop: Retry na janela de erro
echo  Deixe este terminal aberto enquanto usar o Bob.
echo ========================================================
echo.

oc port-forward -n %NS% pod/!POD! !LOCAL_PORT!:2022 --address 127.0.0.1

endlocal
