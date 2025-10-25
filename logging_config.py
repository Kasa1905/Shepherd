"""
Structured JSON logging configuration for Shepherd Configuration Management System.

This module provides structured JSON logging with request IDs for distributed tracing,
replacing basic logging with machine-readable JSON format for log aggregation systems.

Features:
- Request ID generation and correlation
- JSON log formatter with custom fields
- Flask integration with before/after request hooks
- Exception logging with full traceback
- Context manager for additional log fields
- Log forwarding guidance for various systems (ELK, Splunk, Datadog, CloudWatch)

Environment Variables:
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- LOG_FORMAT: json or text (default: json)
- LOG_FILE: Optional file path for log output
- LOG_TO_CONSOLE: Boolean to enable console logging (default: True)
- LOG_REQUEST_ID: Include request IDs in logs (default: True)
- LOG_USER_CONTEXT: Include user info in logs (default: True)
"""

import os
import sys
import uuid
import time
import logging
import traceback
from contextlib import contextmanager
from typing import Optional, Dict, Any

from flask import Flask, request, g, has_request_context
from pythonjsonlogger import jsonlogger

# Expose a module-level logger for compatibility with tests
logger = logging.getLogger(__name__)


def generate_request_id() -> str:
    """
    Generate unique request ID using UUID4.

    Returns:
        str: Unique request ID
    """
    return str(uuid.uuid4())


class JSONFormatter(jsonlogger.JsonFormatter):
    """
    Custom JSON formatter that includes request context and user information.

    Extends pythonjsonlogger.JsonFormatter to add:
    - Request ID correlation
    - User context (username, role)
    - HTTP context (method, endpoint, IP)
    - Request duration
    - Exception details with traceback
    """

    def add_fields(
        self,
        log_record: Dict[str, Any],
        record: logging.LogRecord,
        message_dict: Dict[str, Any],
    ) -> None:
        """
        Add custom fields to log record.

        Args:
            log_record: Dictionary to be serialized as JSON
            record: Python logging record
            message_dict: Additional message fields
        """
        super().add_fields(log_record, record, message_dict)

        # Add standard fields
        log_record["timestamp"] = self.formatTime(record)
        log_record["level"] = record.levelname
        log_record["logger"] = record.name

        # Add request context if in Flask request context
        if has_request_context():
            # Request ID correlation
            if hasattr(g, "request_id"):
                log_record["request_id"] = g.request_id

            # HTTP context
            if request:
                log_record["method"] = request.method
                log_record["endpoint"] = request.endpoint or request.path
                log_record["ip_address"] = self._get_client_ip()

                # User context
                if hasattr(g, "user") and g.user:
                    log_record["user"] = g.user.get("username")
                    log_record["user_role"] = g.user.get("role")

                # Request duration (if available)
                if hasattr(g, "request_start_time"):
                    duration_ms = int((time.time() - g.request_start_time) * 1000)
                    log_record["duration_ms"] = duration_ms

        # Add exception info if present
        if record.exc_info:
            log_record["exception"] = {
                "type": record.exc_info[0].__name__,
                "message": str(record.exc_info[1]),
                "traceback": "".join(traceback.format_exception(*record.exc_info)),
            }

        # Add any additional context from log context manager
        if hasattr(g, "log_context"):
            log_record.update(g.log_context)

    def _get_client_ip(self) -> str:
        """Get client IP address, handling proxies."""
        # Check for X-Forwarded-For header (proxy)
        if request.headers.get("X-Forwarded-For"):
            return request.headers.get("X-Forwarded-For").split(",")[0].strip()
        # Check for X-Real-IP header (nginx)
        elif request.headers.get("X-Real-IP"):
            return request.headers.get("X-Real-IP")
        # Fall back to remote_addr
        else:
            return request.remote_addr or "unknown"


def setup_logging(app: Flask) -> None:
    """
    Configure Flask application with structured JSON logging.

    Args:
        app: Flask application instance
    """
    # Get configuration from environment
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()
    log_format = os.getenv("LOG_FORMAT", "json").lower()
    log_file = os.getenv("LOG_FILE")
    log_to_console = os.getenv("LOG_TO_CONSOLE", "True").lower() == "true"

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, log_level))

    # Remove existing handlers
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    # Create formatter
    if log_format == "json":
        formatter = JSONFormatter("%(message)s")
    else:
        # Text format for local development
        formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        )

    # Add console handler
    if log_to_console:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        root_logger.addHandler(console_handler)

    # Add file handler if specified
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)

    # Configure Flask's logger
    app.logger.setLevel(getattr(logging, log_level))

    # Add Flask request hooks
    app.before_request(before_request_logging)
    app.after_request(after_request_logging)

    # Log startup
    app.logger.info(
        "Logging configured",
        extra={
            "log_level": log_level,
            "log_format": log_format,
            "log_to_console": log_to_console,
            "log_file": log_file,
        },
    )


def before_request_logging() -> None:
    """
    Flask before_request hook to initialize request logging context.

    Generates request ID and stores request start time for duration calculation.
    """
    # Generate and store request ID
    g.request_id = generate_request_id()
    g.request_start_time = time.time()

    # Initialize log context
    g.log_context = {}

    # Log incoming request
    req_logger = logging.getLogger("app.request")
    extra_fields = {
        "method": request.method,
        "path": request.path,
        "query_string": request.query_string.decode("utf-8")
        if request.query_string
        else "",
        "user_agent": request.headers.get("User-Agent", ""),
        "content_length": request.content_length,
    }
    req_logger.info("Request started", extra=extra_fields)
    # Also emit via module-level logger for tests that patch logging_config.logger
    try:
        logger.info("Request started", extra=extra_fields)  # type: ignore[name-defined]
    except Exception:
        pass


def after_request_logging(response) -> Any:
    """
    Flask after_request hook to log response details.

    Args:
        response: Flask response object

    Returns:
        Flask response object (unchanged)
    """
    # Calculate request duration
    duration_ms = int((time.time() - g.request_start_time) * 1000)

    # Log response
    req_logger = logging.getLogger("app.request")
    extra_fields = {
        "status_code": response.status_code,
        "response_size": len(response.get_data()) if response.get_data() else 0,
        "duration_ms": duration_ms,
    }
    req_logger.info("Request completed", extra=extra_fields)
    # Also emit via module-level logger for tests
    try:
        if response.status_code >= 400:
            logger.warning("Request completed with error", extra=extra_fields)  # type: ignore[name-defined]
        else:
            logger.info("Request completed", extra=extra_fields)  # type: ignore[name-defined]
    except Exception:
        pass

    # Add request ID to response headers for correlation
    response.headers["X-Request-ID"] = g.request_id

    return response


def log_exception(error: Exception) -> None:
    """
    Log exceptions with full traceback and request context.

    Args:
        error: Exception instance
    """
    logger = logging.getLogger("app.error")
    logger.error(
        f"Exception occurred: {type(error).__name__}: {str(error)}",
        exc_info=True,
        extra={"error_type": type(error).__name__, "error_message": str(error)},
    )


@contextmanager
def log_context(**kwargs):
    """
    Context manager to add temporary fields to log entries.

    Args:
        **kwargs: Key-value pairs to add to log context

    Usage:
        with log_context(config_id='abc', version=2):
            logger.info('Updated config')
    """
    if not has_request_context():
        yield
        return

    # Store original context
    original_context = getattr(g, "log_context", {}).copy()

    # Add new context
    if not hasattr(g, "log_context"):
        g.log_context = {}
    g.log_context.update(kwargs)

    try:
        yield
    finally:
        # Restore original context
        g.log_context = original_context


# Helper functions for application-specific logging


def log_config_operation(
    operation: str, config_id: str, version: Optional[int] = None, **kwargs
) -> None:
    """
    Log configuration operation with structured context.

    Args:
        operation: Type of operation (create, update, rollback, delete)
        config_id: Configuration identifier
        version: Version number (optional)
        **kwargs: Additional context fields
    """
    logger = logging.getLogger("app.config")

    context = {"operation": operation, "config_id": config_id, **kwargs}

    if version is not None:
        context["version"] = version

    with log_context(**context):
        logger.info(f"Configuration {operation}")


def log_database_operation(
    collection: str, operation: str, duration_ms: Optional[int] = None, **kwargs
) -> None:
    """
    Log database operation with timing and context.

    Args:
        collection: MongoDB collection name
        operation: Database operation (insert, find, update, delete, aggregate)
        duration_ms: Operation duration in milliseconds (optional)
        **kwargs: Additional context fields
    """
    logger = logging.getLogger("app.database")

    context = {"collection": collection, "operation": operation, **kwargs}

    if duration_ms is not None:
        context["duration_ms"] = duration_ms

    with log_context(**context):
        logger.debug(f"Database {operation} on {collection}")


def log_webhook_dispatch(
    webhook_url: str, event_type: str, success: bool, attempt: int = 1, **kwargs
) -> None:
    """
    Log webhook dispatch with delivery status.

    Args:
        webhook_url: Webhook URL (domain only for privacy)
        event_type: Type of event being dispatched
        success: Whether delivery was successful
        attempt: Attempt number (for retries)
        **kwargs: Additional context fields
    """
    logger = logging.getLogger("app.webhook")

    # Extract domain from URL for privacy
    try:
        from urllib.parse import urlparse

        webhook_domain = urlparse(webhook_url).netloc
    except Exception:
        webhook_domain = "unknown"

    context = {
        "webhook_domain": webhook_domain,
        "event_type": event_type,
        "success": success,
        "attempt": attempt,
        **kwargs,
    }

    with log_context(**context):
        status = "succeeded" if success else "failed"
        logger.info(f"Webhook delivery {status}")


def log_authentication_event(
    event_type: str, username: Optional[str] = None, success: bool = True, **kwargs
) -> None:
    """
    Log authentication events.

    Args:
        event_type: Type of auth event (login, logout, api_key_use, password_change)
        username: Username (optional)
        success: Whether event was successful
        **kwargs: Additional context fields
    """
    logger = logging.getLogger("app.auth")

    context = {"auth_event": event_type, "success": success, **kwargs}

    if username:
        context["username"] = username

    with log_context(**context):
        status = "succeeded" if success else "failed"
        logger.info(f"Authentication {event_type} {status}")


# Log forwarding guidance (in docstrings)
"""
Log Forwarding Configuration Examples:

1. ELK Stack (Elasticsearch, Logstash, Kibana):
   Use Filebeat to ship JSON logs to Logstash:
   
   filebeat.yml:
   filebeat.inputs:
     - type: log
       enabled: true
       paths:
         - /var/log/shepherd/*.log
       json.keys_under_root: true
       json.add_error_key: true
   
   output.logstash:
     hosts: ["logstash:5044"]

2. Splunk:
   Use Splunk Universal Forwarder or HTTP Event Collector (HEC):
   
   Environment variables:
   SPLUNK_HEC_URL=https://splunk.example.com:8088/services/collector
   SPLUNK_HEC_TOKEN=your-hec-token
   
   Configure JSON source type for automatic field extraction.

3. Datadog:
   Use Datadog Agent with log collection enabled:
   
   datadog.yaml:
   logs_enabled: true
   
   Docker:
   -e DD_LOGS_ENABLED=true
   -e DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true

4. AWS CloudWatch:
   Use awslogs Docker driver:
   
   docker run --log-driver=awslogs \
     --log-opt awslogs-group=shepherd \
     --log-opt awslogs-region=us-east-1 \
     --log-opt awslogs-stream=shepherd-app \
     your-image

5. Google Cloud Logging:
   Use gcplogs Docker driver:
   
   docker run --log-driver=gcplogs \
     --log-opt gcp-project=my-project \
     --log-opt gcp-log-cmd=true \
     your-image
"""
