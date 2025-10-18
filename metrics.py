"""
Prometheus metrics collection and exposition for Shepherd Configuration Management System.

This module provides comprehensive metrics for monitoring API performance, configuration
operations, database statistics, authentication events, and application health.

Features:
- HTTP request metrics (count, duration, in-progress)
- Configuration metrics (total configs, versions, operations)
- Database metrics (operations, connection pool, document counts)
- Authentication metrics (login attempts, API key usage, active sessions)
- Application metrics (uptime, version info)
- Decorator functions for automatic metric tracking
- Background metric collection for database statistics
- Prometheus exposition format endpoint

Environment Variables:
- METRICS_ENABLED: Enable/disable metrics collection (default: True)
- METRICS_PORT: Port for metrics endpoint (default: same as app)
- METRICS_PATH: Path for metrics endpoint (default: /metrics)
- METRICS_UPDATE_INTERVAL: Seconds between metric updates (default: 60)
"""

import os
import time
import threading
import logging
from functools import wraps
from typing import Optional, Dict, Any, Callable

from flask import Flask, request, g, has_request_context
from prometheus_client import (
    Counter, Histogram, Gauge, Info, 
    CollectorRegistry, generate_latest, 
    CONTENT_TYPE_LATEST, REGISTRY
)


# Global metrics registry
metrics_registry = CollectorRegistry()

# Application info
app_info = Info(
    'app_info', 
    'Application information',
    registry=metrics_registry
)

# Application uptime
app_uptime_seconds = Gauge(
    'app_uptime_seconds',
    'Application uptime in seconds',
    registry=metrics_registry
)

# HTTP Request Metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total number of HTTP requests',
    ['method', 'endpoint', 'status_code'],
    registry=metrics_registry
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency in seconds',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.5, 5.0, 10.0],
    registry=metrics_registry
)

http_requests_in_progress = Gauge(
    'http_requests_in_progress',
    'Number of HTTP requests currently being processed',
    registry=metrics_registry
)

# Configuration Metrics
config_total = Gauge(
    'config_total',
    'Total number of unique configurations',
    ['app_name', 'environment'],
    registry=metrics_registry
)

config_versions_total = Gauge(
    'config_versions_total',
    'Total number of versions per configuration',
    ['config_id'],
    registry=metrics_registry
)

config_operations_total = Counter(
    'config_operations_total',
    'Total configuration operations',
    ['operation', 'status'],
    registry=metrics_registry
)

config_latest_version = Gauge(
    'config_latest_version',
    'Latest version number for each configuration',
    ['config_id'],
    registry=metrics_registry
)

# Database Metrics
mongodb_connection_pool_size = Gauge(
    'mongodb_connection_pool_size',
    'MongoDB connection pool size',
    registry=metrics_registry
)

mongodb_operations_total = Counter(
    'mongodb_operations_total',
    'Total database operations',
    ['operation', 'collection'],
    registry=metrics_registry
)

mongodb_operation_duration_seconds = Histogram(
    'mongodb_operation_duration_seconds',
    'Database operation latency in seconds',
    ['operation', 'collection'],
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0],
    registry=metrics_registry
)

mongodb_documents_total = Gauge(
    'mongodb_documents_total',
    'Total document count per collection',
    ['collection'],
    registry=metrics_registry
)

# Authentication Metrics
auth_attempts_total = Counter(
    'auth_attempts_total',
    'Total authentication attempts',
    ['method', 'status'],
    registry=metrics_registry
)

api_key_usage_total = Counter(
    'api_key_usage_total',
    'Total API key usage',
    ['user', 'endpoint'],
    registry=metrics_registry
)

active_sessions = Gauge(
    'active_sessions',
    'Number of active user sessions',
    registry=metrics_registry
)

# Global variables for metric collection
_metrics_enabled = True
_app_start_time = time.time()
_metric_collector_thread = None
_metric_collector_stop_event = threading.Event()


def setup_metrics(app: Flask) -> None:
    """
    Initialize metrics for Flask application.
    
    Args:
        app: Flask application instance
    """
    global _metrics_enabled, _app_start_time
    
    # Get configuration from environment
    _metrics_enabled = os.getenv('METRICS_ENABLED', 'True').lower() == 'true'
    
    if not _metrics_enabled:
        app.logger.info('Metrics collection disabled')
        return
    
    # Set application info
    try:
        import sys
        app_info.info({
            'version': '1.0.0',  # Should be read from app config or VERSION file
            'python_version': sys.version,
            'flask_env': app.config.get('ENV', 'unknown')
        })
    except Exception as e:
        app.logger.warning(f'Failed to set app info metrics: {e}')
    
    # Initialize uptime tracking
    _app_start_time = time.time()
    
    # Add Flask request hooks for automatic tracking
    app.before_request(_before_request_metrics)
    app.after_request(_after_request_metrics)
    
    # Start background metric collector
    start_metric_collector()
    
    # Register cleanup
    app.teardown_appcontext(_cleanup_metrics)
    
    app.logger.info('Metrics collection initialized')


def _before_request_metrics() -> None:
    """Flask before_request hook for metrics tracking."""
    if not _metrics_enabled:
        return
    
    # Track request start time for duration calculation
    g.metrics_start_time = time.time()
    
    # Increment in-progress requests
    http_requests_in_progress.inc()


def _after_request_metrics(response) -> Any:
    """
    Flask after_request hook for metrics tracking.
    
    Args:
        response: Flask response object
        
    Returns:
        Flask response object (unchanged)
    """
    if not _metrics_enabled:
        return response
    
    try:
        # Calculate request duration
        duration = time.time() - getattr(g, 'metrics_start_time', time.time())
        
        # Get endpoint and method
        endpoint = request.endpoint or 'unknown'
        method = request.method
        status_code = str(response.status_code)
        
        # Update metrics
        http_requests_total.labels(
            method=method,
            endpoint=endpoint,
            status_code=status_code
        ).inc()
        
        http_request_duration_seconds.labels(
            method=method,
            endpoint=endpoint
        ).observe(duration)
        
        # Decrement in-progress requests
        http_requests_in_progress.dec()
        
    except Exception as e:
        # Don't let metrics failures affect request processing
        logging.getLogger('metrics').warning(f'Failed to record request metrics: {e}')
    
    return response


def _cleanup_metrics(error=None) -> None:
    """Cleanup function for metrics on app teardown."""
    stop_metric_collector()


def track_request_metrics(func: Callable) -> Callable:
    """
    Decorator to track request metrics for Flask routes.
    
    Args:
        func: Flask route function
        
    Returns:
        Decorated function with metrics tracking
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        if not _metrics_enabled:
            return func(*args, **kwargs)
        
        start_time = time.time()
        
        try:
            result = func(*args, **kwargs)
            
            # Track successful operation
            if hasattr(result, 'status_code'):
                status = 'success' if result.status_code < 400 else 'error'
            else:
                status = 'success'
            
            return result
            
        except Exception as e:
            # Track failed operation
            status = 'error'
            raise
        
        finally:
            # Record operation metrics if this is a config operation
            try:
                if hasattr(func, '__name__'):
                    if 'create' in func.__name__:
                        config_operations_total.labels(operation='create', status=status).inc()
                    elif 'update' in func.__name__:
                        config_operations_total.labels(operation='update', status=status).inc()
                    elif 'rollback' in func.__name__:
                        config_operations_total.labels(operation='rollback', status=status).inc()
                    elif 'delete' in func.__name__:
                        config_operations_total.labels(operation='delete', status=status).inc()
            except Exception:
                pass  # Don't let metrics failures affect the operation
    
    return wrapper


def track_db_operation(operation: str, collection: str) -> Callable:
    """
    Decorator to track database operation metrics.
    
    Args:
        operation: Database operation type (insert, find, update, delete, aggregate)
        collection: MongoDB collection name
        
    Returns:
        Decorator function
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not _metrics_enabled:
                return func(*args, **kwargs)
            
            start_time = time.time()
            
            try:
                result = func(*args, **kwargs)
                
                # Record successful operation
                mongodb_operations_total.labels(
                    operation=operation,
                    collection=collection
                ).inc()
                
                return result
                
            except Exception as e:
                # Still record the operation attempt
                mongodb_operations_total.labels(
                    operation=operation,
                    collection=collection
                ).inc()
                raise
            
            finally:
                # Record operation duration
                duration = time.time() - start_time
                mongodb_operation_duration_seconds.labels(
                    operation=operation,
                    collection=collection
                ).observe(duration)
        
        return wrapper
    return decorator


def update_config_metrics() -> None:
    """Update configuration-related metrics by querying the database."""
    if not _metrics_enabled:
        return
    
    try:
        # Import here to avoid circular imports
        from database import config_manager
        
        # Get metrics data from database
        metrics_data = config_manager.get_metrics_data()
        
        # Update config total by app_name and environment
        for key, count in metrics_data.get('configs_by_app_env', {}).items():
            app_name, environment = key.split('|', 1)
            config_total.labels(app_name=app_name, environment=environment).set(count)
        
        # Update version counts per config
        for config_id, count in metrics_data.get('versions_per_config', {}).items():
            config_versions_total.labels(config_id=config_id).set(count)
        
        # Update latest versions
        for config_id, version in metrics_data.get('latest_versions', {}).items():
            config_latest_version.labels(config_id=config_id).set(version)
        
    except Exception as e:
        logging.getLogger('metrics').warning(f'Failed to update config metrics: {e}')


def update_db_metrics() -> None:
    """Update database statistics metrics."""
    if not _metrics_enabled:
        return
    
    try:
        # Import here to avoid circular imports
        from database import config_manager
        
        # Update document counts
        collections = ['configurations', 'users']
        for collection_name in collections:
            try:
                count = config_manager.collection.database[collection_name].count_documents({})
                mongodb_documents_total.labels(collection=collection_name).set(count)
            except Exception as e:
                logging.getLogger('metrics').debug(f'Failed to count documents in {collection_name}: {e}')
        
        # Update connection pool stats (if available)
        try:
            # This is a simplified example - actual implementation would depend on PyMongo version
            # and how connection pooling is configured
            pool_size = getattr(config_manager.client, 'max_pool_size', 100)
            mongodb_connection_pool_size.set(pool_size)
        except Exception as e:
            logging.getLogger('metrics').debug(f'Failed to get connection pool stats: {e}')
            
    except Exception as e:
        logging.getLogger('metrics').warning(f'Failed to update database metrics: {e}')


def track_auth_event(method: str, success: bool, username: Optional[str] = None) -> None:
    """
    Track authentication events.
    
    Args:
        method: Authentication method (login, api_key, password_reset)
        success: Whether authentication was successful
        username: Username (optional, for privacy)
    """
    if not _metrics_enabled:
        return
    
    status = 'success' if success else 'failure'
    auth_attempts_total.labels(method=method, status=status).inc()


def track_api_key_usage(username: str, endpoint: str) -> None:
    """
    Track API key usage.
    
    Args:
        username: Username of API key owner
        endpoint: API endpoint being accessed
    """
    if not _metrics_enabled:
        return
    
    api_key_usage_total.labels(user=username, endpoint=endpoint).inc()


def update_active_sessions(count: int) -> None:
    """
    Update active sessions count.
    
    Args:
        count: Current number of active sessions
    """
    if not _metrics_enabled:
        return
    
    active_sessions.set(count)


def start_metric_collector() -> None:
    """Start background thread for periodic metric updates."""
    global _metric_collector_thread
    
    if not _metrics_enabled or _metric_collector_thread is not None:
        return
    
    def metric_collector():
        """Background thread function for collecting metrics."""
        update_interval = int(os.getenv('METRICS_UPDATE_INTERVAL', '60'))
        
        while not _metric_collector_stop_event.wait(update_interval):
            try:
                # Update application uptime
                uptime = time.time() - _app_start_time
                app_uptime_seconds.set(uptime)
                
                # Update config and database metrics
                update_config_metrics()
                update_db_metrics()
                
            except Exception as e:
                logging.getLogger('metrics').warning(f'Error in metric collector: {e}')
    
    _metric_collector_thread = threading.Thread(target=metric_collector, daemon=True)
    _metric_collector_thread.start()
    
    logging.getLogger('metrics').info('Metric collector thread started')


def stop_metric_collector() -> None:
    """Stop background metric collector thread."""
    global _metric_collector_thread
    
    if _metric_collector_thread is None:
        return
    
    _metric_collector_stop_event.set()
    _metric_collector_thread.join(timeout=5)
    _metric_collector_thread = None
    
    logging.getLogger('metrics').info('Metric collector thread stopped')


def metrics_endpoint() -> tuple:
    """
    Generate Prometheus metrics in exposition format.
    
    Returns:
        Tuple of (metrics_text, status_code, headers)
    """
    if not _metrics_enabled:
        return 'Metrics collection disabled\n', 503, {'Content-Type': 'text/plain'}
    
    try:
        # Generate metrics in Prometheus format
        metrics_text = generate_latest(metrics_registry)
        
        return metrics_text, 200, {'Content-Type': CONTENT_TYPE_LATEST}
        
    except Exception as e:
        logging.getLogger('metrics').error(f'Failed to generate metrics: {e}')
        return f'Error generating metrics: {str(e)}\n', 500, {'Content-Type': 'text/plain'}


def get_metrics_summary() -> Dict[str, Any]:
    """
    Get summary of current metrics for debugging/admin purposes.
    
    Returns:
        Dictionary with metric summaries
    """
    if not _metrics_enabled:
        return {'enabled': False}
    
    try:
        from prometheus_client.parser import text_string_to_metric_families
        
        # Get current metrics
        metrics_text = generate_latest(metrics_registry)
        
        # Parse metrics for summary
        summary = {'enabled': True, 'metrics': {}}
        
        for family in text_string_to_metric_families(metrics_text.decode('utf-8')):
            if family.samples:
                summary['metrics'][family.name] = {
                    'type': family.type,
                    'help': family.documentation,
                    'sample_count': len(family.samples)
                }
        
        return summary
        
    except Exception as e:
        return {'enabled': True, 'error': str(e)}


# Custom collector for dynamic metrics (optional)
class ShepherdCustomCollector:
    """
    Custom Prometheus collector for metrics that require database queries.
    
    This collector is called by Prometheus when scraping metrics, allowing
    for real-time metric collection.
    """
    
    def collect(self):
        """
        Collect custom metrics.
        
        Yields:
            Prometheus metric families
        """
        try:
            # Only collect if metrics are enabled
            if not _metrics_enabled:
                return
            
            # Import here to avoid circular imports
            from database import config_manager
            
            # Get real-time config counts
            metrics_data = config_manager.get_metrics_data()
            
            # Example: Total configurations across all apps/environments
            total_configs = sum(metrics_data.get('configs_by_app_env', {}).values())
            
            # Yield custom metric (example)
            # This is just an example - in practice, you might want to expose
            # metrics that can't be easily tracked with standard counters/gauges
            
        except Exception as e:
            # Don't let collector failures break metrics scraping
            logging.getLogger('metrics').debug(f'Custom collector error: {e}')


# Prometheus scrape configuration example (in docstrings)
"""
Prometheus Scrape Configuration:

Add this to your prometheus.yml:

scrape_configs:
  - job_name: 'shepherd'
    static_configs:
      - targets: ['shepherd-app:5000']
    metrics_path: '/metrics'
    scrape_interval: 15s
    scrape_timeout: 10s
    honor_labels: true

# For Kubernetes with ServiceMonitor:
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: shepherd
spec:
  selector:
    matchLabels:
      app: shepherd
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
"""