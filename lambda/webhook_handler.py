"""
OpenClaw Webhook Handler Lambda Function

This Lambda function receives webhooks from external services (Telegram, WhatsApp, etc.)
and forwards them to the OpenClaw gateway running on EC2.

Environment Variables:
    OPENCLAW_HOST: Private IP of the EC2 instance running OpenClaw
    OPENCLAW_PORT: Port number (default: 18789)
    OPENCLAW_TOKEN: Authentication token for OpenClaw gateway
"""

import json
import os
import urllib.request
import urllib.error
from typing import Dict, Any, Optional
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration from environment
OPENCLAW_HOST = os.environ.get('OPENCLAW_HOST', 'localhost')
OPENCLAW_PORT = os.environ.get('OPENCLAW_PORT', '18789')
OPENCLAW_TOKEN = os.environ.get('OPENCLAW_TOKEN', '')


def get_openclaw_url(path: str = '') -> str:
    """Construct OpenClaw gateway URL."""
    return f"http://{OPENCLAW_HOST}:{OPENCLAW_PORT}{path}"


def forward_to_openclaw(
    webhook_data: Dict[str, Any],
    source: str,
    headers: Optional[Dict[str, str]] = None
) -> Dict[str, Any]:
    """
    Forward webhook data to OpenClaw gateway.
    
    Args:
        webhook_data: The webhook payload
        source: Source of the webhook (telegram, whatsapp, etc.)
        headers: Optional additional headers
    
    Returns:
        Response from OpenClaw gateway
    """
    url = get_openclaw_url(f'/webhook/{source}')
    
    # Prepare request
    request_headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {OPENCLAW_TOKEN}',
        'X-Webhook-Source': source
    }
    
    if headers:
        request_headers.update(headers)
    
    # Add metadata to payload
    payload = {
        'webhook_source': source,
        'timestamp': webhook_data.get('timestamp'),
        'data': webhook_data
    }
    
    data = json.dumps(payload).encode('utf-8')
    
    try:
        req = urllib.request.Request(
            url,
            data=data,
            headers=request_headers,
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            response_body = response.read().decode('utf-8')
            return {
                'statusCode': response.status,
                'body': response_body
            }
            
    except urllib.error.HTTPError as e:
        logger.error(f"HTTP Error {e.code}: {e.reason}")
        return {
            'statusCode': e.code,
            'body': json.dumps({
                'error': 'Gateway error',
                'message': str(e.reason)
            })
        }
    except urllib.error.URLError as e:
        logger.error(f"URL Error: {e.reason}")
        return {
            'statusCode': 502,
            'body': json.dumps({
                'error': 'Cannot connect to OpenClaw',
                'message': str(e.reason)
            })
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal error',
                'message': str(e)
            })
        }


def handle_telegram_webhook(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle Telegram bot webhook.
    
    Telegram sends updates in this format:
    {
        "update_id": 123456789,
        "message": {
            "message_id": 1,
            "from": {...},
            "chat": {...},
            "date": 1234567890,
            "text": "Hello"
        }
    }
    """
    body = event.get('body', '{}')
    
    try:
        if isinstance(body, str):
            body = json.loads(body)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in body: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON'})
        }
    
    logger.info(f"Received Telegram webhook: {json.dumps(body)[:200]}...")
    
    # Forward to OpenClaw
    result = forward_to_openclaw(body, 'telegram')
    
    # Telegram expects a 200 OK response quickly
    # Return success even if OpenClaw is temporarily unavailable
    return {
        'statusCode': 200,
        'body': json.dumps({'ok': True})
    }


def handle_whatsapp_webhook(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle WhatsApp webhook (for future implementation).
    
    WhatsApp Business API webhooks have different formats depending on provider
    (Twilio, WhatsApp Business API, etc.)
    """
    body = event.get('body', '{}')
    
    try:
        if isinstance(body, str):
            body = json.loads(body)
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON'})
        }
    
    logger.info(f"Received WhatsApp webhook")
    
    # Forward to OpenClaw
    result = forward_to_openclaw(body, 'whatsapp')
    
    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'received'})
    }


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler.
    
    Args:
        event: Lambda event object
        context: Lambda context object
    
    Returns:
        API Gateway compatible response
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Get path from event
    path = event.get('path', '')
    http_method = event.get('httpMethod', 'POST')
    
    # CORS headers for all responses
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight requests
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({'message': 'OK'})
        }
    
    # Route to appropriate handler based on path
    try:
        if '/webhook/telegram' in path:
            response = handle_telegram_webhook(event)
        elif '/webhook/whatsapp' in path:
            response = handle_whatsapp_webhook(event)
        else:
            response = {
                'statusCode': 404,
                'body': json.dumps({'error': 'Unknown webhook endpoint'})
            }
    except Exception as e:
        logger.error(f"Unhandled exception: {str(e)}", exc_info=True)
        response = {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
    
    # Add CORS headers
    if 'headers' not in response:
        response['headers'] = {}
    response['headers'].update(cors_headers)
    
    return response
