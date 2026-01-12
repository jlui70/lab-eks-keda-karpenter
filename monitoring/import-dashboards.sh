#!/bin/bash
#*************************
# IMPORTAR DASHBOARDS GRAFANA
# Dashboards customizados para KEDA + Karpenter
#*************************

source $(dirname "$0")/../deployment/environmentVariables.sh

echo "${BLUE}🎨 IMPORTAÇÃO DE DASHBOARDS GRAFANA"
echo "====================================="

# Verificar se Grafana está rodando
if ! kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
    echo "${RED}❌ Erro: Grafana não encontrado no namespace 'monitoring'"
    echo "${YELLOW}Execute primeiro: ./monitoring/install-monitoring.sh"
    exit 1
fi

echo "${GREEN}✅ Grafana detectado"

# Obter credenciais do Grafana
GRAFANA_PASSWORD="admin123"
GRAFANA_USER="admin"

echo ""
echo "${CYAN}📊 Dashboards Disponíveis:"
echo "${CYAN}   1. SQS Payments Dashboard - Monitoramento de filas SQS e pods KEDA"
echo "${CYAN}   2. EKS E-commerce Dashboard - HTTP requests e scaling"

echo ""
echo "${YELLOW}📋 Instruções de Importação Manual:"
echo ""
echo "${CYAN}1️⃣  Acesse o Grafana:"
echo "${GREEN}   kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "${GREEN}   URL: http://localhost:3000"
echo "${GREEN}   Login: ${GRAFANA_USER} / ${GRAFANA_PASSWORD}"
echo ""
echo "${CYAN}2️⃣  No Grafana, clique em:"
echo "${YELLOW}   [+] Create → Import → Upload JSON file"
echo ""
echo "${CYAN}3️⃣  Importe os arquivos:"
echo "${GREEN}   📁 monitoring/grafana-dashboard-sqs-payments.json"
echo "${GREEN}   📁 monitoring/grafana-dashboard-eks-ecommerce.json"
echo ""
echo "${CYAN}4️⃣  Selecione o Data Source:"
echo "${YELLOW}   Prometheus → monitoring-kube-prometheus-prometheus"
echo ""

# Criar ConfigMap com os dashboards para provisioning automático
echo ""
echo "${CYAN}🚀 Criando ConfigMaps para provisioning automático..."

# Dashboard 1: SQS Payments
if [ -f "$(dirname "$0")/grafana-dashboard-sqs-payments.json" ]; then
    kubectl create configmap grafana-dashboard-sqs-payments \
      --from-file=dashboard.json=$(dirname "$0")/grafana-dashboard-sqs-payments.json \
      -n monitoring \
      --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl label configmap grafana-dashboard-sqs-payments \
      grafana_dashboard=1 \
      -n monitoring --overwrite
    
    echo "${GREEN}   ✅ SQS Payments Dashboard configurado"
fi

# Dashboard 2: EKS E-commerce
if [ -f "$(dirname "$0")/grafana-dashboard-eks-ecommerce.json" ]; then
    kubectl create configmap grafana-dashboard-eks-ecommerce \
      --from-file=dashboard.json=$(dirname "$0")/grafana-dashboard-eks-ecommerce.json \
      -n monitoring \
      --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl label configmap grafana-dashboard-eks-ecommerce \
      grafana_dashboard=1 \
      -n monitoring --overwrite
    
    echo "${GREEN}   ✅ EKS E-commerce Dashboard configurado"
fi

# Reiniciar Grafana para carregar novos dashboards
echo ""
echo "${CYAN}🔄 Reiniciando Grafana para carregar dashboards..."
kubectl rollout restart deployment monitoring-grafana -n monitoring
kubectl rollout status deployment monitoring-grafana -n monitoring --timeout=120s

echo ""
echo "${GREEN}🎉 Dashboards importados com sucesso!"
echo ""
echo "${YELLOW}📊 Acesse os Dashboards:"
echo "${CYAN}   1. Port-forward: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "${CYAN}   2. Abra: http://localhost:3000"
echo "${CYAN}   3. Login: admin / admin123"
echo "${CYAN}   4. Menu: Dashboards → Browse"
echo ""
echo "${GREEN}✅ Dashboards Disponíveis:"
echo "${CYAN}   📈 SQS Payments Dashboard"
echo "${CYAN}   📈 EKS E-commerce Dashboard"
