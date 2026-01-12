#!/usr/bin/env python3
"""
SQS Reader - Consumes messages from SQS and saves to DynamoDB
Exposes Prometheus metrics
"""

import boto3
import json
import os
import time
from datetime import datetime
from prometheus_client import start_http_server, Counter, Gauge
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Prometheus metrics
messages_processed = Counter('sqs_messages_processed_total', 'Total number of SQS messages processed')
messages_failed = Counter('sqs_messages_failed_total', 'Total number of failed message processing')
queue_size = Gauge('sqs_queue_approximate_size', 'Approximate number of messages in queue')
processing_time = Gauge('sqs_message_processing_seconds', 'Time taken to process messages')

# AWS Configuration
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'payments')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

# Initialize AWS clients
sqs = boto3.client('sqs', region_name=AWS_REGION)
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)

def get_queue_size():
    """Get approximate number of messages in queue"""
    try:
        response = sqs.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=['ApproximateNumberOfMessages']
        )
        size = int(response['Attributes']['ApproximateNumberOfMessages'])
        queue_size.set(size)
        return size
    except Exception as e:
        logger.error(f"Error getting queue size: {e}")
        return 0

def process_message(message):
    """Process a single SQS message"""
    try:
        # Parse message body
        body = json.loads(message['Body'])
        
        # Simulate processing time
        time.sleep(0.5)
        
        # Save to DynamoDB
        timestamp = datetime.utcnow().isoformat()
        item = {
            'messageId': message['MessageId'],
            'timestamp': timestamp,
            'data': json.dumps(body),
            'processed': True
        }
        
        table.put_item(Item=item)
        
        # Delete message from queue
        sqs.delete_message(
            QueueUrl=SQS_QUEUE_URL,
            ReceiptHandle=message['ReceiptHandle']
        )
        
        messages_processed.inc()
        logger.info(f"Processed message: {message['MessageId']}")
        return True
        
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        messages_failed.inc()
        return False

def poll_messages():
    """Poll messages from SQS"""
    logger.info(f"Starting to poll messages from queue: {SQS_QUEUE_URL}")
    
    while True:
        try:
            # Get queue size for metrics
            size = get_queue_size()
            logger.info(f"Queue size: {size}")
            
            # Receive messages
            start_time = time.time()
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=10,
                VisibilityTimeout=60
            )
            
            messages = response.get('Messages', [])
            
            if messages:
                logger.info(f"Received {len(messages)} messages")
                for message in messages:
                    process_message(message)
                
                processing_time.set(time.time() - start_time)
            else:
                logger.info("No messages received, waiting...")
                time.sleep(5)
                
        except Exception as e:
            logger.error(f"Error in polling loop: {e}")
            time.sleep(5)

def main():
    """Main function"""
    # Validate environment
    if not SQS_QUEUE_URL:
        logger.error("SQS_QUEUE_URL environment variable not set")
        exit(1)
    
    logger.info("Starting SQS Reader...")
    logger.info(f"Queue URL: {SQS_QUEUE_URL}")
    logger.info(f"DynamoDB Table: {DYNAMODB_TABLE}")
    logger.info(f"Region: {AWS_REGION}")
    
    # Start Prometheus metrics server
    start_http_server(8000)
    logger.info("Metrics server started on port 8000")
    
    # Start polling
    poll_messages()

if __name__ == '__main__':
    main()
