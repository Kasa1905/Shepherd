"""
Database layer for Shepherd Configuration Management System.

This module provides MongoDB connectivity and CRUD operations with versioning
for configuration management. It handles configuration document creation,
updates, retrieval, and maintains version history.
"""

import os
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any
from dotenv import load_dotenv
from pymongo import MongoClient, DESCENDING, ReadPreference
from pymongo.errors import (
    DuplicateKeyError,
    ConnectionFailure,
    ServerSelectionTimeoutError,
    OperationFailure,
)
from bson import ObjectId

# Conditionally import metrics decorator (guarded import)
try:
    from metrics import track_db_operation
except ImportError:
    # If metrics module is not available, create a no-op decorator
    def track_db_operation(operation, collection):
        def decorator(func):
            return func

        return decorator


# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DatabaseConnection:
    """Singleton MongoDB connection manager."""

    _instance = None
    _client = None
    _database = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(DatabaseConnection, cls).__new__(cls)
            cls._instance._initialize_connection()
        return cls._instance

    def _initialize_connection(self):
        """Initialize MongoDB connection with replica set support and retry logic."""
        mongodb_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017/")
        database_name = os.getenv("DATABASE_NAME", "shepherd_cms")

        try:
            # Parse URI to detect replica set configuration
            is_replica_set = self._is_replica_set_uri(mongodb_uri)

            # Enhanced connection options for replica sets
            connection_options = {
                "serverSelectionTimeoutMS": 30000,  # Increased for replica set discovery
                "connectTimeoutMS": 10000,
                "socketTimeoutMS": 10000,
                "heartbeatFrequencyMS": 10000,
                "retryWrites": True,
                "w": "majority" if is_replica_set else 1,
                "wtimeoutMS": 30000,
            }

            # Add replica set specific options
            if is_replica_set:
                connection_options.update(
                    {
                        "read_preference": ReadPreference.SECONDARY_PREFERRED,  # Distribute reads
                        "maxPoolSize": 50,
                        "minPoolSize": 5,
                        "maxIdleTimeMS": 30000,
                        "serverSelectionTimeoutMS": 30000,
                    }
                )
                logger.info(
                    "Detected replica set configuration, using enhanced connection options"
                )

            # Create client with retry logic
            retry_count = 3
            for attempt in range(retry_count):
                try:
                    self._client = MongoClient(mongodb_uri, **connection_options)

                    # Test connection and verify server accessibility
                    server_info = self._client.server_info()
                    logger.info(
                        f"MongoDB server version: {server_info.get('version', 'unknown')}"
                    )

                    # Check replica set status if applicable
                    if is_replica_set:
                        rs_status = self._check_replica_set_status()
                        if rs_status:
                            logger.info(f"Replica set status: {rs_status}")

                    break

                except (ConnectionFailure, ServerSelectionTimeoutError) as e:
                    if attempt < retry_count - 1:
                        import time

                        wait_time = 2**attempt  # Exponential backoff
                        logger.warning(
                            f"Connection attempt {attempt + 1} failed: {e}. Retrying in {wait_time} seconds..."
                        )
                        time.sleep(wait_time)
                    else:
                        raise

            self._database = self._client[database_name]

            # Create indexes for optimization
            self._create_indexes()

            logger.info(f"Successfully connected to MongoDB database: {database_name}")

        except (ConnectionFailure, ServerSelectionTimeoutError) as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise ConnectionError(f"Database connection failed: {e}")

    def _is_replica_set_uri(self, uri: str) -> bool:
        """Check if the MongoDB URI is configured for a replica set."""
        return (
            "replicaSet=" in uri
            or "," in uri.split("://")[1].split("/")[0]
            or "readPreference=" in uri  # Multiple hosts
        )

    def _check_replica_set_status(self) -> Optional[Dict[str, Any]]:
        """Check replica set status and return basic information."""
        try:
            admin_db = self._client.admin
            rs_status = admin_db.command("replSetGetStatus")

            primary_node = None
            secondary_nodes = []

            for member in rs_status.get("members", []):
                if member.get("stateStr") == "PRIMARY":
                    primary_node = member.get("name")
                elif member.get("stateStr") == "SECONDARY":
                    secondary_nodes.append(member.get("name"))

            return {
                "set": rs_status.get("set"),
                "primary": primary_node,
                "secondaries": secondary_nodes,
                "total_members": len(rs_status.get("members", [])),
            }

        except OperationFailure as e:
            # This is expected if not running in a replica set
            logger.debug(f"Not running in replica set mode: {e}")
            return None
        except Exception as e:
            logger.warning(f"Failed to get replica set status: {e}")
            return None

    def _create_indexes(self):
        """Create necessary indexes for better query performance."""
        try:
            # Configuration indexes
            configurations_collection = self._database.configurations
            # Drop any legacy unique index on the field 'name' to avoid conflicts
            try:
                for ix in configurations_collection.list_indexes():
                    # ix['key'] is an ordered mapping like {'name': 1}
                    key_fields = list(ix.get("key", {}).keys())
                    if "name" in key_fields:
                        configurations_collection.drop_index(ix["name"])
                        logger.info(f"Dropped legacy index on 'name': {ix['name']}")
            except Exception as e:
                logger.debug(f"Index cleanup skipped/failed: {e}")
            # Unique index to prevent duplicate versions for the same config_id
            configurations_collection.create_index(
                [("config_id", 1), ("version", 1)], unique=True
            )
            # Helpful query indexes
            configurations_collection.create_index([("app_name", 1)])
            configurations_collection.create_index([("environment", 1)])
            configurations_collection.create_index([("created_at", -1)])
            configurations_collection.create_index([("updated_at", -1)])

            # Compound indexes for common queries
            configurations_collection.create_index(
                [("environment", 1), ("created_at", -1)]
            )
            configurations_collection.create_index(
                [("app_name", 1), ("environment", 1)]
            )

            # User indexes
            users_collection = self._database.users
            users_collection.create_index([("username", 1)], unique=True)
            users_collection.create_index([("api_key", 1)], unique=True)
            users_collection.create_index([("role", 1)])
            users_collection.create_index([("is_active", 1)])
            users_collection.create_index([("created_at", -1)])

            logger.info("Created configuration and user indexes successfully")

        except Exception as e:
            logger.warning(f"Error creating indexes: {e}")

    @property
    def database(self):
        """Get database instance."""
        if self._database is None:
            raise ConnectionError("Database connection not initialized")
        return self._database

    @property
    def client(self):
        """Get MongoDB client instance."""
        if self._client is None:
            raise ConnectionError("Database connection not initialized")
        return self._client

    def health_check(self) -> Dict[str, Any]:
        """
        Perform comprehensive health check for MongoDB connection and replica set.

        Returns:
            Dictionary containing health status information
        """
        health_status = {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "connection": False,
            "database_accessible": False,
            "replica_set": None,
            "errors": [],
        }

        try:
            # Test basic connectivity
            server_info = self._client.server_info()
            health_status["connection"] = True
            health_status["server_version"] = server_info.get("version", "unknown")

            # Test database accessibility
            collections = self._database.list_collection_names()
            health_status["database_accessible"] = True
            health_status["collections_count"] = len(collections)

            # Check replica set status if applicable
            mongodb_uri = os.getenv("MONGODB_URI", "")
            if self._is_replica_set_uri(mongodb_uri):
                rs_status = self._check_replica_set_status()
                if rs_status:
                    health_status["replica_set"] = rs_status

                    # Additional replica set health checks
                    if rs_status["primary"] is None:
                        health_status["errors"].append(
                            "No primary node found in replica set"
                        )
                        health_status["status"] = "degraded"

                    if len(rs_status["secondaries"]) == 0:
                        health_status["errors"].append("No secondary nodes available")
                        health_status["status"] = "degraded"

            # Test write operation with a simple ping to admin database
            admin_db = self._client.admin
            ping_result = admin_db.command("ping")
            health_status["write_accessible"] = ping_result.get("ok") == 1

        except Exception as e:
            health_status["status"] = "unhealthy"
            health_status["errors"].append(f"Health check failed: {str(e)}")
            logger.error(f"Database health check failed: {e}")

        return health_status

    def check_replica_set_lag(self) -> Optional[Dict[str, Any]]:
        """
        Check replication lag in replica set.

        Returns:
            Dictionary with lag information or None if not a replica set
        """
        try:
            if not self._is_replica_set_uri(os.getenv("MONGODB_URI", "")):
                return None

            admin_db = self._client.admin
            rs_status = admin_db.command("replSetGetStatus")

            primary_optime = None
            secondaries_lag = []

            for member in rs_status.get("members", []):
                if member.get("stateStr") == "PRIMARY":
                    primary_optime = member.get("optime", {}).get("ts")
                elif member.get("stateStr") == "SECONDARY":
                    secondary_optime = member.get("optime", {}).get("ts")
                    if primary_optime and secondary_optime:
                        lag_seconds = primary_optime.time - secondary_optime.time
                        secondaries_lag.append(
                            {"name": member.get("name"), "lag_seconds": lag_seconds}
                        )

            return {
                "primary_optime": primary_optime.time if primary_optime else None,
                "secondaries_lag": secondaries_lag,
                "max_lag_seconds": max([s["lag_seconds"] for s in secondaries_lag])
                if secondaries_lag
                else 0,
            }

        except Exception as e:
            logger.warning(f"Failed to check replica set lag: {e}")
            return None

    def test_failover_readiness(self) -> Dict[str, Any]:
        """
        Test failover readiness by checking replica set configuration.

        Returns:
            Dictionary with failover readiness status
        """
        readiness = {"ready_for_failover": False, "issues": [], "recommendations": []}

        try:
            health = self.health_check()

            if health["replica_set"] is None:
                readiness["issues"].append("Not running in replica set mode")
                readiness["recommendations"].append(
                    "Configure replica set for high availability"
                )
                return readiness

            rs_info = health["replica_set"]

            # Check primary availability
            if rs_info["primary"] is None:
                readiness["issues"].append("No primary node available")

            # Check secondary count
            if len(rs_info["secondaries"]) < 1:
                readiness["issues"].append("Insufficient secondary nodes for failover")
                readiness["recommendations"].append("Deploy at least 2 secondary nodes")

            # Check replication lag
            lag_info = self.check_replica_set_lag()
            if lag_info and lag_info["max_lag_seconds"] > 60:  # More than 1 minute lag
                readiness["issues"].append(
                    f"High replication lag: {lag_info['max_lag_seconds']} seconds"
                )
                readiness["recommendations"].append(
                    "Investigate network or performance issues"
                )

            # If no critical issues, mark as ready
            if not readiness["issues"]:
                readiness["ready_for_failover"] = True

        except Exception as e:
            readiness["issues"].append(f"Failover readiness check failed: {str(e)}")

        return readiness


class ConfigurationManager:
    """Configuration management with versioning support."""

    def __init__(self):
        self.db = DatabaseConnection().database
        self.collection = self.db.configurations

    @track_db_operation("insert", "configurations")
    def create_config(
        self,
        config_data: Dict[str, Any],
        updated_by: str = None,
        change_notes: str = None,
    ) -> Dict[str, Any]:
        """
        Create a new configuration document with version 1.

        Args:
            config_data: Dictionary containing config_id, app_name, environment, and settings
            updated_by: Username of person creating the configuration (optional)
            change_notes: Notes describing the purpose of this configuration (optional)

        Returns:
            Created configuration document

        Raises:
            ValueError: If required fields are missing or config_id already exists
        """
        try:
            # Validate required fields
            required_fields = ["config_id", "app_name", "environment", "settings"]
            for field in required_fields:
                if field not in config_data:
                    raise ValueError(f"Missing required field: {field}")

            # Check if config_id already exists
            existing_config = self.collection.find_one(
                {"config_id": config_data["config_id"]}
            )
            if existing_config:
                raise ValueError(
                    f"Configuration with config_id '{config_data['config_id']}' already exists"
                )

            # Prepare document with metadata
            current_time = datetime.utcnow().isoformat()
            document = {
                "config_id": config_data["config_id"],
                "version": 1,
                "app_name": config_data["app_name"],
                "environment": config_data["environment"],
                "settings": config_data["settings"],
                "created_at": current_time,
                "updated_at": current_time,
                "updated_by": updated_by,
                "change_notes": change_notes or "Initial configuration creation",
            }

            # Insert document
            result = self.collection.insert_one(document)
            document["_id"] = str(result.inserted_id)

            logger.info(
                f"Created configuration: {config_data['config_id']} (version 1)"
            )
            return document

        except DuplicateKeyError:
            raise ValueError(
                f"Configuration with config_id '{config_data['config_id']}' already exists"
            )
        except Exception as e:
            logger.error(f"Error creating configuration: {e}")
            raise RuntimeError(f"Failed to create configuration: {e}")

    @track_db_operation("find", "configurations")
    def get_latest_config(self, config_id: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve the latest version of a configuration.

        Args:
            config_id: Unique identifier for the configuration

        Returns:
            Latest configuration document or None if not found
        """
        try:
            document = self.collection.find_one(
                {"config_id": config_id}, sort=[("version", DESCENDING)]
            )

            if document:
                # Convert ObjectId to string for JSON serialization
                document["_id"] = str(document["_id"])
                logger.info(
                    f"Retrieved latest configuration: {config_id} (version {document['version']})"
                )

            return document

        except Exception as e:
            logger.error(f"Error retrieving latest configuration: {e}")
            raise RuntimeError(f"Failed to retrieve configuration: {e}")

    # Backwards/compatibility alias expected by some tests
    def get_config(self, config_id: str) -> Optional[Dict[str, Any]]:
        """Alias for get_latest_config for compatibility with tests."""
        return self.get_latest_config(config_id)

    @track_db_operation("insert", "configurations")
    def update_config(
        self,
        config_id: str,
        new_settings: Dict[str, Any],
        updated_by: str = None,
        change_notes: str = None,
    ) -> Dict[str, Any]:
        """
        Update a configuration by creating a new version.

        Args:
            config_id: Unique identifier for the configuration
            new_settings: New settings dictionary
            updated_by: Username of person updating the configuration (optional)
            change_notes: Notes describing the changes made (optional)

        Returns:
            New configuration document with incremented version

        Raises:
            ValueError: If configuration doesn't exist
        """
        try:
            # Get the latest version
            latest_config = self.collection.find_one(
                {"config_id": config_id}, sort=[("version", DESCENDING)]
            )

            if not latest_config:
                raise ValueError(
                    f"Configuration with config_id '{config_id}' not found"
                )

            # Create new version document
            new_version = latest_config["version"] + 1
            current_time = datetime.utcnow().isoformat()

            new_document = {
                "config_id": config_id,
                "version": new_version,
                "app_name": latest_config["app_name"],
                "environment": latest_config["environment"],
                "settings": new_settings,
                "created_at": latest_config[
                    "created_at"
                ],  # Preserve original creation time
                "updated_at": current_time,
                "updated_by": updated_by,
                "change_notes": change_notes or "Configuration updated",
            }

            # Insert new version
            result = self.collection.insert_one(new_document)
            new_document["_id"] = str(result.inserted_id)

            logger.info(f"Updated configuration: {config_id} (version {new_version})")
            return new_document

        except ValueError:
            # Re-raise ValueError (e.g., config not found) without wrapping
            raise
        except Exception as e:
            logger.error(f"Error updating configuration: {e}")
            raise RuntimeError(f"Failed to update configuration: {e}")

    @track_db_operation("insert", "configurations")
    def rollback_config(
        self,
        config_id: str,
        target_version: int,
        updated_by: str,
        change_notes: str = None,
    ) -> Dict[str, Any]:
        """
        Rollback a configuration to a previous version by creating a new version with old settings.

        Args:
            config_id: Unique identifier for the configuration
            target_version: Version number to rollback to
            updated_by: Username of person performing the rollback
            change_notes: Optional notes describing the rollback reason

        Returns:
            New configuration document with incremented version containing old settings

        Raises:
            ValueError: If target version not found or config_id doesn't exist
        """
        try:
            # Retrieve the target version
            target_config = self.collection.find_one(
                {"config_id": config_id, "version": target_version}
            )
            if not target_config:
                raise ValueError(
                    f"Version {target_version} not found for config_id '{config_id}'"
                )

            # Get the current latest version to determine next version number
            latest_config = self.get_latest_config(config_id)
            if not latest_config:
                raise ValueError(f"Configuration '{config_id}' not found")

            new_version = latest_config["version"] + 1
            current_time = datetime.utcnow().isoformat()

            # Create new document with settings from target version
            new_document = {
                "config_id": config_id,
                "version": new_version,
                "app_name": target_config["app_name"],
                "environment": target_config["environment"],
                "settings": target_config[
                    "settings"
                ],  # Copy settings from target version
                "created_at": target_config[
                    "created_at"
                ],  # Preserve original creation time
                "updated_at": current_time,
                "updated_by": updated_by,
                "change_notes": change_notes
                or f"Rolled back to version {target_version}",
            }

            # Insert new version
            result = self.collection.insert_one(new_document)
            new_document["_id"] = str(result.inserted_id)

            logger.info(
                f"Rolled back {config_id} to version {target_version}, created version {new_version}"
            )
            return new_document

        except ValueError:
            # Re-raise ValueError for config/version not found
            raise
        except Exception as e:
            logger.error(f"Error rolling back configuration: {e}")
            raise RuntimeError(f"Failed to rollback configuration: {e}")

    @track_db_operation("find", "configurations")
    def get_config_version(
        self, config_id: str, version: int
    ) -> Optional[Dict[str, Any]]:
        """
        Retrieve a specific version of a configuration.

        Args:
            config_id: Unique identifier for the configuration
            version: Version number to retrieve

        Returns:
            Configuration document for specified version or None if not found
        """
        try:
            document = self.collection.find_one(
                {"config_id": config_id, "version": version}
            )

            if document:
                # Convert ObjectId to string for JSON serialization
                document["_id"] = str(document["_id"])
                logger.info(
                    f"Retrieved configuration version: {config_id} (version {version})"
                )

            return document

        except Exception as e:
            logger.error(f"Error retrieving configuration version: {e}")
            return None

    @track_db_operation("find", "configurations")
    def get_config_history(self, config_id: str) -> List[Dict[str, Any]]:
        """
        Retrieve all versions of a configuration, sorted by version descending.

        Args:
            config_id: Unique identifier for the configuration

        Returns:
            List of configuration documents (all versions)
        """
        try:
            cursor = self.collection.find({"config_id": config_id}).sort(
                "version", DESCENDING
            )

            documents = []
            for doc in cursor:
                doc["_id"] = str(doc["_id"])
                documents.append(doc)

            logger.info(
                f"Retrieved {len(documents)} versions for configuration: {config_id}"
            )
            return documents

        except Exception as e:
            logger.error(f"Error retrieving configuration history: {e}")
            raise RuntimeError(f"Failed to retrieve configuration history: {e}")

    @track_db_operation("aggregate", "configurations")
    def query_configs(
        self, app_name: Optional[str] = None, environment: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Query configurations by app_name and/or environment, returning latest versions only.

        Args:
            app_name: Filter by application name (optional)
            environment: Filter by environment (optional)

        Returns:
            List of latest configuration documents matching the criteria
        """
        try:
            # Build aggregation pipeline to get latest versions only
            pipeline = []

            # Match stage for filtering
            match_criteria = {}
            if app_name:
                match_criteria["app_name"] = app_name
            if environment:
                match_criteria["environment"] = environment

            if match_criteria:
                pipeline.append({"$match": match_criteria})

            # Group by config_id to get latest version
            pipeline.extend(
                [
                    {"$sort": {"config_id": 1, "version": -1}},
                    {
                        "$group": {
                            "_id": "$config_id",
                            "latest_doc": {"$first": "$$ROOT"},
                        }
                    },
                    {"$replaceRoot": {"newRoot": "$latest_doc"}},
                    {"$sort": {"config_id": 1}},
                ]
            )

            cursor = self.collection.aggregate(pipeline)
            documents = []

            for doc in cursor:
                doc["_id"] = str(doc["_id"])
                documents.append(doc)

            logger.info(
                f"Retrieved {len(documents)} latest configurations (app_name={app_name}, environment={environment})"
            )
            return documents

        except Exception as e:
            logger.error(f"Error querying configurations: {e}")
            raise RuntimeError(f"Failed to query configurations: {e}")

    @track_db_operation("delete", "configurations")
    def delete_config(self, config_id: str) -> int:
        """
        Delete all versions of a configuration.

        Args:
            config_id: Unique identifier for the configuration

        Returns:
            Number of deleted documents
        """
        try:
            result = self.collection.delete_many({"config_id": config_id})
            deleted_count = result.deleted_count

            logger.info(
                f"Deleted {deleted_count} versions of configuration: {config_id}"
            )
            return deleted_count

        except Exception as e:
            logger.error(f"Error deleting configuration: {e}")
            raise RuntimeError(f"Failed to delete configuration: {e}")

    def get_database_stats(self) -> Dict[str, Any]:
        """
        Get database statistics.

        Returns:
            Database statistics including document count and storage size
        """
        try:
            stats = self.db.command("collStats", "configurations")

            return {
                "document_count": stats.get("count", 0),
                "storage_size": stats.get("storageSize", 0),
                "average_object_size": stats.get("avgObjSize", 0),
                "total_index_size": stats.get("totalIndexSize", 0),
            }

        except Exception as e:
            logger.error(f"Error retrieving database stats: {e}")
            return {"error": str(e)}

    def get_metrics_data(self) -> Dict[str, Any]:
        """
        Aggregate metrics-friendly data for Prometheus updaters.

        Returns:
            {
              'configs_by_app_env': {'app|env': count, ...},
              'versions_per_config': {'config_id': count, ...},
              'latest_versions': {'config_id': latest_version, ...}
            }
        """
        try:
            # Aggregate counts by app/environment
            pipeline_app_env = [
                {
                    "$group": {
                        "_id": {"app": "$app_name", "env": "$environment"},
                        "count": {"$sum": 1},
                    }
                }
            ]
            app_env_counts = {}
            for row in self.collection.aggregate(pipeline_app_env):
                app = row.get("_id", {}).get("app")
                env = row.get("_id", {}).get("env")
                if app and env:
                    app_env_counts[f"{app}|{env}"] = row.get("count", 0)

            # Versions per config and latest version
            pipeline_versions = [
                {
                    "$group": {
                        "_id": "$config_id",
                        "count": {"$sum": 1},
                        "latest": {"$max": "$version"},
                    }
                }
            ]
            versions_per_config = {}
            latest_versions = {}
            for row in self.collection.aggregate(pipeline_versions):
                cid = row.get("_id")
                if cid is not None:
                    versions_per_config[cid] = row.get("count", 0)
                    latest_versions[cid] = row.get("latest", 0)

            return {
                "configs_by_app_env": app_env_counts,
                "versions_per_config": versions_per_config,
                "latest_versions": latest_versions,
            }
        except Exception as e:
            logger.warning(f"Failed to build metrics data: {e}")
            return {
                "configs_by_app_env": {},
                "versions_per_config": {},
                "latest_versions": {},
            }


class UserManager:
    """
    Manager class for user operations and authentication.

    Handles user creation, authentication, API key management,
    and role-based access control.
    """

    def __init__(self):
        """Initialize UserManager with database connection."""
        self.db = DatabaseConnection().database
        self.collection = self.db.users

    @track_db_operation("insert", "users")
    def create_user(self, username, password_hash, role, api_key=None):
        """
        Create a new user document.

        Args:
            username: Unique username
            password_hash: Hashed password
            role: User role (viewer, editor, admin)
            api_key: Optional API key (generated if not provided)

        Returns:
            Created user document (without password_hash)

        Raises:
            ValueError: If username already exists or role is invalid
        """
        try:
            # Validate role
            valid_roles = ["viewer", "editor", "admin"]
            if role not in valid_roles:
                raise ValueError(f"Invalid role. Must be one of: {valid_roles}")

            # Check if username already exists
            existing_user = self.collection.find_one({"username": username})
            if existing_user:
                raise ValueError(f"Username '{username}' already exists")

            # Generate API key if not provided
            if api_key is None:
                import secrets

                api_key = secrets.token_urlsafe(32)

            # Prepare user document
            current_time = datetime.utcnow().isoformat()
            user_document = {
                "username": username,
                "password_hash": password_hash,
                "role": role,
                "api_key": api_key,
                "created_at": current_time,
                "updated_at": current_time,
                "is_active": True,
            }

            # Insert user
            result = self.collection.insert_one(user_document)
            user_document["_id"] = result.inserted_id

            # Return user without password_hash for security
            safe_user = {k: v for k, v in user_document.items() if k != "password_hash"}

            logger.info(f"Created user: {username} with role: {role}")
            return safe_user

        except Exception as e:
            logger.error(f"Error creating user: {e}")
            raise

    @track_db_operation("find", "users")
    def get_user_by_username(self, username):
        """
        Retrieve user by username (includes password_hash for login verification).

        Args:
            username: Username to search for

        Returns:
            User document with password_hash or None if not found
        """
        try:
            user = self.collection.find_one({"username": username, "is_active": True})
            if user:
                user["_id"] = str(user["_id"])
            return user

        except Exception as e:
            logger.error(f"Error retrieving user by username: {e}")
            return None

    @track_db_operation("find", "users")
    def get_user_by_id(self, user_id):
        """
        Retrieve user by ID (excludes password_hash).

        Args:
            user_id: User ID string

        Returns:
            User document without password_hash or None if not found
        """
        try:
            user = self.collection.find_one(
                {"_id": ObjectId(user_id), "is_active": True},
                {"password_hash": 0},  # Exclude password_hash
            )
            if user:
                user["_id"] = str(user["_id"])
            return user

        except Exception as e:
            logger.error(f"Error retrieving user by ID: {e}")
            return None

    @track_db_operation("find", "users")
    def get_user_by_api_key(self, api_key):
        """
        Retrieve user by API key (excludes password_hash).

        Args:
            api_key: API key to search for

        Returns:
            User document without password_hash or None if not found
        """
        try:
            user = self.collection.find_one(
                {"api_key": api_key, "is_active": True},
                {"password_hash": 0},  # Exclude password_hash
            )
            if user:
                user["_id"] = str(user["_id"])
            return user

        except Exception as e:
            logger.error(f"Error retrieving user by API key: {e}")
            return None

    @track_db_operation("update", "users")
    def update_user_password(self, username, new_password_hash):
        """
        Update user's password.

        Args:
            username: Username to update
            new_password_hash: New hashed password

        Returns:
            Updated user document without password_hash
        """
        try:
            current_time = datetime.utcnow().isoformat()
            result = self.collection.update_one(
                {"username": username},
                {
                    "$set": {
                        "password_hash": new_password_hash,
                        "updated_at": current_time,
                    }
                },
            )

            if result.modified_count > 0:
                logger.info(f"Updated password for user: {username}")
                return self.get_user_by_username(username)
            else:
                raise ValueError(f"User '{username}' not found")

        except Exception as e:
            logger.error(f"Error updating user password: {e}")
            raise

    @track_db_operation("update", "users")
    def regenerate_api_key(self, username, new_api_key):
        """
        Update user's API key.

        Args:
            username: Username to update
            new_api_key: New API key

        Returns:
            Updated user document without password_hash
        """
        try:
            current_time = datetime.utcnow().isoformat()
            result = self.collection.update_one(
                {"username": username},
                {"$set": {"api_key": new_api_key, "updated_at": current_time}},
            )

            if result.modified_count > 0:
                logger.info(f"Regenerated API key for user: {username}")
                # Return user without password_hash
                user = self.collection.find_one(
                    {"username": username}, {"password_hash": 0}
                )
                if user:
                    user["_id"] = str(user["_id"])
                return user
            else:
                raise ValueError(f"User '{username}' not found")

        except Exception as e:
            logger.error(f"Error regenerating API key: {e}")
            raise

    @track_db_operation("find", "users")
    def list_users(self):
        """
        List all users (admin function).

        Returns:
            List of users without password_hash
        """
        try:
            users = list(
                self.collection.find({}, {"password_hash": 0})  # Exclude password_hash
            )

            # Convert ObjectId to string
            for user in users:
                user["_id"] = str(user["_id"])

            return users

        except Exception as e:
            logger.error(f"Error listing users: {e}")
            return []

    @track_db_operation("delete", "users")
    def delete_user(self, username):
        """
        Delete user (admin function).

        Args:
            username: Username to delete

        Returns:
            Number of deleted documents
        """
        try:
            result = self.collection.delete_one({"username": username})

            if result.deleted_count > 0:
                logger.info(f"Deleted user: {username}")

            return result.deleted_count

        except Exception as e:
            logger.error(f"Error deleting user: {e}")
            return 0

    @track_db_operation("find", "users")
    def user_exists(self):
        """
        Check if any users exist in the system.

        Returns:
            True if any users exist, False otherwise
        """
        try:
            count = self.collection.count_documents({})
            return count > 0

        except Exception as e:
            logger.error(f"Error checking if users exist: {e}")
            return False


# Global instances for easy importing
config_manager = ConfigurationManager()
user_manager = UserManager()
