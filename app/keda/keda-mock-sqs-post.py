#!/usr/bin/env python3
"""
KEDA Load Test - SQS Message Sender
Envia mensagens para fila SQS FIFO para testar autoscaling
"""

import boto3
import json
import time
import sys
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Cores para output
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    CYAN = '\033[96m'
    BLUE = '\033[94m'
    RESET = '\033[0m'

def print_color(color, message):
    """Print colored message"""
    print(f"{color}{message}{Colors.RESET}")

def validate_environment():
    """Validate required environment variables"""
    required_vars = ['SQS_QUEUE_URL', 'AWS_REGION']
    missing_vars = []
    
    for var in required_vars:
        if var not in os.environ:
            missing_vars.append(var)
    
    if missing_vars:
        print_color(Colors.RED, f"❌ Erro: Variáveis de ambiente faltando: {', '.join(missing_vars)}")
        print_color(Colors.YELLOW, "Execute: source ../deployment/environmentVariables.sh")
        sys.exit(1)
    
    return os.environ['SQS_QUEUE_URL'], os.environ['AWS_REGION']

def send_message_batch(sqs_client, queue_url, messages):
    """Send batch of messages to SQS"""
    try:
        # SQS batch send aceita até 10 mensagens por vez
        entries = []
        for idx, msg in enumerate(messages):
            entries.append({
                'Id': str(idx),
                'MessageBody': json.dumps(msg),
                'MessageGroupId': 'loadtest-group-1'
            })
        
        response = sqs_client.send_message_batch(
            QueueUrl=queue_url,
            Entries=entries
        )
        
        successful = len(response.get('Successful', []))
        failed = len(response.get('Failed', []))
        
        return successful, failed
    
    except ClientError as e:
        print_color(Colors.RED, f"❌ Erro ao enviar mensagens: {e}")
        return 0, len(messages)

def send_single_message(sqs_client, queue_url, message_body):
    """Send single message to SQS"""
    try:
        response = sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message_body),
            MessageGroupId='loadtest-group-1'
        )
        return True
    except ClientError as e:
        print_color(Colors.RED, f"❌ Erro: {e}")
        return False

def main():
    """Main function"""
    print_color(Colors.GREEN, "╔══════════════════════════════════════════════════════╗")
    print_color(Colors.GREEN, "║       KEDA Load Test - SQS Message Sender           ║")
    print_color(Colors.GREEN, "╚══════════════════════════════════════════════════════╝")
    print()
    
    # Validate environment
    queue_url, region = validate_environment()
    
    print_color(Colors.CYAN, f"📋 Configuração:")
    print_color(Colors.CYAN, f"   • Queue URL: {queue_url}")
    print_color(Colors.CYAN, f"   • Region: {region}")
    print()
    
    # Perguntar quantas mensagens enviar
    print_color(Colors.YELLOW, "Quantas mensagens deseja enviar?")
    print_color(Colors.CYAN, "   • Digite um número (ex: 100, 1000)")
    print_color(Colors.CYAN, "   • Ou 'continuous' para modo contínuo")
    print()
    
    mode = input(f"{Colors.BLUE}Sua escolha: {Colors.RESET}").strip().lower()
    
    # Initialize SQS client
    try:
        sqs_client = boto3.client("sqs", region_name=region)
        print_color(Colors.GREEN, "✅ Cliente SQS inicializado")
    except Exception as e:
        print_color(Colors.RED, f"❌ Erro ao inicializar cliente SQS: {e}")
        sys.exit(1)
    
    print()
    
    if mode == 'continuous':
        # Modo contínuo - 1 mensagem por segundo
        print_color(Colors.GREEN, "🚀 Modo Contínuo Ativado")
        print_color(Colors.YELLOW, "   Enviando 1 mensagem por segundo...")
        print_color(Colors.YELLOW, "   Pressione Ctrl+C para parar")
        print()
        
        count = 0
        try:
            start_time = time.time()
            while True:
                count += 1
                current_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S.%f')
                
                message_body = {
                    'id': f'msg-{count}',  # ID único para DynamoDB
                    'msg': f'Load Test Message #{count}',
                    'timestamp': current_time,
                    'messageId': count,
                    'messageProcessingTime': current_time
                }
                
                if send_single_message(sqs_client, queue_url, message_body):
                    print(f"{Colors.GREEN}✓{Colors.RESET} [{count}] Enviada às {datetime.now().strftime('%H:%M:%S')}")
                else:
                    print_color(Colors.RED, f"✗ [{count}] Falha")
                
                time.sleep(1.0)
                
        except KeyboardInterrupt:
            elapsed = time.time() - start_time
            print()
            print_color(Colors.YELLOW, "⚠️  Interrompido pelo usuário")
            print_color(Colors.CYAN, f"📊 Total enviado: {count} mensagens em {elapsed:.1f}s")
    
    else:
        # Modo batch - enviar quantidade específica
        try:
            total_messages = int(mode)
        except ValueError:
            print_color(Colors.RED, "❌ Entrada inválida! Use um número ou 'continuous'")
            sys.exit(1)
        
        print_color(Colors.GREEN, f"🚀 Enviando {total_messages} mensagens...")
        print()
        
        # Enviar em batches de 10 (limite do SQS)
        batch_size = 10
        total_sent = 0
        total_failed = 0
        
        start_time = time.time()
        
        for batch_num in range(0, total_messages, batch_size):
            batch_messages = []
            batch_count = min(batch_size, total_messages - batch_num)
            
            for i in range(batch_count):
                msg_num = batch_num + i + 1
                current_time = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S.%f')
                
                message_body = {
                    'id': f'msg-{msg_num}',  # ID único para DynamoDB
                    'msg': f'Load Test Message #{msg_num}',
                    'timestamp': current_time,
                    'messageId': msg_num,
                    'messageProcessingTime': current_time
                }
                batch_messages.append(message_body)
            
            # Send batch
            successful, failed = send_message_batch(sqs_client, queue_url, batch_messages)
            total_sent += successful
            total_failed += failed
            
            # Progress
            progress = (total_sent / total_messages) * 100
            print(f"{Colors.CYAN}📤 Progresso: {total_sent}/{total_messages} ({progress:.1f}%) - Batch {batch_num//batch_size + 1}{Colors.RESET}")
            
            # Small delay to avoid throttling
            time.sleep(0.1)
        
        elapsed = time.time() - start_time
        
        print()
        print_color(Colors.GREEN, "╔══════════════════════════════════════════════════════╗")
        print_color(Colors.GREEN, "║              ✅ ENVIO CONCLUÍDO!                     ║")
        print_color(Colors.GREEN, "╚══════════════════════════════════════════════════════╝")
        print()
        print_color(Colors.CYAN, f"📊 Estatísticas:")
        print_color(Colors.GREEN, f"   ✅ Enviadas: {total_sent}")
        if total_failed > 0:
            print_color(Colors.RED, f"   ❌ Falhas: {total_failed}")
        print_color(Colors.CYAN, f"   ⏱️  Tempo: {elapsed:.2f}s")
        print_color(Colors.CYAN, f"   📈 Taxa: {total_sent/elapsed:.1f} msgs/s")
        print()
        
        print_color(Colors.YELLOW, "💡 Próximos passos:")
        print_color(Colors.CYAN, "   1. Monitorar pods: watch kubectl get pods -n keda-test")
        print_color(Colors.CYAN, "   2. Verificar HPA: watch kubectl get hpa -n keda-test")
        print_color(Colors.CYAN, "   3. Verificar nodes: watch kubectl get nodes")
        print()

if __name__ == "__main__":
    main()
