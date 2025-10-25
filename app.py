"""
Flask REST API for Shepherd Configuration Management System.

This module provides RESTful JSON API endpoints for configuration management,
utilizing the database layer from database.py for all CRUD operations with
versioning support.
"""

import os
import logging
import json
import time
import uuid
from flask import Flask, request, jsonify, render_template, redirect, url_for, flash, session, g
from flask_cors import CORS
from database import config_manager, user_manager
from auth import (
    require_api_key, require_login, require_role,
    hash_password, verify_password, generate_api_key,
    login_user, logout_user, get_current_user,
    create_default_admin
)
from logging_config import setup_logging
from metrics import setup_metrics, metrics_endpoint, track_request_metrics, update_config_metrics
from webhooks import WebhookManager, WebhookEvent, trigger_webhook_on_create, trigger_webhook_on_update, trigger_webhook_on_rollback

# Initialize Flask application
app = Flask(__name__)

# Setup structured JSON logging
setup_logging(app)
logger = logging.getLogger(__name__)

# Setup Prometheus metrics
setup_metrics(app)

# Initialize webhook manager
webhook_manager = WebhookManager()

# Enable CORS for frontend development
CORS(app)

# Configure Flask from environment variables
app.config['DEBUG'] = os.getenv('FLASK_DEBUG', 'True').lower() == 'true'
app.config['ENV'] = os.getenv('FLASK_ENV', 'development')
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')


# Authentication initialization
# Flask 2.3+ removed before_first_request; perform one-time init on first request instead.
app.config.setdefault('AUTH_INIT_DONE', False)

def initialize_auth():
    """Initialize authentication system with default admin user."""
    if app.config.get('AUTH_INIT_DONE'):
        return
    try:
        create_default_admin()
        logger.info("Authentication system initialized")
        app.config['AUTH_INIT_DONE'] = True
    except Exception as e:
        logger.error(f"Failed to initialize authentication: {e}")


@app.before_request
def before_request():
    """One-time auth init and load user before each request."""
    if not app.config.get('AUTH_INIT_DONE'):
        initialize_auth()
    g.user = get_current_user()


# Input Validation Helpers
def validate_config_payload(data):
    """
    Validate configuration creation payload.
    
    Args:
        data: JSON payload from request
        
    Returns:
        tuple: (is_valid: bool, error_message: str)
    """
    if not isinstance(data, dict):
        return False, "Request body must be a JSON object"
    
    required_fields = ['config_id', 'app_name', 'environment', 'settings']
    
    for field in required_fields:
        if field not in data:
            return False, f"Missing required field: {field}"
        
        if not isinstance(data[field], str) and field != 'settings':
            return False, f"Field '{field}' must be a string"
    
    # Validate settings is a dictionary
    if not isinstance(data['settings'], dict):
        return False, "Field 'settings' must be a JSON object"
    
    # Check for empty strings
    string_fields = ['config_id', 'app_name', 'environment']
    for field in string_fields:
        if not data[field].strip():
            return False, f"Field '{field}' cannot be empty"
    
    return True, None


def validate_update_payload(data):
    """
    Validate configuration update payload.
    
    Args:
        data: JSON payload from request
        
    Returns:
        tuple: (is_valid: bool, error_message: str)
    """
    if not isinstance(data, dict):
        return False, "Request body must be a JSON object"
    
    if 'settings' not in data:
        return False, "Missing required field: settings"
    
    if not isinstance(data['settings'], dict):
        return False, "Field 'settings' must be a JSON object"
    
    return True, None


def get_schema_templates():
    """
    Get common configuration schema templates for the create form.
    
    Returns:
        Dictionary of schema templates with examples
    """
    return {
        "database": {
            "name": "database",
            "description": "Relational database connection and pool settings",
            "host": "localhost",
            "port": 5432,
            "database": "myapp",
            "username": "dbuser",
            "password": "${DB_PASSWORD}",
            "pool_size": 10,
            "timeout": 30,
            "ssl_mode": "require"
        },
        "api_service": {
            "name": "api_service",
            "description": "External API service configuration",
            "base_url": "https://api.example.com",
            "timeout": 30,
            "retry_attempts": 3,
            "retry_delay": 1,
            "auth": {
                "type": "bearer",
                "token": "${API_TOKEN}"
            },
            "rate_limit": {
                "requests_per_minute": 100
            }
        },
        "feature_flags": {
            "name": "feature_flags",
            "description": "Feature toggles and rollout settings",
            "enable_new_ui": True,
            "beta_features": False,
            "maintenance_mode": False,
            "max_users": 1000,
            "feature_rollout_percentage": 50
        },
        "cache": {
            "name": "cache",
            "description": "Caching backend and TTL configuration",
            "type": "redis",
            "host": "localhost",
            "port": 6379,
            "database": 0,
            "ttl": 3600,
            "max_memory": "256mb",
            "eviction_policy": "allkeys-lru"
        },
        "logging": {
            "name": "logging",
            "description": "Application logging configuration",
            "level": "INFO",
            "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            "handlers": {
                "console": True,
                "file": {
                    "enabled": True,
                    "path": "/var/log/app.log",
                    "max_size": "10MB",
                    "backup_count": 5
                }
            }
        }
    }


# API Endpoints

@app.route('/')
@require_login
def dashboard():
    """
    Dashboard route - display all configurations.
    """
    try:
        # Get all latest configurations
        configs = config_manager.query_configs()
        
        # Sort by config_id for consistent display
        configs.sort(key=lambda x: x['config_id'])
        
        logger.info(f"Dashboard loaded with {len(configs)} configurations")
        return render_template('dashboard.html', configs=configs)
        
    except Exception as e:
        logger.error(f"Error loading dashboard: {e}")
        return render_template('dashboard.html', configs=[], error=str(e))


@app.route('/create', methods=['GET', 'POST'])
@require_role('editor')
def create_config_ui():
    """
    Create configuration route - GET shows form, POST processes creation.
    """
    if request.method == 'GET':
        schema_templates = get_schema_templates()
        try:
            uname = (g.user or {}).get('username') if hasattr(g, 'user') else None
        except Exception:
            uname = None
        logger.info(f"User {uname or 'anonymous'} opened create config form")
        return render_template('create.html', schema_templates=schema_templates)
    
    # Handle POST request
    try:
        # Extract form fields
        config_id = request.form.get('config_id', '').strip()
        app_name = request.form.get('app_name', '').strip()
        environment = request.form.get('environment', '').strip()
        settings_json = request.form.get('settings', '').strip()
        change_notes = request.form.get('change_notes', '').strip()
        
        # Validate required fields
        if not config_id or not app_name or not environment or not settings_json:
            flash('All required fields must be filled', 'error')
            return render_template('create.html', 
                                 schema_templates=get_schema_templates(),
                                 form_data=request.form)
        
        # Parse settings JSON
        try:
            settings = json.loads(settings_json)
        except json.JSONDecodeError as e:
            flash(f'Invalid JSON in settings: {str(e)}', 'error')
            return render_template('create.html', 
                                 schema_templates=get_schema_templates(),
                                 form_data=request.form)
        
        # Build config data
        config_data = {
            'config_id': config_id,
            'app_name': app_name,
            'environment': environment,
            'settings': settings
        }
        
        # Create configuration with metadata
        updated_by = g.user['username'] if g.user else 'anonymous'
        config_manager.create_config(
            config_data, 
            updated_by=updated_by, 
            change_notes=change_notes
        )
        
        flash(f'Configuration "{config_id}" created successfully!', 'success')
        logger.info(f"User {updated_by} created config {config_id}")
        return redirect(url_for('view_config', config_id=config_id))
        
    except ValueError as e:
        flash(str(e), 'error')
        return render_template('create.html', 
                             schema_templates=get_schema_templates(),
                             form_data=request.form)
    except Exception as e:
        logger.error(f"Error creating configuration: {e}")
        flash('An error occurred while creating the configuration', 'error')
        return render_template('create.html', 
                             schema_templates=get_schema_templates(),
                             form_data=request.form)


@app.route('/config/<config_id>')
@require_login
def view_config(config_id):
    """
    View configuration details.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get latest configuration
        config = config_manager.get_latest_config(config_id)
        
        if config is None:
            flash(f"Configuration '{config_id}' not found", 'error')
            return redirect(url_for('dashboard'))
        
        # Format settings JSON for display
        settings_json = json.dumps(config['settings'], indent=4)
        
        logger.info(f"Viewed configuration details: {config_id}")
        return render_template('details.html', config=config, settings_json=settings_json)
        
    except Exception as e:
        logger.error(f"Error viewing configuration: {e}")
        flash(f"Error loading configuration: {str(e)}", 'error')
        return redirect(url_for('dashboard'))


@app.route('/edit/<config_id>', methods=['GET'])
@require_role('editor')
def edit_config(config_id):
    """
    Display edit form for configuration.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get latest configuration
        config = config_manager.get_latest_config(config_id)
        
        if config is None:
            flash(f"Configuration '{config_id}' not found", 'error')
            return redirect(url_for('dashboard'))
        
        # Format settings JSON for textarea
        settings_json = json.dumps(config['settings'], indent=4)
        
        logger.info(f"Opened edit form for configuration: {config_id}")
        return render_template('edit.html', config=config, settings_json=settings_json)
        
    except Exception as e:
        logger.error(f"Error loading edit form: {e}")
        flash(f"Error loading edit form: {str(e)}", 'error')
        return redirect(url_for('dashboard'))


@app.route('/edit/<config_id>', methods=['POST'])
@require_role('editor')
def update_config(config_id):
    """
    Submit configuration update.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get form data
        settings_json_str = request.form.get('settings', '').strip()
        change_notes = request.form.get('change_notes', '').strip()
        
        if not settings_json_str:
            flash('Settings cannot be empty', 'error')
            return redirect(url_for('edit_config_form', config_id=config_id))
        
        # Parse JSON
        try:
            parsed_settings = json.loads(settings_json_str)
        except json.JSONDecodeError as e:
            flash(f'Invalid JSON format: {str(e)}', 'error')
            # Re-render form with error
            config = config_manager.get_latest_config(config_id)
            return render_template('edit.html', 
                                 config=config, 
                                 settings_json=settings_json_str,
                                 error=f'Invalid JSON format: {str(e)}')
        
        # Update configuration with metadata
        updated_config = config_manager.update_config(
            config_id, 
            parsed_settings, 
            updated_by=g.user['username'], 
            change_notes=change_notes
        )
        
        # Create flash message with change notes if provided
        message = f'Configuration updated successfully! New version: {updated_config["version"]}'
        if change_notes:
            message += f' - {change_notes}'
        flash(message, 'success')
        logger.info(f"Updated configuration: {config_id} (new version: {updated_config['version']})")
        return redirect(url_for('view_config', config_id=config_id))
        
    except ValueError as e:
        # Configuration not found
        flash(f'Configuration not found: {str(e)}', 'error')
        return redirect(url_for('dashboard'))
        
    except Exception as e:
        logger.error(f"Error updating configuration: {e}")
        flash(f'Error updating configuration: {str(e)}', 'error')
        return redirect(url_for('edit_config_form', config_id=config_id))


@app.route('/history/<config_id>')
@require_login
def config_history(config_id):
    """
    View configuration version history.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get configuration history
        versions = config_manager.get_config_history(config_id)
        
        logger.info(f"Viewed configuration history: {config_id} ({len(versions)} versions)")
        return render_template('history.html', config_id=config_id, versions=versions)
        
    except Exception as e:
        logger.error(f"Error retrieving configuration history: {e}")
        flash(f"Error loading version history: {str(e)}", 'error')
        return redirect(url_for('dashboard'))


@app.route('/compare/<config_id>/<int:version1>/<int:version2>')
@require_login
def compare_versions(config_id, version1, version2):
    """
    Compare two versions of a configuration.
    
    Args:
        config_id: Unique identifier for the configuration
        version1: First version number
        version2: Second version number
    """
    try:
        # Ensure version1 < version2 for consistent display
        if version1 > version2:
            version1, version2 = version2, version1
        
        # Retrieve both versions
        config_v1 = config_manager.get_config_version(config_id, version1)
        config_v2 = config_manager.get_config_version(config_id, version2)
        
        if not config_v1:
            flash(f'Version {version1} not found', 'error')
            return redirect(url_for('config_history', config_id=config_id))
        
        if not config_v2:
            flash(f'Version {version2} not found', 'error')
            return redirect(url_for('config_history', config_id=config_id))
        
        logger.info(f"Comparing {config_id} versions {version1} vs {version2}")
        return render_template('compare.html', 
                             config_id=config_id, 
                             version1=config_v1, 
                             version2=config_v2)
        
    except Exception as e:
        logger.error(f"Error comparing versions: {e}")
        flash('Error loading version comparison', 'error')
        return redirect(url_for('config_history', config_id=config_id))


@app.route('/rollback/<config_id>/<int:target_version>', methods=['POST'])
@require_role('editor')
def rollback_config(config_id, target_version):
    """
    Rollback configuration to a previous version.
    
    Args:
        config_id: Unique identifier for the configuration
        target_version: Version number to rollback to
    """
    try:
        # Extract change notes from form
        change_notes = request.form.get('change_notes', '').strip()
        if not change_notes:
            change_notes = f"Rolled back to version {target_version}"
        
        # Determine updater identity safely in tests or anonymous contexts
        updated_by = (g.user.get('username') if isinstance(g.user, dict) and 'username' in g.user else 'test-user')
        # Perform rollback
        new_config = config_manager.rollback_config(
            config_id, 
            target_version, 
            updated_by=updated_by, 
            change_notes=change_notes
        )
        
        flash(f'Successfully rolled back to version {target_version}. Created new version {new_config["version"]}.', 'success')
        logger.info(f"User {updated_by} rolled back {config_id} to version {target_version}")
        return redirect(url_for('view_config', config_id=config_id))
        
    except ValueError as e:
        flash(str(e), 'error')
        return redirect(url_for('config_history', config_id=config_id))
    except Exception as e:
        logger.error(f"Error rolling back configuration: {e}")
        flash('An error occurred during rollback', 'error')
        return redirect(url_for('config_history', config_id=config_id))


@app.route('/api/config', methods=['POST'])
@require_api_key
@require_role('editor')
@track_request_metrics
def create_config():
    """
    Create a new configuration with version 1.
    
    Expected JSON payload:
    {
        "config_id": "string",
        "app_name": "string", 
        "environment": "string",
        "settings": {"key": "value", ...},
        "change_notes": "string (optional)"
    }
    """
    try:
        # Validate JSON content type
        if not request.is_json:
            return jsonify({
                "error": "Content-Type must be application/json",
                "status": 400
            }), 400
        
        try:
            data = request.get_json()
        except Exception:
            return jsonify({
                "error": "Invalid JSON payload",
                "status": 400
            }), 400
        
        # Backward/alternate payload support
        if 'settings' not in data and 'data' in data:
            data['settings'] = data.get('data')
        
        # Validate payload
        is_valid, error_message = validate_config_payload(data)
        if not is_valid:
            return jsonify({
                "error": error_message,
                "status": 400
            }), 400
        
        # Create configuration using database manager with metadata
        updated_by = data.get('updated_by') or (g.user['username'] if g.user else None)
        change_notes = data.get('change_notes', '')
        result = config_manager.create_config(data, updated_by=updated_by, change_notes=change_notes)
        
        # Trigger webhook on successful creation
        trigger_webhook_on_create(result, webhook_manager)
        
        # Update config metrics
        update_config_metrics()
        
        logger.info(f"Created configuration: {data['config_id']}")
        return jsonify(result), 201
        
    except ValueError as e:
        # Handle duplicate config_id or validation errors
        logger.warning(f"Configuration creation failed: {e}")
        return jsonify({
            "error": str(e),
            "status": 400
        }), 400

    except RuntimeError as e:
        # Database layer can raise RuntimeError for duplicates
        error_msg = str(e)
        if 'already exists' in error_msg:
            logger.warning(f"Configuration creation failed: {e}")
            return jsonify({
                "error": error_msg,
                "status": 400
            }), 400
        # Otherwise, treat as internal server error
        logger.error(f"Unexpected error creating configuration: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error creating configuration: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/<config_id>', methods=['GET'])
@require_api_key
@track_request_metrics
def get_latest_configuration(config_id):
    """
    Retrieve the latest version of a configuration.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get latest configuration
        result = config_manager.get_latest_config(config_id)
        
        if result is None:
            return jsonify({
                "error": f"Configuration with config_id '{config_id}' not found",
                "status": 404
            }), 404
        
        logger.info(f"Retrieved latest configuration: {config_id}")
        return jsonify(result), 200
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error retrieving configuration: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/<config_id>', methods=['PUT'])
@require_api_key
@require_role('editor')
@track_request_metrics
def update_configuration(config_id):
    """
    Update a configuration by creating a new version.
    
    Args:
        config_id: Unique identifier for the configuration
        
    Expected JSON payload:
    {
        "settings": {"key": "value", ...},
        "change_notes": "string (optional)"
    }
    """
    try:
        # Validate JSON content type
        if not request.is_json:
            return jsonify({
                "error": "Content-Type must be application/json",
                "status": 400
            }), 400
        
        try:
            data = request.get_json()
        except Exception:
            return jsonify({
                "error": "Invalid JSON payload",
                "status": 400
            }), 400
        
        # Validate payload
        is_valid, error_message = validate_update_payload(data)
        if not is_valid:
            return jsonify({
                "error": error_message,
                "status": 400
            }), 400
        
        # Update configuration using database manager with metadata
        updated_by = data.get('updated_by') or (g.user['username'] if g.user else None)
        change_notes = data.get('change_notes', '')
        
        # Get old config for webhook trigger
        old_config = config_manager.get_latest_config(config_id)
        result = config_manager.update_config(config_id, data['settings'], updated_by=updated_by, change_notes=change_notes)
        
        # Trigger webhook on successful update
        trigger_webhook_on_update(old_config, result, webhook_manager)
        
        # Update config metrics
        update_config_metrics()
        
        logger.info(f"Updated configuration: {config_id} (new version: {result['version']})")
        return jsonify(result), 200
        
    except ValueError as e:
        # Handle config not found errors
        logger.warning(f"Configuration update failed: {e}")
        return jsonify({
            "error": str(e),
            "status": 404
        }), 404
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error updating configuration: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/history/<config_id>', methods=['GET'])
@require_api_key
def get_configuration_history(config_id):
    """
    Retrieve all versions of a configuration, sorted by version descending.
    
    Args:
        config_id: Unique identifier for the configuration
    """
    try:
        # Get configuration history
        result = config_manager.get_config_history(config_id)
        
        logger.info(f"Retrieved configuration history: {config_id} ({len(result)} versions)")
        return jsonify(result), 200
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error retrieving configuration history: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/query', methods=['GET'])
@require_api_key
@track_request_metrics
def query_configurations():
    """
    Query configurations by app_name and/or environment, returning latest versions only.
    
    Query parameters:
        app or app_name: Filter by application name (optional)
        env or environment: Filter by environment (optional)
    """
    try:
        # Extract query parameters with flexible naming
        app_name = request.args.get('app') or request.args.get('app_name')
        environment = request.args.get('env') or request.args.get('environment')
        
        # Query configurations using database manager
        result = config_manager.query_configs(app_name, environment)
        
        logger.info(f"Queried configurations: app_name={app_name}, environment={environment} ({len(result)} results)")
        return jsonify(result), 200
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error querying configurations: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/<config_id>/version/<int:version>', methods=['GET'])
@require_api_key
def get_config_version(config_id, version):
    """
    Get a specific version of a configuration.
    
    Args:
        config_id: Unique identifier for the configuration
        version: Version number to retrieve
    """
    try:
        # Get specific version
        result = config_manager.get_config_version(config_id, version)
        
        if not result:
            return jsonify({
                "error": "Configuration version not found",
                "status": 404
            }), 404
        
        logger.info(f"Retrieved configuration version: {config_id} v{version}")
        return jsonify(result), 200
        
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error retrieving configuration version: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


@app.route('/api/config/<config_id>/rollback/<int:target_version>', methods=['POST'])
@require_api_key
@require_role('editor')
@track_request_metrics
def rollback_config_api(config_id, target_version):
    """
    Rollback a configuration to a previous version via API.
    
    Args:
        config_id: Unique identifier for the configuration
        target_version: Version number to rollback to
    """
    try:
        # Validate JSON content type
        if not request.is_json:
            return jsonify({
                "error": "Content-Type must be application/json",
                "status": 400
            }), 400
        
        try:
            data = request.get_json()
        except Exception:
            return jsonify({
                "error": "Invalid JSON payload",
                "status": 400
            }), 400
        
        # Extract metadata
        updated_by = data.get('updated_by', g.user.get('username', 'api_user'))
        change_notes = data.get('change_notes', f'Rolled back to version {target_version} via API')
        
        # Perform rollback
        result = config_manager.rollback_config(config_id, target_version, updated_by, change_notes)
        
        if not result:
            return jsonify({
                "error": "Configuration or target version not found",
                "status": 404
            }), 404
        
        # Trigger webhook on successful rollback
        trigger_webhook_on_rollback(result, target_version, webhook_manager)
        
        # Update config metrics
        update_config_metrics()
        
        logger.info(f"Rolled back configuration via API: {config_id} to version {target_version} by {updated_by}")
        return jsonify(result), 200
        
    except ValueError as e:
        return jsonify({
            "error": str(e),
            "status": 400
        }), 400
    except Exception as e:
        # Handle unexpected server errors
        logger.error(f"Unexpected error during API rollback: {e}")
        return jsonify({
            "error": "Internal server error",
            "status": 500
        }), 500


# Error Handlers

@app.errorhandler(400)
def bad_request_error(error):
    """Handle 400 Bad Request errors."""
    # Check if this is a web UI request
    if request.path.startswith('/api/'):
        return jsonify({
            "error": "Bad Request",
            "status": 400
        }), 400
    else:
        flash("Bad Request", 'error')
        return redirect(url_for('dashboard'))


@app.errorhandler(404)
def not_found_error(error):
    """Handle 404 Not Found errors."""
    # Check if this is a web UI request
    if request.path.startswith('/api/'):
        return jsonify({
            "error": "Not Found",
            "status": 404
        }), 404
    else:
        flash("Page not found", 'error')
        return redirect(url_for('dashboard'))


@app.errorhandler(500)
def internal_server_error(error):
    """Handle 500 Internal Server Error."""
    # Check if this is a web UI request
    if request.path.startswith('/api/'):
        return jsonify({
            "error": "Internal Server Error",
            "status": 500
        }), 500
    else:
        flash("Internal server error occurred", 'error')
        return redirect(url_for('dashboard'))


# Authentication Routes

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login route for web interface."""
    if request.method == 'GET':
        # If already logged in, redirect to dashboard
        if g.user:
            return redirect(url_for('dashboard'))
        return render_template('login.html')
    
    # Handle POST request
    try:
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        
        if not username or not password:
            flash('Username and password are required', 'error')
            return render_template('login.html'), 400
        
        # Get user from database
        user = user_manager.get_user_by_username(username)
        if not user or not verify_password(password, user['password_hash']):
            flash('Invalid username or password', 'error')
            return render_template('login.html'), 401
        
        # Login user (sets session)
        login_user(user)
        flash(f'Welcome back, {username}!', 'success')
        
        # Redirect to next page or dashboard
        next_page = request.args.get('next')
        if next_page:
            return redirect(next_page)
        return redirect(url_for('dashboard'))
        
    except Exception as e:
        logger.error(f"Login error: {e}")
        flash('An error occurred during login', 'error')
        return render_template('login.html'), 500


@app.route('/logout')
def logout():
    """Logout route for web interface."""
    try:
        logout_user()
        flash('You have been logged out successfully', 'info')
        return redirect(url_for('login'))
        
    except Exception as e:
        logger.error(f"Logout error: {e}")
        flash('An error occurred during logout', 'error')
        return redirect(url_for('dashboard'))


@app.route('/profile')
@require_login
def profile():
    """User profile page."""
    try:
        return render_template('profile.html', user=g.user)
        
    except Exception as e:
        logger.error(f"Profile error: {e}")
        flash('An error occurred loading your profile', 'error')
        return redirect(url_for('dashboard'))


@app.route('/profile/regenerate-api-key', methods=['POST'])
@require_login
def regenerate_api_key():
    """Regenerate user's API key."""
    try:
        new_api_key = generate_api_key()
        updated_user = user_manager.regenerate_api_key(g.user['username'], new_api_key)
        
        # Update session with new user data
        session['user'] = updated_user
        g.user = updated_user
        
        flash('API key regenerated successfully', 'success')
        return redirect(url_for('profile'))
        
    except Exception as e:
        logger.error(f"API key regeneration error: {e}")
        flash('Failed to regenerate API key', 'error')
        return redirect(url_for('profile'))


@app.route('/profile/change-password', methods=['POST'])
@require_login
def change_password():
    """Change user password."""
    try:
        current_password = request.form.get('current_password', '')
        new_password = request.form.get('new_password', '')
        confirm_password = request.form.get('confirm_password', '')
        
        if not current_password or not new_password or not confirm_password:
            flash('All password fields are required', 'error')
            return redirect(url_for('profile'))
        
        if new_password != confirm_password:
            flash('New passwords do not match', 'error')
            return redirect(url_for('profile'))
        
        if len(new_password) < 8:
            flash('Password must be at least 8 characters long', 'error')
            return redirect(url_for('profile'))
        
        # Verify current password
        user = user_manager.get_user_by_username(g.user['username'])
        if not verify_password(current_password, user['password_hash']):
            flash('Current password is incorrect', 'error')
            return redirect(url_for('profile'))
        
        # Update password
        new_password_hash = hash_password(new_password)
        user_manager.update_user_password(g.user['username'], new_password_hash)
        
        flash('Password changed successfully', 'success')
        return redirect(url_for('profile'))
        
    except Exception as e:
        logger.error(f"Password change error: {e}")
        flash('Failed to change password', 'error')
        return redirect(url_for('profile'))


# Admin Routes

@app.route('/admin/users')
@require_role('admin')
def admin_users():
    """Admin page to manage users."""
    try:
        users = user_manager.list_users()
        return render_template('admin_users.html', users=users)
        
    except Exception as e:
        logger.error(f"Admin users error: {e}")
        flash('Failed to load users', 'error')
        return redirect(url_for('dashboard'))


@app.route('/admin/create-user', methods=['POST'])
@require_role('admin')
def admin_create_user():
    """Admin route to create new user."""
    try:
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        role = request.form.get('role', '')
        
        if not username or not password or not role:
            flash('Username, password, and role are required', 'error')
            return redirect(url_for('admin_users'))
        
        if role not in ['viewer', 'editor', 'admin']:
            flash('Invalid role selected', 'error')
            return redirect(url_for('admin_users'))
        
        if len(password) < 8:
            flash('Password must be at least 8 characters long', 'error')
            return redirect(url_for('admin_users'))
        
        # Create user
        password_hash = hash_password(password)
        api_key = generate_api_key()
        
        user_manager.create_user(username, password_hash, role, api_key)
        flash(f'User {username} created successfully with role {role}', 'success')
        
        return redirect(url_for('admin_users'))
        
    except ValueError as e:
        flash(str(e), 'error')
        return redirect(url_for('admin_users'))
    except Exception as e:
        logger.error(f"User creation error: {e}")
        flash('Failed to create user', 'error')
        return redirect(url_for('admin_users'))


@app.route('/admin/delete-user/<username>', methods=['POST'])
@require_role('admin')
def admin_delete_user(username):
    """Admin route to delete user."""
    try:
        if username == 'admin':
            flash('Cannot delete the admin user', 'error')
            return redirect(url_for('admin_users'))
        
        if username == g.user['username']:
            flash('Cannot delete your own account', 'error')
            return redirect(url_for('admin_users'))
        
        deleted_count = user_manager.delete_user(username)
        if deleted_count > 0:
            flash(f'User {username} deleted successfully', 'success')
        else:
            flash(f'User {username} not found', 'error')
        
        return redirect(url_for('admin_users'))
        
    except Exception as e:
        logger.error(f"User deletion error: {e}")
        flash('Failed to delete user', 'error')
        return redirect(url_for('admin_users'))


@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint for monitoring."""
    try:
        # Test database connection
        stats = config_manager.get_database_stats()
        
        return jsonify({
            "status": "healthy",
            "database": "connected",
            "stats": stats
        }), 200
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e)
        }), 503



# Webhook Admin API Routes

@app.route('/api/webhooks', methods=['GET'])
@require_api_key
@require_role('admin')
def list_webhooks():
    """List all configured webhooks (sans secrets)."""
    webhooks = []
    for webhook in webhook_manager.webhooks:
        webhook_data = {
            'url': webhook.url,
            'events': webhook.events,
            'enabled': webhook.enabled,
            'timeout': webhook.timeout,
            'retry_attempts': webhook.retry_attempts,
            'retry_delay': webhook.retry_delay
            # Secret is intentionally omitted for security
        }
        webhooks.append(webhook_data)
    return jsonify({'webhooks': webhooks}), 200


@app.route('/api/webhooks/test', methods=['POST'])
@require_api_key
@require_role('admin')
def test_webhook():
    """Send a test webhook event."""
    try:
        data = request.get_json()
        test_event = WebhookEvent(
            event_type='config.test',
            event_id=str(uuid.uuid4()),
            timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            config_id='test-config',
            version=1,
            app_name='test-app',
            environment='test',
            updated_by=g.user.get('username', 'admin'),
            change_notes='Test webhook event',
            settings={'test': True},
            metadata={'test': True}
        )
        webhook_manager.dispatch_event(test_event)
        return jsonify({'message': 'Test webhook dispatched'}), 200
    except Exception as e:
        logger.error(f"Webhook test failed: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/webhooks/stats', methods=['GET'])
@require_api_key
@require_role('admin')
def webhook_stats():
    """Get webhook delivery statistics."""
    return jsonify({'stats': webhook_manager.get_webhook_stats()}), 200


# Alias routes for backward compatibility with tests expecting /api/configs
@app.route('/api/configs', methods=['POST', 'GET'])
@track_request_metrics
def configs_alias():
    if request.method == 'POST':
        # Accept alternate payload shape {name, environment, data}
        try:
            if request.is_json:
                try:
                    data = request.get_json() or {}
                except Exception:
                    return jsonify({'error': 'Invalid JSON payload', 'status': 400}), 400
                if any(k in data for k in ['name', 'data']):
                    transformed = {
                        'config_id': data.get('config_id') or data.get('name') or str(uuid.uuid4()),
                        'app_name': data.get('app_name') or data.get('application') or data.get('name') or 'app',
                        'environment': data.get('environment') or data.get('env') or 'default',
                        'settings': data.get('data') or data.get('settings') or {}
                    }
                    updated_by = data.get('updated_by') or ((g.user or {}).get('username') if hasattr(g, 'user') else None)
                    change_notes = data.get('change_notes', '')
                    result = config_manager.create_config(transformed, updated_by=updated_by, change_notes=change_notes)
                    trigger_webhook_on_create(result, webhook_manager)
                    update_config_metrics()
                    return jsonify(result), 201
            # Fallback to primary handler
            return create_config()
        except Exception as e:
            logger.warning(f"/api/configs alias handler error: {e}")
            return jsonify({'error': str(e), 'status': 400}), 400
    else:
        # GET maps to query endpoint
        return query_configurations()


# Metrics endpoint for Prometheus scraping
@app.route('/metrics', methods=['GET'])
def metrics_route():
    """Expose Prometheus metrics endpoint."""
    body, status, headers = metrics_endpoint()
    return (body, status, headers)


# Application Entry Point

if __name__ == '__main__':
    # Load configuration from environment
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('FLASK_DEBUG', 'True').lower() == 'true'
    
    logger.info(f"Starting Shepherd Configuration Management API on port {port}")
    logger.info(f"Debug mode: {debug}")
    
    # Run Flask development server
    app.run(
        host='0.0.0.0',  # Allow external connections
        port=port,
        debug=debug
    )