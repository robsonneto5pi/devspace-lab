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
├── manifests/
│   ├── 01-devspaces-operator.yaml # Instala o operador Dev Spaces via OLM
│   └── 02-checluster.yaml         # CheCluster: auth via OCP token, sem RH OAuth
├── scripts/
│   ├── connect-bob.cmd            # ★ Conecta IBM Bob Desktop ao workspace (1 comando)
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

### 4. Conectar IBM Bob Desktop ao workspace

O Dev Spaces 3.31 tem suporte nativo ao IBM Bob via SSH (**Tech Preview**).
Ao criar o workspace com o tile **IBM Bob** no dashboard, o Dev Spaces:
- Configura automaticamente o bloco `Host bob-lab` em `~/.ssh/devspaces.conf`
- Expõe uma **landing page** na porta 3400 com o URI de conexão direto

#### Opção A — Landing page (mais simples, recomendado)

1. Com o workspace rodando, acesse a landing page do workspace:
   ```
   https://devspaces.apps.<cluster>/<namespace>/bob-lab/3400/
   ```
   Exemplo no Developer Sandbox:
   ```
   https://devspaces.apps.rm2.thpm.p1.openshiftapps.com/robson-neto/bob-lab/3400/
   ```
2. A página exibe o URI de conexão. Clique nele — o IBM Bob Desktop abre e conecta automaticamente.

> 💡 **Salve essa URL nos bookmarks** — enquanto o workspace estiver rodando, o clique no URI é o único passo necessário para reconectar o Bob Desktop.

#### Opção B — Script `connect-bob.cmd` (quando o link não funcionar ou token expirar)

O script lê a porta configurada pelo Dev Spaces no `~/.ssh/devspaces.conf`, instala a chave pública no pod e abre o túnel automaticamente.

**Terminal** (manter aberto enquanto usar o Bob):
```bat
cd C:\Users\RobsondeOliveiraNeto\Projetos\Dev\devspaces-lab
scripts\connect-bob.cmd
```

Depois no IBM Bob Desktop: **Remote-SSH → Connect to Host → `bob-lab`** e abrir a pasta `/projects/devspace-lab`.

> ⚠️ Pré-requisito: `oc login` já feito. Se o token expirou, copie o novo via
> console OCP → canto superior direito → **Copy login command**.

#### O que o `connect-bob.cmd` faz internamente

```
1. Lê ~/.ssh/devspaces.conf  →  encontra a porta local do Host bob-lab (ex: 62255)
2. oc get pods               →  localiza o pod atual do workspace
3. oc exec                   →  instala ~/.ssh/id_ed25519.pub no authorized_keys do pod
4. oc port-forward           →  abre 127.0.0.1:62255 → pod:2022 (SSH)
```

---

## Passo a passo: Developer Sandbox (x86_64 — sem cluster próprio)

O Sandbox é gratuito, não exige conta em organização e usa x86_64 (IBM Bob funciona nativamente).

```bash
# 1. Acesse https://developers.redhat.com/developer-sandbox e crie conta gratuita
#    (esta é a única vez que conta Red Hat é usada — para provisionar o Sandbox)
# 2. Console → Copy login command → cole no terminal
oc login --token=<token> --server=https://api.rm2.thpm.p1.openshiftapps.com:6443

# 3. Criar workspace a partir deste repositório
#    Dashboard → Create Workspace → Import from Git:
#    https://github.com/robsonneto5pi/devspace-lab
#    Selecionar o tile "IBM Bob" no Editor Selector
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
| Explorer vazio / "path does not exist" | Caminho `/home/user/projects/...` inválido | Usar `/projects/devspace-lab` |
| `ECONNREFUSED 127.0.0.1:<porta>` no Bob Desktop | Túnel não está aberto | Executar `scripts\connect-bob.cmd` num terminal e clicar em **Retry** no Bob |
| `access token received successfully` abre no browser | Callback do `oc login` — normal | Pode fechar a aba; o token já foi recebido no terminal |
| Workspace não sobe — `exceeded quota: requests.cpu` | `cpuRequest` total excede limite do Sandbox (3 CPUs) | Reduzir `cpuRequest` no devfile; valores atuais: `udi=100m`, `ramalama=200m` |
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
