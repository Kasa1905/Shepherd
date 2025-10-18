"""
Webhook dispatch and event management for Shepherd Configuration Management System.

This module provides HTTP webhook dispatch on configuration create, update, and rollback events,
with retry logic, HMAC signature verification, and async delivery.

Features:
- WebhookConfig dataclass for configuration
- WebhookEvent dataclass for event payloads
- HMAC signature generation and verification
- Async webhook dispatch with retry logic (tenacity)
- WebhookManager for managing subscribers and delivery stats
- Integration helpers for config create/update/rollback
- Test and stats API endpoints

Environment Variables:
- WEBHOOK_ENABLED: Enable/disable webhook dispatch (default: True)
- WEBHOOK_URLS: Comma-separated webhook URLs
- WEBHOOK_SECRET: Shared secret for HMAC signing
- WEBHOOK_EVENTS: Comma-separated event types (default: all)
- WEBHOOK_TIMEOUT: Request timeout (default: 10)
- WEBHOOK_RETRY_ATTEMPTS: Max retries (default: 3)
- WEBHOOK_RETRY_DELAY: Initial retry delay (default: 1)
"""

import os
import json
import uuid
import time
import hmac
import hashlib
import threading
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
import requests

# Webhook configuration dataclass
@dataclass
class WebhookConfig:
    url: str
    events: List[str] = field(default_factory=lambda: ['config.created', 'config.updated', 'config.rolled_back'])
    secret: Optional[str] = None
    enabled: bool = True
    timeout: int = 10
    retry_attempts: int = 3
    retry_delay: int = 1

# Webhook event dataclass
@dataclass
class WebhookEvent:
    event_type: str
    event_id: str
    timestamp: str
    config_id: str
    version: int
    previous_version: Optional[int] = None
    app_name: Optional[str] = None
    environment: Optional[str] = None
    updated_by: Optional[str] = None
    change_notes: Optional[str] = None
    settings: Optional[Dict[str, Any]] = None
    metadata: Optional[Dict[str, Any]] = None

# HMAC signature generation

def generate_signature(payload: str, secret: str) -> str:
    """
    Generate HMAC-SHA256 signature for payload.
    """
    digest = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return f"sha256={digest}"


def verify_signature(payload: str, signature: str, secret: str) -> bool:
    """
    Verify HMAC-SHA256 signature.
    """
    expected = generate_signature(payload, secret)
    return hmac.compare_digest(expected, signature)

# Webhook dispatch

def dispatch_webhook(event: WebhookEvent, webhook_config: WebhookConfig) -> Dict[str, Any]:
    """
    Send webhook HTTP POST request with HMAC signature.
    """
    payload = json.dumps(event.__dict__, sort_keys=True, default=str)
    headers = {
        'Content-Type': 'application/json',
        'X-Shepherd-Event': event.event_type,
        'X-Shepherd-Delivery': event.event_id,
        'User-Agent': 'Shepherd-Webhook/1.0'
    }
    if webhook_config.secret:
        headers['X-Shepherd-Signature'] = generate_signature(payload, webhook_config.secret)
    try:
        response = requests.post(
            webhook_config.url,
            data=payload,
            headers=headers,
            timeout=webhook_config.timeout
        )
        return {
            'status_code': response.status_code,
            'response_text': response.text,
            'success': response.status_code >= 200 and response.status_code < 300
        }
    except Exception as e:
        return {
            'status_code': None,
            'response_text': str(e),
            'success': False
        }

# Async webhook dispatch with retry

def dispatch_webhook_async(event: WebhookEvent, webhook_config: WebhookConfig, webhook_manager=None):
    """
    Dispatch webhook asynchronously with retry logic.
    """
    def _dispatch():
        result = dispatch_with_retry(event, webhook_config)
        
        # Update stats if webhook_manager is provided
        if webhook_manager:
            webhook_manager.stats.setdefault(webhook_config.url, {'success': 0, 'failure': 0})
            if result['success']:
                webhook_manager.stats[webhook_config.url]['success'] += 1
            else:
                webhook_manager.stats[webhook_config.url]['failure'] += 1
        
        # Log result
        logging.getLogger('app.webhook').info(
            f"Webhook dispatched to {webhook_config.url}",
            extra={
                'event_type': event.event_type,
                'config_id': event.config_id,
                'version': event.version,
                'success': result['success'],
                'status_code': result['status_code']
            }
        )
    thread = threading.Thread(target=_dispatch, daemon=True)
    thread.start()

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=60),
    retry=retry_if_exception_type((requests.ConnectionError, requests.Timeout, requests.HTTPError))
)
def dispatch_with_retry(event: WebhookEvent, webhook_config: WebhookConfig) -> Dict[str, Any]:
    """
    Dispatch webhook with retry logic.
    """
    result = dispatch_webhook(event, webhook_config)
    if not result['success'] and (result['status_code'] is None or result['status_code'] >= 500):
        raise requests.ConnectionError(f"Webhook delivery failed: {result['response_text']}")
    return result

# Webhook manager
class WebhookManager:
    def __init__(self):
        self.webhooks: List[WebhookConfig] = self._load_webhooks()
        self.stats: Dict[str, Dict[str, Any]] = {}

    def _load_webhooks(self) -> List[WebhookConfig]:
        urls = os.getenv('WEBHOOK_URLS', '').split(',')
        secret = os.getenv('WEBHOOK_SECRET')
        events = os.getenv('WEBHOOK_EVENTS', 'config.created,config.updated,config.rolled_back').split(',')
        enabled = os.getenv('WEBHOOK_ENABLED', 'True').lower() == 'true'
        timeout = int(os.getenv('WEBHOOK_TIMEOUT', '10'))
        retry_attempts = int(os.getenv('WEBHOOK_RETRY_ATTEMPTS', '3'))
        retry_delay = int(os.getenv('WEBHOOK_RETRY_DELAY', '1'))
        configs = []
        for url in urls:
            url = url.strip()
            if url:
                configs.append(WebhookConfig(
                    url=url,
                    events=events,
                    secret=secret,
                    enabled=enabled,
                    timeout=timeout,
                    retry_attempts=retry_attempts,
                    retry_delay=retry_delay
                ))
        return configs

    def register_webhook(self, webhook_config: WebhookConfig):
        self.webhooks.append(webhook_config)

    def unregister_webhook(self, url: str):
        self.webhooks = [w for w in self.webhooks if w.url != url]

    def dispatch_event(self, event: WebhookEvent):
        for webhook in self.webhooks:
            if webhook.enabled and event.event_type in webhook.events:
                dispatch_webhook_async(event, webhook, self)
                # Initialize stats entry if not exists
                self.stats.setdefault(webhook.url, {'success': 0, 'failure': 0})

    def get_webhook_stats(self):
        return self.stats

# Integration helpers

def trigger_webhook_on_create(config: Dict[str, Any], webhook_manager_instance=None):
    event = WebhookEvent(
        event_type='config.created',
        event_id=str(uuid.uuid4()),
        timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        config_id=config.get('config_id'),
        version=config.get('version'),
        app_name=config.get('app_name'),
        environment=config.get('environment'),
        updated_by=config.get('updated_by'),
        change_notes=config.get('change_notes'),
        settings=config.get('settings'),
        metadata={}
    )
    if webhook_manager_instance:
        webhook_manager_instance.dispatch_event(event)
    elif 'webhook_manager' in globals():
        webhook_manager.dispatch_event(event)


def trigger_webhook_on_update(old_config: Dict[str, Any], new_config: Dict[str, Any], webhook_manager_instance=None):
    event = WebhookEvent(
        event_type='config.updated',
        event_id=str(uuid.uuid4()),
        timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        config_id=new_config.get('config_id'),
        version=new_config.get('version'),
        previous_version=old_config.get('version'),
        app_name=new_config.get('app_name'),
        environment=new_config.get('environment'),
        updated_by=new_config.get('updated_by'),
        change_notes=new_config.get('change_notes'),
        settings=new_config.get('settings'),
        metadata={}
    )
    if webhook_manager_instance:
        webhook_manager_instance.dispatch_event(event)
    elif 'webhook_manager' in globals():
        webhook_manager.dispatch_event(event)


def trigger_webhook_on_rollback(config: Dict[str, Any], target_version: int, webhook_manager_instance=None):
    event = WebhookEvent(
        event_type='config.rolled_back',
        event_id=str(uuid.uuid4()),
        timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        config_id=config.get('config_id'),
        version=config.get('version'),
        previous_version=target_version,
        app_name=config.get('app_name'),
        environment=config.get('environment'),
        updated_by=config.get('updated_by'),
        change_notes=config.get('change_notes'),
        settings=config.get('settings'),
        metadata={}
    )
    if webhook_manager_instance:
        webhook_manager_instance.dispatch_event(event)
    elif 'webhook_manager' in globals():
        webhook_manager.dispatch_event(event)
