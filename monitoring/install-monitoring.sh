#!/bin/bash
#*************************
# INSTALAÇÃO PROMETHEUS + GRAFANA STACK
# Lab: EKS KEDA + Karpenter v2
#*************************

source $(dirname "$0")/../deployment/environmentVariables.sh

echo "${BLUE}📊 INSTALAÇÃO PROMETHEUS + GRAFANA STACK"
echo "========================================"

# Verificar se kubectl está configurado
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "${RED}❌ Erro: kubectl não está configurado ou cluster não está acessível"
    exit 1
fi

echo "${GREEN}✅ Cluster EKS conectado: ${CLUSTER_NAME}"

# Adicionar repositório Helm
echo ""
echo "${CYAN}📦 Adicionando repositório Prometheus Community..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Criar namespace para monitoring
echo ""
echo "${CYAN}📁 Criando namespace monitoring..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Instalar kube-prometheus-stack
echo ""
echo "${GREEN}🚀 Instalando Prometheus + Grafana via Helm..."
echo "${CYAN}   📦 Chart: kube-prometheus-stack"
echo "${CYAN}   📍 Namespace: monitoring"
echo "${YELLOW}   ⏳ Aguarde, pode levar 2-3 minutos..."

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
  --set grafana.service.type=LoadBalancer \
  --wait --timeout=600s

if [ $? -eq 0 ]; then
    echo ""
    echo "${GREEN}✅ Prometheus + Grafana instalados com sucesso!"
    
    echo ""
    echo "${CYAN}📊 Status dos componentes:"
    kubectl get pods -n monitoring
    
    echo ""
    echo "${CYAN}🌐 Serviços disponíveis:"
    kubectl get svc -n monitoring
    
    echo ""
    echo "${YELLOW}🎯 URLs de Acesso:"
    
    # Grafana LoadBalancer
    echo "${CYAN}   Aguardando LoadBalancer do Grafana..."
    sleep 10
    GRAFANA_LB=$(kubectl get svc -n monitoring monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if [ ! -z "$GRAFANA_LB" ] && [ "$GRAFANA_LB" != "null" ]; then
        echo "${GREEN}   📊 Grafana LoadBalancer: http://$GRAFANA_LB"
    else
        echo "${YELLOW}   📊 Grafana Port-Forward: kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
        echo "${YELLOW}      Acesse: http://localhost:3000"
    fi
    
    echo "${GREEN}      Login: admin / admin123"
    
    # Prometheus
    echo "${YELLOW}   📈 Prometheus: kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
    echo "${YELLOW}      Acesse: http://localhost:9090"
    
    echo ""
    echo "${GREEN}🎉 Stack de Monitoramento Pronto!"
    echo "${CYAN}📋 Próximos passos:"
    echo "${CYAN}   1. ✅ Prometheus coletando métricas do cluster"
    echo "${CYAN}   2. ✅ Grafana com dashboards pré-configurados do Kubernetes"
    echo "${CYAN}   3. 🔄 Execute: ./monitoring/setup-keda-metrics.sh"
    echo "${CYAN}   4. 🎨 Importe os dashboards customizados: ./monitoring/import-dashboards.sh"
    
else
    echo "${RED}❌ Erro na instalação do Prometheus + Grafana"
    echo "${CYAN}📋 Verificar logs:"
    echo "${CYAN}   kubectl get events -n monitoring --sort-by='.lastTimestamp'"
    echo "${CYAN}   kubectl logs -l app.kubernetes.io/name=prometheus -n monitoring"
    exit 1
fi
