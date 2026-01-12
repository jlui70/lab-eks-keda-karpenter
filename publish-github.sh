#!/bin/bash
#*************************
# Script de Publicação no GitHub
# Execute após validar que tudo está funcionando
#*************************

set -e

# Cores
RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
NC=$(tput sgr0 2>/dev/null || echo "")

echo "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║                                                           ║${NC}"
echo "${CYAN}║        🚀 PUBLICAÇÃO NO GITHUB - EKS KEDA KARPENTER      ║${NC}"
echo "${CYAN}║                                                           ║${NC}"
echo "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar se estamos no diretório correto
if [ ! -f "README.md" ] || [ ! -d "deployment" ]; then
    echo "${RED}❌ Erro: Execute este script no diretório raiz do projeto${NC}"
    exit 1
fi

# Passo 1: Validações pré-git
echo "${YELLOW}📋 Passo 1/6: Validações Pré-Git${NC}"
echo ""

# Verificar tamanho do repo
echo "${CYAN}   • Verificando tamanho do repositório...${NC}"
SIZE=$(du -sh --exclude=venv --exclude=backups --exclude=docs --exclude=.git . | awk '{print $1}')
echo "${GREEN}     ✅ Tamanho do repo (sem ignorados): ${SIZE}${NC}"

# Verificar se venv/ está ignorado
if [ -d "app/keda/venv" ]; then
    echo "${GREEN}     ✅ venv/ existe e será ignorado${NC}"
fi

# Verificar se docs/ está ignorado
if [ -d "docs" ]; then
    echo "${GREEN}     ✅ docs/ existe e será ignorado${NC}"
fi

# Verificar se backups/ está ignorado
if [ -d "backups" ]; then
    echo "${GREEN}     ✅ backups/ existe e será ignorado${NC}"
fi

echo ""

# Passo 2: Inicializar Git (se necessário)
echo "${YELLOW}📋 Passo 2/6: Inicializar Git${NC}"
echo ""

if [ ! -d ".git" ]; then
    echo "${CYAN}   • Inicializando repositório Git...${NC}"
    git init
    echo "${GREEN}     ✅ Git inicializado${NC}"
else
    echo "${GREEN}     ✅ Git já está inicializado${NC}"
fi

echo ""

# Passo 3: Adicionar arquivos
echo "${YELLOW}📋 Passo 3/6: Adicionar Arquivos${NC}"
echo ""

echo "${CYAN}   • Adicionando arquivos ao stage...${NC}"
git add .

# Mostrar status
echo ""
echo "${CYAN}   • Status do repositório:${NC}"
echo ""
git status --short | head -20
TOTAL_FILES=$(git status --short | wc -l)
echo ""
echo "${GREEN}     ✅ Total de arquivos adicionados: ${TOTAL_FILES}${NC}"

# Verificar se arquivos ignorados não foram adicionados
echo ""
echo "${CYAN}   • Verificando arquivos ignorados:${NC}"
IGNORED_IN_STAGED=$(git status --short | grep -E "venv/|backups/|docs/" || echo "")
if [ -z "$IGNORED_IN_STAGED" ]; then
    echo "${GREEN}     ✅ Nenhum arquivo ignorado foi adicionado${NC}"
else
    echo "${RED}     ❌ ATENÇÃO: Arquivos ignorados foram adicionados!${NC}"
    echo "$IGNORED_IN_STAGED"
    exit 1
fi

echo ""

# Passo 4: Commit
echo "${YELLOW}📋 Passo 4/6: Criar Commit Inicial${NC}"
echo ""

# Verificar se já existe commit
if git rev-parse HEAD >/dev/null 2>&1; then
    echo "${GREEN}     ✅ Já existe commit no repositório${NC}"
    echo "${CYAN}     ℹ️  Para criar novo commit, use: git commit -m \"sua mensagem\"${NC}"
else
    echo "${CYAN}   • Criando commit inicial...${NC}"
    git commit -m "Initial commit: EKS KEDA Karpenter Lab v2

- Complete automated deployment scripts for EKS + KEDA + Karpenter
- Kubernetes 1.31, Karpenter 1.0.1, KEDA 2.15.1
- Prometheus + Grafana monitoring stack with custom dashboards
- Load testing scripts for autoscaling validation
- Automated cleanup script with Security Group handling
- Comprehensive documentation and quick commands guide

Features:
✅ One-command installation (_main.sh)
✅ SQS FIFO + DynamoDB integration
✅ Pod autoscaling with KEDA (1→50 pods)
✅ Node autoscaling with Karpenter (3→9 nodes)
✅ Real-time monitoring with Grafana dashboards
✅ Automated scale-down with cooldown configuration
✅ Emergency HPA reset script for presentations

Tested and validated in production-like environment."
    echo "${GREEN}     ✅ Commit criado com sucesso${NC}"
fi

echo ""

# Passo 5: Configurar Remote
echo "${YELLOW}📋 Passo 5/6: Configurar Remote do GitHub${NC}"
echo ""

# Verificar se remote já existe
if git remote | grep -q "origin"; then
    REMOTE_URL=$(git remote get-url origin)
    echo "${GREEN}     ✅ Remote 'origin' já configurado: ${REMOTE_URL}${NC}"
    echo ""
    echo "${CYAN}     ℹ️  Para alterar, use:${NC}"
    echo "${CYAN}        git remote set-url origin https://github.com/<usuario>/<repo>.git${NC}"
else
    echo "${YELLOW}     ⚠️  Remote 'origin' não configurado${NC}"
    echo ""
    echo "${CYAN}     Configure manualmente com:${NC}"
    echo "${CYAN}        git remote add origin https://github.com/<usuario>/<repo>.git${NC}"
    echo "${CYAN}        git branch -M main${NC}"
    echo ""
    read -p "     Deseja configurar agora? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        read -p "     Digite a URL do repositório GitHub: " REPO_URL
        git remote add origin "$REPO_URL"
        git branch -M main
        echo "${GREEN}     ✅ Remote configurado: ${REPO_URL}${NC}"
    else
        echo "${YELLOW}     ⏸️  Configuração de remote pulada${NC}"
        echo "${YELLOW}     Execute manualmente quando estiver pronto${NC}"
        exit 0
    fi
fi

echo ""

# Passo 6: Push
echo "${YELLOW}📋 Passo 6/6: Push para GitHub${NC}"
echo ""

echo "${CYAN}   • Verificando conexão com GitHub...${NC}"
if git ls-remote origin HEAD &>/dev/null; then
    echo "${GREEN}     ✅ Conexão com GitHub OK${NC}"
    
    echo ""
    echo "${YELLOW}     ⚠️  ATENÇÃO: Isso irá fazer push dos arquivos para o GitHub${NC}"
    echo ""
    read -p "     Confirmar push? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo ""
        echo "${CYAN}   • Fazendo push para GitHub...${NC}"
        git push -u origin main
        echo ""
        echo "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║                                                           ║${NC}"
        echo "${GREEN}║        ✅ PROJETO PUBLICADO NO GITHUB COM SUCESSO!       ║${NC}"
        echo "${GREEN}║                                                           ║${NC}"
        echo "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "${CYAN}   🔗 Acesse seu repositório no GitHub e verifique!${NC}"
        echo ""
    else
        echo "${YELLOW}     ⏸️  Push cancelado${NC}"
        echo "${CYAN}     Execute quando estiver pronto: git push -u origin main${NC}"
    fi
else
    echo "${YELLOW}     ⚠️  Não foi possível conectar ao remote${NC}"
    echo "${CYAN}     Verifique se a URL está correta e você tem permissão${NC}"
    echo "${CYAN}     Execute manualmente: git push -u origin main${NC}"
fi

echo ""
echo "${GREEN}✅ Script concluído!${NC}"
echo ""
