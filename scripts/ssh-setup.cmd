@echo off
REM ============================================================
REM ssh-setup.cmd — Instala a chave publica SSH no workspace
REM e cria/atualiza o bloco Host no ~/.ssh/config (Windows)
REM
REM Uso:
REM   ssh-setup.cmd <namespace> <porta-local>
REM   ssh-setup.cmd robson-neto-dev 48778
REM
REM Pre-requisitos:
REM   - oc.exe no PATH
REM   - ssh-keygen.exe disponivel (Git for Windows / OpenSSH do Windows 10+)
REM   - Ter feito oc login antes
REM   - Workspace bob-lab rodando e tunel AINDA NAO precisa estar ativo
REM ============================================================

setlocal enabledelayedexpansion

set "NS=%~1"
set "LOCAL_PORT=%~2"
set "HOST_ALIAS=devspaces-bob"
set "SSH_KEY=%USERPROFILE%\.ssh\id_devspaces"
set "SSH_CONFIG=%USERPROFILE%\.ssh\config"

if "%NS%"=="" set "NS=robson-neto-dev"
if "%LOCAL_PORT%"=="" set "LOCAL_PORT=48778"

echo.
echo [ssh-setup.cmd] Namespace  : %NS%
echo [ssh-setup.cmd] Porta local: %LOCAL_PORT%
echo [ssh-setup.cmd] Host alias : %HOST_ALIAS%
echo.

REM --- 1. Garantir que o diretorio .ssh existe ---
if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"

REM --- 2. Gerar chave SSH dedicada se nao existir ---
if not exist "%SSH_KEY%" (
    echo [ssh-setup.cmd] Gerando chave SSH: %SSH_KEY%
    ssh-keygen -t ed25519 -f "%SSH_KEY%" -N "" -C "devspaces-bob-lab"
    if errorlevel 1 (
        echo [ERRO] Falha ao gerar chave SSH.
        exit /b 1
    )
) else (
    echo [ssh-setup.cmd] Chave SSH ja existe: %SSH_KEY%
)

REM --- 3. Localizar o pod do workspace ---
echo [ssh-setup.cmd] Localizando pod do workspace bob-lab em %NS%...
for /f "tokens=*" %%P in ('oc get pods -n %NS% -l "controller.devfile.io/devworkspace_name=bob-lab" -o name 2^>^&1 ^| findstr /i "pod/"') do (
    set "POD=%%P"
)

if "!POD!"=="" (
    echo [ERRO] Nenhum pod "bob-lab" encontrado em %NS%.
    echo        Verifique: oc get pods -n %NS% -l controller.devfile.io/devworkspace_name=bob-lab
    exit /b 1
)
echo [ssh-setup.cmd] Pod: !POD!

REM --- 4. Instalar chave publica no pod ---
echo [ssh-setup.cmd] Instalando chave publica no pod...
set /p PUBKEY=<"%SSH_KEY%.pub"
oc exec -n %NS% !POD! -c udi -- bash -c "mkdir -p /home/user/.ssh && chmod 700 /home/user/.ssh && touch /home/user/.ssh/authorized_keys && (grep -qxF '!PUBKEY!' /home/user/.ssh/authorized_keys || echo '!PUBKEY!' >> /home/user/.ssh/authorized_keys) && chmod 600 /home/user/.ssh/authorized_keys && echo OK"
if errorlevel 1 (
    echo [ERRO] Falha ao instalar chave no pod. Verifique se o pod esta Running.
    exit /b 1
)
echo [ssh-setup.cmd] Chave instalada com sucesso.

REM --- 5. Atualizar ~/.ssh/config ---
echo.
echo [ssh-setup.cmd] Atualizando %SSH_CONFIG%...

REM Remove bloco antigo se existir
if exist "%SSH_CONFIG%" (
    powershell -Command ^
        "$c = Get-Content '%SSH_CONFIG%' -Raw; " ^
        "$c = $c -replace '(?s)# BEGIN devspaces-bob.*?# END devspaces-bob\r?\n?', ''; " ^
        "Set-Content '%SSH_CONFIG%' $c.TrimEnd()"
)

REM Adiciona bloco novo
(
echo.
echo # BEGIN devspaces-bob
echo Host %HOST_ALIAS%
echo     HostName 127.0.0.1
echo     Port %LOCAL_PORT%
echo     User user
echo     IdentityFile %SSH_KEY%
echo     StrictHostKeyChecking no
echo     UserKnownHostsFile /dev/null
echo     ServerAliveInterval 30
echo     ServerAliveCountMax 5
echo # END devspaces-bob
) >> "%SSH_CONFIG%"

echo [ssh-setup.cmd] Configuracao SSH salva em %SSH_CONFIG%.
echo.
echo ========================================================
echo  Proximo passo:
echo   1. Execute: scripts\tunnel.cmd %NS% %LOCAL_PORT%
echo      (em outro terminal, deixe rodando)
echo   2. No IBM Bob: Remote-SSH -^> %HOST_ALIAS% -^> /projects/devspace-lab
echo ========================================================
echo.

endlocal
