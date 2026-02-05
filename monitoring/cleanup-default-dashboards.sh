#!/bin/bash
#*************************
# Remove dashboards padrão do Grafana
# Mantém apenas o dashboard customizado do projeto
#*************************

# Cores
RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
NC=$(tput sgr0 2>/dev/null || echo "")

echo ""
echo "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║    LIMPEZA DE DASHBOARDS PADRÃO DO GRAFANA               ║${NC}"
echo "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${YELLOW}📋 Este script irá remover todos os dashboards padrão do kube-prometheus-stack${NC}"
echo "${YELLOW}   mantendo apenas o dashboard customizado do projeto:${NC}"
echo "${GREEN}   • EKS Payment Processing - KEDA + Karpenter (SQS)${NC}"
echo ""

# Listar dashboards atuais
TOTAL_DASHBOARDS=$(kubectl get configmap -n monitoring -l grafana_dashboard=1 --no-headers 2>/dev/null | wc -l)
echo "${CYAN}📊 Dashboards encontrados: ${TOTAL_DASHBOARDS}${NC}"
echo ""

if [ "$TOTAL_DASHBOARDS" -le 1 ]; then
    echo "${GREEN}✅ Apenas 1 dashboard encontrado - limpeza não necessária!${NC}"
    echo ""
    exit 0
fi

echo "${YELLOW}🗑️  Removendo $(($TOTAL_DASHBOARDS - 1)) dashboards padrão...${NC}"
echo ""

# Remover todos exceto o customizado
REMOVED=0
for dashboard in $(kubectl get configmap -n monitoring -l grafana_dashboard=1 --no-headers 2>/dev/null | awk '{print $1}' | grep -v "grafana-dashboard-sqs-payments"); do
    kubectl delete configmap "$dashboard" -n monitoring >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "${GREEN}   ✅ Removido: ${dashboard}${NC}"
        REMOVED=$((REMOVED + 1))
    fi
done

echo ""
echo "${GREEN}✅ Total removido: ${REMOVED} dashboards${NC}"
echo ""

# Reiniciar Grafana
echo "${YELLOW}🔄 Reiniciando Grafana para aplicar mudanças...${NC}"
kubectl rollout restart deployment monitoring-grafana -n monitoring >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "${GREEN}✅ Grafana reiniciado com sucesso!${NC}"
    echo ""
    echo "${CYAN}📝 Próximos passos:${NC}"
    echo "   1. Aguarde 30 segundos para o Grafana reiniciar"
    echo "   2. Acesse: http://localhost:3000 (se port-forward estiver ativo)"
    echo "   3. Faça login novamente: admin / admin123"
    echo "   4. Menu: Dashboards → Browse"
    echo "   5. Você verá apenas 1 dashboard! 🎉"
    echo ""
else
    echo "${RED}❌ Erro ao reiniciar Grafana${NC}"
    exit 1
fi
