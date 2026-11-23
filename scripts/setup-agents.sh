#!/usr/bin/env bash
# Instala as CLIs dos agentes de IA e carrega o .env.local em todo terminal novo.
# Uso: bash scripts/setup-agents.sh   (também roda no postStart do devfile)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env.local"
NPM_PREFIX="$HOME/.npm-global"
BASHRC="$HOME/.bashrc"

# Pacote npm -> comando. Confirme os nomes na documentação de cada ferramenta.
PACKAGES=(
  "@anthropic-ai/claude-code"  # claude
  "@openai/codex"              # codex
  "opencode-ai"                # opencode
  "cline"                      # cline
)

if ! command -v npm >/dev/null 2>&1; then
  echo "✗ npm não encontrado; instale o Node.js antes." >&2
  exit 1
fi

# Prefixo em $HOME evita erro de permissão no npm install -g
mkdir -p "$NPM_PREFIX/bin"
export PATH="$NPM_PREFIX/bin:$PATH"

for pkg in "${PACKAGES[@]}"; do
  if npm install -g --prefix "$NPM_PREFIX" "$pkg" >/dev/null 2>&1; then
    echo "✓ $pkg"
  else
    echo "✗ $pkg (falhou; rode 'npm install -g --prefix $NPM_PREFIX $pkg' para ver o erro)" >&2
  fi
done

# Adiciona PATH e carga do .env.local ao .bashrc (idempotente)
MARK="# >>> setup-agents >>>"
if ! grep -qF "$MARK" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<EOF

$MARK
export PATH="$NPM_PREFIX/bin:\$PATH"
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
# <<< setup-agents <<<
EOF
  echo "✓ .bashrc atualizado"
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "! $ENV_FILE não existe (o storage é efêmero e o arquivo não é versionado); recrie-o com as chaves." >&2
fi

echo "Feito. Abra um novo terminal ou rode: source ~/.bashrc"
echo "Comandos: claude | codex | opencode | cline"
