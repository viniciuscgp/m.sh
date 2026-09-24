#!/bin/bash
set -euo pipefail

# update.sh - baixa a última versão do repo e instala o m em /home/vinicius/.local/bin/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/home/vinicius/.local/bin"

cd "$SCRIPT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERRO: há alterações locais no repositório." >&2
  echo "  Use 'git stash' para guardá-las (ou 'git checkout -- .' para descartar) e rode novamente." >&2
  exit 1
fi

echo "==> Buscando a última versão..."
git pull --ff-only

echo "==> Instalando m em $BIN_DIR/"
mkdir -p "$BIN_DIR"
cp -f "$SCRIPT_DIR/m" "$BIN_DIR/m"
chmod +x "$BIN_DIR/m"

echo "==> OK! m atualizado."
