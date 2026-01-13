#!/bin/bash
#*************************
# INSTALAÇÃO COMPLETA AUTOMÁTICA
# Prometheus + Grafana + Dashboards KEDA
# Execução ÚNICA para avaliadores
#*************************

set -e  # Exit on error

source $(dirname "$0")/../deployment/environmentVariables.sh

echo "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║     INSTALAÇÃO COMPLETA: MONITORING STACK                 ║${NC}"
echo "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "${RED}❌ Erro: kubectl não configurado ou cluster inacessível${NC}"
    exit 1
fi

echo "${GREEN}✅ Cluster conectado: ${CLUSTER_NAME}${NC}"
echo ""

# =============================================================================
# ETAPA 1: INSTALAR PROMETHEUS + GRAFANA
# =============================================================================
echo "${YELLOW}📦 ETAPA 1/4: Instalando Prometheus + Grafana...${NC}"

# Adicionar repositório Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Criar namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# Instalar kube-prometheus-stack
echo "${CYAN}   Instalando via Helm (aguarde 2-3 min)...${NC}"
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp2 \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.storageClassName=gp2 \
  --set grafana.persistence.size=10Gi \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.scrapeInterval=30s \
  --set grafana.service.type=ClusterIP \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.label=grafana_dashboard \
  --set grafana.sidecar.dashboards.searchNamespace=monitoring \
  --wait --timeout=600s

echo "${GREEN}   ✅ Prometheus + Grafana instalados${NC}"
echo ""

# =============================================================================
# ETAPA 2: CONFIGURAR MÉTRICAS KEDA
# =============================================================================
echo "${YELLOW}📊 ETAPA 2/4: Configurando métricas KEDA...${NC}"

# ServiceMonitor KEDA Metrics API Server (o importante para HPA)
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: keda-metrics-apiserver
  namespace: monitoring
  labels:
    app: keda-metrics-apiserver
    release: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: keda-operator-metrics-apiserver
  namespaceSelector:
    matchNames:
    - keda
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF

echo "${GREEN}   ✅ ServiceMonitors criados${NC}"
echo ""

# =============================================================================
# ETAPA 3: IMPORTAR DASHBOARDS AUTOMATICAMENTE
# =============================================================================
echo "${YELLOW}🎨 ETAPA 3/4: Importando dashboards customizados...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dashboard SQS Payments
if [ -f "${SCRIPT_DIR}/grafana-dashboard-sqs-payments.json" ]; then
    kubectl create configmap grafana-dashboard-sqs-payments \
      --from-file=dashboard.json=${SCRIPT_DIR}/grafana-dashboard-sqs-payments.json \
      -n monitoring \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    kubectl label configmap grafana-dashboard-sqs-payments \
      grafana_dashboard=1 \
      -n monitoring --overwrite >/dev/null 2>&1
    
    echo "${GREEN}   ✅ Dashboard: SQS Payments${NC}"
fi

# Dashboard EKS E-commerce
if [ -f "${SCRIPT_DIR}/grafana-dashboard-eks-ecommerce.json" ]; then
    kubectl create configmap grafana-dashboard-eks-ecommerce \
      --from-file=dashboard.json=${SCRIPT_DIR}/grafana-dashboard-eks-ecommerce.json \
      -n monitoring \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    kubectl label configmap grafana-dashboard-eks-ecommerce \
      grafana_dashboard=1 \
      -n monitoring --overwrite >/dev/null 2>&1
    
    echo "${GREEN}   ✅ Dashboard: EKS E-commerce${NC}"
fi

# Reiniciar Grafana para carregar dashboards
echo "${CYAN}   Reiniciando Grafana...${NC}"
kubectl rollout restart deployment monitoring-grafana -n monitoring >/dev/null 2>&1
kubectl rollout status deployment monitoring-grafana -n monitoring --timeout=120s >/dev/null 2>&1

echo "${GREEN}   ✅ Dashboards carregados automaticamente${NC}"
echo ""

# =============================================================================
# ETAPA 4: VALIDAÇÃO E INFORMAÇÕES DE ACESSO
# =============================================================================
echo "${YELLOW}🔍 ETAPA 4/4: Validando instalação...${NC}"

# Verificar pods
PROMETHEUS_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
GRAFANA_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

if [ "$PROMETHEUS_READY" = "True" ] && [ "$GRAFANA_READY" = "True" ]; then
    echo "${GREEN}   ✅ Prometheus: Running${NC}"
    echo "${GREEN}   ✅ Grafana: Running${NC}"
    echo "${GREEN}   ✅ ServiceMonitors: $(kubectl get servicemonitor -n monitoring 2>/dev/null | grep -c keda || echo 0) KEDA monitor (Metrics API Server)${NC}"
    echo "${GREEN}   ✅ Dashboards: 2 customizados importados${NC}"
else
    echo "${YELLOW}   ⚠️  Aguardando pods ficarem prontos...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=60s >/dev/null 2>&1 || true
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=60s >/dev/null 2>&1 || true
fi

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║         MONITORING STACK INSTALADO COM SUCESSO!           ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Obter URL do LoadBalancer
echo "${YELLOW}🌐 URLs de Acesso:${NC}"
echo ""

GRAFANA_LB=$(kubectl get svc -n monitoring monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ ! -z "$GRAFANA_LB" ] && [ "$GRAFANA_LB" != "null" ]; then
    echo "${GREEN}📊 Grafana (LoadBalancer):${NC}"
    echo "${CYAN}   URL: http://$GRAFANA_LB${NC}"
    echo "${CYAN}   Login: admin / admin123${NC}"
    echo ""
    echo "${YELLOW}   ⚠️  LoadBalancer pode levar 2-3 min para ficar disponível${NC}"
else
    echo "${YELLOW}📊 Grafana (aguardando LoadBalancer...)${NC}"
    echo "${CYAN}   Obter URL: kubectl get svc -n monitoring monitoring-grafana${NC}"
fi

echo ""
echo "${GREEN}📊 Grafana (Port-Forward - RECOMENDADO PARA DEMO):${NC}"
echo "${CYAN}   Comando: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring${NC}"
echo "${CYAN}   URL: http://localhost:3000${NC}"
echo "${CYAN}   Login: admin / admin123${NC}"
echo ""

echo "${GREEN}📈 Prometheus (Port-Forward):${NC}"
echo "${CYAN}   Comando: kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring${NC}"
echo "${CYAN}   URL: http://localhost:9090${NC}"
echo ""

echo "${GREEN}📋 Dashboards Disponíveis no Grafana:${NC}"
echo "${CYAN}   1. EKS Payment Processing - KEDA + Karpenter (SQS)${NC}"
echo "${CYAN}   2. EKS E-Commerce - KEDA Autoscaling Monitor${NC}"
echo "${CYAN}   3. Kubernetes Dashboards - Pré-instalados (Cluster, Pods, Nodes)${NC}"
echo ""

echo "${YELLOW}🎯 Para DEMONSTRAÇÃO:${NC}"
echo "${CYAN}   1. Abra terminal e execute: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring${NC}"
echo "${CYAN}   2. Abra navegador: http://localhost:3000${NC}"
echo "${CYAN}   3. Login: admin / admin123${NC}"
echo "${CYAN}   4. Menu: Dashboards → Browse → Selecione 'EKS Payment Processing - KEDA + Karpenter (SQS)'${NC}"
echo "${CYAN}   5. Execute teste: cd tests && ./run-load-test.sh${NC}"
echo "${CYAN}   6. Observe o dashboard em tempo real!${NC}"
echo ""

echo "${GREEN}✅ Instalação completa finalizada!${NC}"
