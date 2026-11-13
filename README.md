# devspaces-lab — IBM Bob + OpenShift Dev Spaces (TechZone, sem login Red Hat)

> Repositório de infraestrutura para provisionar um ambiente IBM Bob no TechZone usando  
> OpenShift Dev Spaces **sem** necessidade de conta Red Hat / sso.redhat.com.  
> **Nunca versionar:** tokens, chaves SSH, certificados ou dados do cluster (`.secrets/`).

---

## Pré-requisitos

| Ferramenta | Versão mínima | Download |
|---|---|---|
| `oc` CLI | 4.14+ | https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/ |
| OpenSSH (Windows) | Nativo (Win 10+) | Configurações → Apps → Recursos Opcionais → OpenSSH Client |
| IBM Bob | Mais recente | https://marketplace.visualstudio.com/items?itemName=IBM.wca-vscode-ext |
| VPN Cisco | — | Necessária para acessar o TechZone (`pok-systems.techzone.ibm.com`) |

---

## Estrutura do repositório

```
devspaces-lab/
├── devfile.yaml                   # Devfile do workspace (sem login Red Hat)
├── .che/
│   └── che-editor.yaml            # Seleciona IBM Bob como editor padrão
├── manifests/
│   ├── 01-devspaces-operator.yaml # Instala o operador Dev Spaces via OLM
│   └── 02-checluster.yaml         # CheCluster: auth via OCP token, sem RH OAuth
├── scripts/
│   ├── tunnel.cmd                 # Abre port-forward SSH para o workspace
│   └── ssh-setup.cmd              # Instala chave pública no pod e configura ~/.ssh/config
└── .gitignore
```

---

## Como eliminar o login Red Hat

O problema original era que o Dev Spaces, por padrão, usa o **Red Hat SSO** (`sso.redhat.com`)  
como Identity Provider, forçando login em conta Red Hat.

### Solução implementada

No [`manifests/02-checluster.yaml`](manifests/02-checluster.yaml):

```yaml
networking:
  auth:
    gateway:
      kubernetesRBAC:
        enabled: true   # ← autentica pelo token do `oc login` (ServiceAccount/kubeadmin)
    identityProviderURL: ""  # ← vazio = sem redirect para sso.redhat.com
```

Com isso, o acesso ao Dev Spaces é feito com o mesmo token OCP obtido por:

```bash
# No console OCP → canto superior direito → "Copy login command"
oc login --token=<seu-token> --server=https://api.<cluster>:6443
```

Nenhuma conta Red Hat é necessária.

---

## Passo a passo: TechZone (OpenShift em IBM Power ou x86)

### 1. Provisionar o cluster no TechZone

1. Acesse https://techzone.ibm.com (com VPN Cisco ativa).
2. Provisione um ambiente **OpenShift 4.x** (Power ou x86 conforme disponibilidade).
3. Aguarde o e-mail de provisionamento com a URL da API (`api.<cluster>:6443`) e as credenciais do `kubeadmin`.

### 2. Instalar o Dev Spaces

```bash
# Login com kubeadmin (sem conta Red Hat)
oc login --token=<kubeadmin-token> --server=https://api.<cluster>:6443

# Criar namespace e instalar operador
oc apply -f manifests/01-devspaces-operator.yaml
oc wait csv -n openshift-operators -l operators.coreos.com/devspaces.openshift-operators \
   --for=jsonpath='{.status.phase}'=Succeeded --timeout=10m

# Criar namespace do Dev Spaces e aplicar CheCluster
oc new-project openshift-devspaces
oc apply -f manifests/02-checluster.yaml
oc wait checluster/devspaces -n openshift-devspaces \
   --for=jsonpath='{.status.chePhase}'=Active --timeout=10m

# Verificar URL do dashboard
oc get checluster devspaces -n openshift-devspaces \
   -o jsonpath='{.status.cheURL}{"\n"}'
```

### 3. Criar o workspace

**Opção A — via URL (mais simples):**
```
https://devspaces.apps.<cluster>/f?url=https://github.com/<seu-usuario>/devspaces-lab
```

**Opção B — via dashboard:**
1. Acesse o dashboard (URL obtida acima).
2. Create Workspace → Import from Git → cole a URL deste repositório.
3. O editor IBM Bob é selecionado automaticamente pelo `.che/che-editor.yaml`.

### 4. Conectar IBM Bob via SSH (necessário em Power/ppc64le; opcional em x86)

> No Developer Sandbox (x86), o IBM Bob carrega direto no browser. Os passos abaixo são  
> necessários apenas se você quiser usar o IBM Bob **desktop** (VS Code local).

```bat
REM Terminal 1 — fazer login (token copiado do console OCP)
oc login --token=<token> --server=https://api.<cluster>:6443

REM Terminal 2 — configurar SSH (só na 1ª vez ou quando o pod mudar)
scripts\ssh-setup.cmd <namespace> 48778

REM Terminal 3 — manter o túnel aberto (deixar rodando)
scripts\tunnel.cmd <namespace> 48778
```

No IBM Bob desktop:
- **Remote-SSH → Connect to Host → `devspaces-bob`**
- Abrir pasta: `/projects/openshift-lab`

---

## Passo a passo: Developer Sandbox (x86_64 — sem cluster próprio)

O Sandbox é gratuito, não exige conta em organização e usa x86_64 (IBM Bob funciona nativamente).

```bash
# 1. Acesse https://developers.redhat.com/developer-sandbox e crie conta gratuita
#    (esta é a única vez que conta Red Hat é usada — para provisionar o Sandbox)
# 2. Console → Copy login command → cole no terminal
oc login --token=<token> --server=https://api.rm2.thpm.p1.openshiftapps.com:6443

# 3. Verificar namespace e recursos
oc project <seu-usuario>-dev
oc get dw,pods -n <seu-usuario>-dev
```

Dashboard: `https://devspaces.apps.rm2.thpm.p1.openshiftapps.com/dashboard/`

> **Atenção:** No Sandbox, 1 workspace por vez. Pare o workspace anterior antes de criar outro.

---

## Notas de arquitetura

### Por que o devfile usa `storage-type: ephemeral`?

```yaml
attributes:
  controller.devfile.io/storage-type: ephemeral
```

PVCs demoram para serem provisionados no TechZone com `nfs-storage-provisioner` e podem travar  
o workspace. Com `ephemeral`, o workspace sobe imediatamente. **Desvantagem:** dados do `/home/user`  
são perdidos ao parar. Use sempre o repositório git para persistir código.

### Por que Ramalama + Qwen2.5-Coder:3b?

- Modelo leve (3B parâmetros), cabe em 4Gi de RAM.
- Sem chamadas externas: o LLM roda **dentro do pod** do workspace.
- Elimina dependência de API keys externas (OpenAI, Anthropic etc.).
- O Continue extension se conecta a `http://localhost:8080` automaticamente via `postStart`.

### IBM Bob em Power (ppc64le)

O editor "IBM Bob" do Dev Spaces declara suporte apenas para `x86_64` e `arm64`.  
Em Power, é necessário usar o container `che-code-sshd` e conectar via SSH como descrito na seção 4.  
Não é possível rodar o IBM Bob self-hosted em cluster ppc64le.

---

## Problemas conhecidos

| Sintoma | Causa | Solução |
|---|---|---|
| "Another instance is running as administrator" | Bob aberto com elevação | Fechar a instância elevada e reabrir normalmente |
| Explorer vazio / "path does not exist" | Caminho `/home/user/projects/...` inválido | Usar `/projects/<repo>` |
| Connection refused na porta 48778 | Túnel caiu ou workspace parou | `oc get dw -n <ns>`, reiniciar workspace, executar `tunnel.cmd` novamente |
| Workspace não sobe no TechZone Power | PVC pendente | Verificar StorageClass: `oc get sc`; usar `ephemeral` no devfile |
| Dashboard redireciona para sso.redhat.com | `identityProviderURL` configurado | Verificar `02-checluster.yaml`, garantir `identityProviderURL: ""` |

---

## Segurança

- Nunca versionar tokens, certificados ou saídas de `oc login`.
- Adicionar ao `.gitignore`: `.secrets/`, `*.crt`, `*.key`, `.env`.
- Antes de `git push`: `git diff HEAD` e `git log -p` para revisar segredos.
- O `curl -v` imprime credenciais de proxy. Evitar `-v` em ambientes corporativos.

---

*Baseado na sessão de trabalho documentada em GUIA-BOB-DEVSPACES.md e no padrão de CDE do repositório [remingtonsb/cde-ramalama-continue](https://github.com/remingtonsb/cde-ramalama-continue).*
