#!/bin/bash
#*************************
# CONFIGURAÇÃO MÉTRICAS KEDA
# Habilita ServiceMonitors para Prometheus coletar métricas do KEDA
#*************************

source $(dirname "$0")/../deployment/environmentVariables.sh

echo "${BLUE}📊 CONFIGURAÇÃO DE MÉTRICAS KEDA"
echo "====================================="

# Verificar se KEDA está instalado
if ! kubectl get namespace keda >/dev/null 2>&1; then
    echo "${RED}❌ Erro: Namespace 'keda' não encontrado"
    echo "${YELLOW}Execute primeiro: ./deployment/_main.sh"
    exit 1
fi

# Verificar se Prometheus está instalado
if ! kubectl get namespace monitoring >/dev/null 2>&1; then
    echo "${RED}❌ Erro: Namespace 'monitoring' não encontrado"
    echo "${YELLOW}Execute primeiro: ./monitoring/install-monitoring.sh"
    exit 1
fi

echo "${GREEN}✅ KEDA e Prometheus detectados"

# Criar ServiceMonitor para KEDA Operator
echo ""
echo "${CYAN}🎯 Criando ServiceMonitor para KEDA Operator..."
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: keda-operator
  namespace: monitoring
  labels:
    app: keda-operator
    release: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: keda-operator
  namespaceSelector:
    matchNames:
    - keda
  endpoints:
  - port: metricsservice
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF

# Criar ServiceMonitor para KEDA Metrics Server
echo ""
echo "${CYAN}🎯 Criando ServiceMonitor para KEDA Metrics Server..."
kubectl apply -f - <<EOF
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

# Criar ServiceMonitor para monitorar SQS Reader Pods
echo ""
echo "${CYAN}🎯 Criando ServiceMonitor para SQS Reader Pods (namespace keda-test)..."
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sqs-reader-pods
  namespace: monitoring
  labels:
    app: sqs-reader
    release: monitoring
spec:
  selector:
    matchLabels:
      app: sqs-reader
  namespaceSelector:
    matchNames:
    - keda-test
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
EOF

echo ""
echo "${GREEN}✅ ServiceMonitors criados com sucesso!"

# Verificar se os ServiceMonitors foram criados
echo ""
echo "${CYAN}📋 ServiceMonitors ativos:"
kubectl get servicemonitor -n monitoring | grep -E "keda|sqs"

echo ""
echo "${YELLOW}🔍 Verificando targets no Prometheus..."
echo "${CYAN}   Acesse: http://localhost:9090/targets"
echo "${CYAN}   Procure por: keda-operator, keda-metrics-apiserver"

echo ""
echo "${GREEN}🎉 Configuração de métricas KEDA concluída!"
echo "${CYAN}📋 Próximos passos:"
echo "${CYAN}   1. ✅ Métricas KEDA sendo coletadas"
echo "${CYAN}   2. 🎨 Importe dashboards: ./monitoring/import-dashboards.sh"
echo "${CYAN}   3. 📊 Visualize no Grafana: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
