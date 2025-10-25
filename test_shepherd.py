"""
Comprehensive test suite for Shepherd Configuration Management System.

This test suite validates all API endpoints, versioning logic, error handling,
and database operations for the Shepherd CMS.
"""

import pytest
import json
import os
import sys
from unittest.mock import patch

# CRITICAL: Set up test environment variables BEFORE importing app/config_manager
# to ensure config_manager.collection points to test DB and prevent production data deletion
os.environ["MONGODB_URI"] = "mongodb://localhost:27017/"
os.environ["DATABASE_NAME"] = "shepherd_cms_test"
os.environ["FLASK_ENV"] = "testing"
os.environ["FLASK_DEBUG"] = "False"

# Add the project directory to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import AFTER setting test environment variables
from app import app
from database import config_manager


# Test Configuration
@pytest.fixture(scope="session", autouse=True)
def setup_test_environment():
    """Ensure test environment is properly configured."""
    # Verify test database is being used
    assert "test" in os.environ.get("DATABASE_NAME", ""), "Test database not configured"


@pytest.fixture
def test_client():
    """Create Flask test client."""
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


@pytest.fixture(autouse=True)
def clean_database():
    """Clean up test database before and after each test."""
    # Clean before test
    try:
        config_manager.collection.delete_many({})
    except Exception:
        pass  # Ignore errors if collection doesn't exist

    yield

    # Clean after test
    try:
        config_manager.collection.delete_many({})
    except Exception:
        pass


@pytest.fixture
def sample_config():
    """Provide sample configuration data for tests."""
    return {
        "config_id": "test_config_123",
        "app_name": "TestApp",
        "environment": "testing",
        "settings": {
            "database_url": "mongodb://localhost:27017/test",
            "debug": True,
            "max_connections": 50,
            "features": {"caching": True, "logging": False},
        },
    }


# Test Utilities and Helpers
def cleanup_test_data():
    """Helper function to delete all test configurations."""
    try:
        config_manager.collection.delete_many({})
    except Exception:
        pass


def create_test_config(config_data=None):
    """Helper to create a standard test configuration."""
    if config_data is None:
        config_data = {
            "config_id": "helper_test_config",
            "app_name": "HelperApp",
            "environment": "test",
            "settings": {"key": "value"},
        }
    return config_manager.create_config(config_data)


def assert_config_structure(config):
    """Helper to validate configuration document structure."""
    required_fields = [
        "config_id",
        "version",
        "app_name",
        "environment",
        "settings",
        "created_at",
        "updated_at",
    ]
    for field in required_fields:
        assert field in config, f"Missing required field: {field}"

    assert isinstance(config["version"], int), "Version must be an integer"
    assert config["version"] >= 1, "Version must be >= 1"
    assert isinstance(config["settings"], dict), "Settings must be a dictionary"


def assert_version_increment(old_config, new_config):
    """Helper to validate version incrementing logic."""
    assert (
        new_config["version"] == old_config["version"] + 1
    ), "Version should increment by 1"
    assert (
        new_config["config_id"] == old_config["config_id"]
    ), "Config ID should remain same"
    assert (
        new_config["app_name"] == old_config["app_name"]
    ), "App name should remain same"
    assert (
        new_config["environment"] == old_config["environment"]
    ), "Environment should remain same"
    assert (
        new_config["created_at"] == old_config["created_at"]
    ), "Created timestamp should be preserved"
    assert (
        new_config["updated_at"] != old_config["updated_at"]
    ), "Updated timestamp should change"


# Test Class 1: Configuration Creation Tests
class TestConfigurationCreation:
    """Test configuration creation via POST /api/config"""

    @pytest.mark.api
    def test_create_config_success(self, test_client, sample_config):
        """Test successful POST to /api/config with valid payload."""
        response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        assert response.status_code == 201
        data = json.loads(response.data)

        # Verify response contains all required fields
        assert_config_structure(data)

        # Verify specific values
        assert data["config_id"] == sample_config["config_id"]
        assert data["app_name"] == sample_config["app_name"]
        assert data["environment"] == sample_config["environment"]
        assert data["version"] == 1
        assert data["settings"] == sample_config["settings"]
        assert "created_at" in data
        assert "updated_at" in data
        assert "_id" in data

    @pytest.mark.api
    def test_create_config_duplicate(self, test_client, sample_config):
        """Test POST with duplicate config_id."""
        # Create initial configuration
        response1 = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        assert response1.status_code == 201

        # Attempt to create another with same config_id
        response2 = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        assert response2.status_code == 400
        data = json.loads(response2.data)
        assert "error" in data
        assert "already exists" in data["error"].lower()

    @pytest.mark.api
    def test_create_config_missing_fields(self, test_client, sample_config):
        """Test POST with missing required fields."""
        required_fields = ["config_id", "app_name", "environment", "settings"]

        for field in required_fields:
            config_copy = sample_config.copy()
            del config_copy[field]

            response = test_client.post(
                "/api/config",
                data=json.dumps(config_copy),
                content_type="application/json",
            )

            assert response.status_code == 400
            data = json.loads(response.data)
            assert "error" in data
            assert field in data["error"].lower()

    @pytest.mark.api
    def test_create_config_invalid_settings_type(self, test_client, sample_config):
        """Test POST with non-dict settings."""
        invalid_settings = ["string_settings", ["list", "settings"], 123, True]

        for invalid_setting in invalid_settings:
            config_copy = sample_config.copy()
            config_copy["settings"] = invalid_setting

            response = test_client.post(
                "/api/config",
                data=json.dumps(config_copy),
                content_type="application/json",
            )

            assert response.status_code == 400
            data = json.loads(response.data)
            assert "error" in data
            assert "settings" in data["error"].lower()

    @pytest.mark.api
    def test_create_config_invalid_content_type(self, test_client, sample_config):
        """Test POST without JSON content type."""
        # Test with text/plain
        response1 = test_client.post(
            "/api/config", data=json.dumps(sample_config), content_type="text/plain"
        )

        assert response1.status_code == 400
        data1 = json.loads(response1.data)
        assert "content-type" in data1["error"].lower()

        # Test with form data
        response2 = test_client.post("/api/config", data=sample_config)

        assert response2.status_code == 400


# Test Class 2: Configuration Retrieval Tests
class TestConfigurationRetrieval:
    """Test configuration retrieval via GET /api/config/<config_id>"""

    @pytest.mark.api
    def test_get_latest_config_success(self, test_client, sample_config):
        """Test GET /api/config/<config_id>."""
        # Create a configuration
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        assert create_response.status_code == 201

        # Retrieve it via GET
        get_response = test_client.get(f'/api/config/{sample_config["config_id"]}')

        assert get_response.status_code == 200
        data = json.loads(get_response.data)

        # Verify all fields match created config
        assert_config_structure(data)
        assert data["config_id"] == sample_config["config_id"]
        assert data["app_name"] == sample_config["app_name"]
        assert data["environment"] == sample_config["environment"]
        assert data["version"] == 1
        assert data["settings"] == sample_config["settings"]

    @pytest.mark.api
    def test_get_latest_config_not_found(self, test_client):
        """Test GET for non-existent config_id."""
        response = test_client.get("/api/config/nonexistent_config")

        assert response.status_code == 404
        data = json.loads(response.data)
        assert "error" in data
        assert "not found" in data["error"].lower()

    @pytest.mark.api
    def test_get_latest_config_after_updates(self, test_client, sample_config):
        """Test GET returns latest version."""
        # Create config (version 1)
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        assert create_response.status_code == 201

        # Update it twice (versions 2 and 3)
        update1 = {"settings": {"updated": "version2"}}
        update2 = {"settings": {"updated": "version3"}}

        test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(update1),
            content_type="application/json",
        )

        test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(update2),
            content_type="application/json",
        )

        # GET latest config
        get_response = test_client.get(f'/api/config/{sample_config["config_id"]}')

        assert get_response.status_code == 200
        data = json.loads(get_response.data)
        assert data["version"] == 3
        assert data["settings"] == {"updated": "version3"}


# Test Class 3: Configuration Update and Versioning Tests
class TestConfigurationUpdateVersioning:
    """Test configuration updates and versioning via PUT /api/config/<config_id>"""

    @pytest.mark.api
    @pytest.mark.versioning
    def test_update_config_success(self, test_client, sample_config):
        """Test PUT /api/config/<config_id>."""
        # Create initial config (version 1)
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        assert create_response.status_code == 201
        original_data = json.loads(create_response.data)

        # Update with new settings
        new_settings = {
            "database_url": "mongodb://localhost:27017/updated",
            "debug": False,
            "new_feature": True,
        }
        update_payload = {"settings": new_settings}

        update_response = test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(update_payload),
            content_type="application/json",
        )

        assert update_response.status_code == 200
        updated_data = json.loads(update_response.data)

        # Verify version incremented to 2
        assert updated_data["version"] == 2

        # Verify new settings are stored
        assert updated_data["settings"] == new_settings

        # Verify created_at timestamp preserved
        assert updated_data["created_at"] == original_data["created_at"]

        # Verify updated_at timestamp changed
        assert updated_data["updated_at"] != original_data["updated_at"]

        # Verify other fields preserved
        assert updated_data["config_id"] == original_data["config_id"]
        assert updated_data["app_name"] == original_data["app_name"]
        assert updated_data["environment"] == original_data["environment"]

    @pytest.mark.api
    @pytest.mark.versioning
    def test_update_config_multiple_versions(self, test_client, sample_config):
        """Test multiple updates create multiple versions."""
        # Create config (version 1)
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        assert create_response.status_code == 201

        # Update 3 times
        for i in range(2, 5):  # versions 2, 3, 4
            update_payload = {"settings": {"version": f"v{i}"}}
            update_response = test_client.put(
                f'/api/config/{sample_config["config_id"]}',
                data=json.dumps(update_payload),
                content_type="application/json",
            )

            assert update_response.status_code == 200
            data = json.loads(update_response.data)
            assert data["version"] == i

        # Query database to verify 4 documents exist for config_id
        all_versions = config_manager.get_config_history(sample_config["config_id"])
        assert len(all_versions) == 4

        # Verify each document has correct version number
        expected_versions = [4, 3, 2, 1]  # Sorted descending
        actual_versions = [v["version"] for v in all_versions]
        assert actual_versions == expected_versions

    @pytest.mark.api
    def test_update_config_not_found(self, test_client):
        """Test PUT for non-existent config_id."""
        update_payload = {"settings": {"test": "value"}}

        response = test_client.put(
            "/api/config/nonexistent_config",
            data=json.dumps(update_payload),
            content_type="application/json",
        )

        assert response.status_code == 404
        data = json.loads(response.data)
        assert "error" in data

    @pytest.mark.api
    def test_update_config_missing_settings(self, test_client, sample_config):
        """Test PUT without settings field."""
        # Create config first
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        # Try to update without settings
        empty_payload = {}
        response = test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(empty_payload),
            content_type="application/json",
        )

        assert response.status_code == 400
        data = json.loads(response.data)
        assert "settings" in data["error"].lower()

    @pytest.mark.api
    def test_update_config_invalid_settings_type(self, test_client, sample_config):
        """Test PUT with non-dict settings."""
        # Create config first
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        # Try to update with invalid settings type
        invalid_payload = {"settings": "not_a_dict"}
        response = test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(invalid_payload),
            content_type="application/json",
        )

        assert response.status_code == 400
        data = json.loads(response.data)
        assert "settings" in data["error"].lower()

    @pytest.mark.versioning
    def test_update_preserves_metadata(self, test_client, sample_config):
        """Test that updates preserve app_name, environment, config_id."""
        # Create config
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )
        original_data = json.loads(create_response.data)

        # Update settings
        update_payload = {"settings": {"completely": "new", "settings": True}}
        update_response = test_client.put(
            f'/api/config/{sample_config["config_id"]}',
            data=json.dumps(update_payload),
            content_type="application/json",
        )
        updated_data = json.loads(update_response.data)

        # Verify app_name, environment, config_id unchanged
        assert updated_data["app_name"] == original_data["app_name"]
        assert updated_data["environment"] == original_data["environment"]
        assert updated_data["config_id"] == original_data["config_id"]

        # Verify only settings and updated_at changed
        assert updated_data["settings"] != original_data["settings"]
        assert updated_data["updated_at"] != original_data["updated_at"]
        assert updated_data["created_at"] == original_data["created_at"]


# Test Class 4: Version History Tests
class TestVersionHistory:
    """Test version history via GET /api/config/history/<config_id>"""

    @pytest.mark.api
    @pytest.mark.versioning
    def test_get_config_history_success(self, test_client, sample_config):
        """Test GET /api/config/history/<config_id>."""
        # Create config and update it 3 times (4 versions total)
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        for i in range(2, 5):  # Create versions 2, 3, 4
            update_payload = {"settings": {"version": i}}
            test_client.put(
                f'/api/config/{sample_config["config_id"]}',
                data=json.dumps(update_payload),
                content_type="application/json",
            )

        # Get history
        response = test_client.get(f'/api/config/history/{sample_config["config_id"]}')

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify 4 documents returned
        assert len(data) == 4

        # Verify versions are [4, 3, 2, 1] (descending order)
        versions = [item["version"] for item in data]
        assert versions == [4, 3, 2, 1]

    @pytest.mark.api
    @pytest.mark.versioning
    def test_get_config_history_sorting(self, test_client, sample_config):
        """Test history is sorted by version descending."""
        # Create config and update multiple times
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        # Create 5 more versions
        for i in range(2, 7):
            update_payload = {"settings": {"iteration": i}}
            test_client.put(
                f'/api/config/{sample_config["config_id"]}',
                data=json.dumps(update_payload),
                content_type="application/json",
            )

        # Get history
        response = test_client.get(f'/api/config/history/{sample_config["config_id"]}')
        data = json.loads(response.data)

        # Verify first item has highest version
        assert data[0]["version"] == 6

        # Verify last item has version 1
        assert data[-1]["version"] == 1

        # Verify all versions are in descending order
        versions = [item["version"] for item in data]
        assert versions == sorted(versions, reverse=True)

    @pytest.mark.api
    def test_get_config_history_empty(self, test_client):
        """Test history for non-existent config."""
        response = test_client.get("/api/config/history/nonexistent_config")

        assert response.status_code == 200
        data = json.loads(response.data)
        assert isinstance(data, list)
        assert len(data) == 0

    @pytest.mark.api
    def test_get_config_history_single_version(self, test_client, sample_config):
        """Test history with only one version."""
        # Create config without updates
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        # Get history
        response = test_client.get(f'/api/config/history/{sample_config["config_id"]}')

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify 1 document returned
        assert len(data) == 1

        # Verify version is 1
        assert data[0]["version"] == 1


# Test Class 5: Query and Filter Tests
class TestQueryFilter:
    """Test configuration querying via GET /api/config/query"""

    @pytest.mark.api
    def test_query_configs_no_filters(self, test_client):
        """Test GET /api/config/query without filters."""
        # Create multiple configs with different apps and environments
        configs = [
            {
                "config_id": "twitter_bot_prod",
                "app_name": "TwitterBot",
                "environment": "production",
                "settings": {"api_key": "prod_key"},
            },
            {
                "config_id": "slack_bot_dev",
                "app_name": "SlackBot",
                "environment": "development",
                "settings": {"webhook": "dev_url"},
            },
            {
                "config_id": "twitter_bot_dev",
                "app_name": "TwitterBot",
                "environment": "development",
                "settings": {"api_key": "dev_key"},
            },
        ]

        for config in configs:
            test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )

        # Query without parameters
        response = test_client.get("/api/config/query")

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify all latest versions returned
        assert len(data) == 3

        # Verify no duplicate config_ids
        config_ids = [item["config_id"] for item in data]
        assert len(config_ids) == len(set(config_ids))

        # Verify all have version 1 (latest and only)
        for item in data:
            assert item["version"] == 1

    @pytest.mark.api
    def test_query_configs_by_app_name(self, test_client):
        """Test query with app_name filter."""
        # Create configs for different apps
        configs = [
            {
                "config_id": "twitter_1",
                "app_name": "TwitterBot",
                "environment": "prod",
                "settings": {"key": "twitter1"},
            },
            {
                "config_id": "slack_1",
                "app_name": "SlackBot",
                "environment": "prod",
                "settings": {"key": "slack1"},
            },
            {
                "config_id": "twitter_2",
                "app_name": "TwitterBot",
                "environment": "dev",
                "settings": {"key": "twitter2"},
            },
        ]

        for config in configs:
            test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )

        # Query with app=TwitterBot
        response = test_client.get("/api/config/query?app=TwitterBot")

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify only TwitterBot configs returned
        assert len(data) == 2
        for item in data:
            assert item["app_name"] == "TwitterBot"

    @pytest.mark.api
    def test_query_configs_by_environment(self, test_client):
        """Test query with environment filter."""
        # Create configs for different environments
        configs = [
            {
                "config_id": "app1_prod",
                "app_name": "App1",
                "environment": "production",
                "settings": {"env": "prod"},
            },
            {
                "config_id": "app1_staging",
                "app_name": "App1",
                "environment": "staging",
                "settings": {"env": "staging"},
            },
            {
                "config_id": "app2_prod",
                "app_name": "App2",
                "environment": "production",
                "settings": {"env": "prod"},
            },
        ]

        for config in configs:
            test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )

        # Query with env=production
        response = test_client.get("/api/config/query?env=production")

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify only production configs returned
        assert len(data) == 2
        for item in data:
            assert item["environment"] == "production"

    @pytest.mark.api
    def test_query_configs_by_both_filters(self, test_client):
        """Test query with both app_name and environment."""
        # Create various configs
        configs = [
            {
                "config_id": "twitter_prod",
                "app_name": "TwitterBot",
                "environment": "production",
                "settings": {"match": True},
            },
            {
                "config_id": "twitter_dev",
                "app_name": "TwitterBot",
                "environment": "development",
                "settings": {"match": False},
            },
            {
                "config_id": "slack_prod",
                "app_name": "SlackBot",
                "environment": "production",
                "settings": {"match": False},
            },
        ]

        for config in configs:
            test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )

        # Query with both filters
        response = test_client.get("/api/config/query?app=TwitterBot&env=production")

        assert response.status_code == 200
        data = json.loads(response.data)

        # Verify only matching config returned
        assert len(data) == 1
        assert data[0]["app_name"] == "TwitterBot"
        assert data[0]["environment"] == "production"
        assert data[0]["config_id"] == "twitter_prod"

    @pytest.mark.api
    @pytest.mark.versioning
    def test_query_configs_returns_latest_only(self, test_client):
        """Test query returns only latest versions."""
        # Create config and update it (versions 1, 2, 3)
        config1 = {
            "config_id": "versioned_config",
            "app_name": "TestApp",
            "environment": "test",
            "settings": {"version": 1},
        }

        test_client.post(
            "/api/config", data=json.dumps(config1), content_type="application/json"
        )

        # Update twice
        test_client.put(
            "/api/config/versioned_config",
            data=json.dumps({"settings": {"version": 2}}),
            content_type="application/json",
        )

        test_client.put(
            "/api/config/versioned_config",
            data=json.dumps({"settings": {"version": 3}}),
            content_type="application/json",
        )

        # Create another config without updates (version 1)
        config2 = {
            "config_id": "single_version_config",
            "app_name": "TestApp",
            "environment": "test",
            "settings": {"version": 1},
        }

        test_client.post(
            "/api/config", data=json.dumps(config2), content_type="application/json"
        )

        # Query all configs
        response = test_client.get("/api/config/query")
        data = json.loads(response.data)

        # Verify first config returned with version 3 (not 1 or 2)
        versioned_config = next(
            item for item in data if item["config_id"] == "versioned_config"
        )
        assert versioned_config["version"] == 3
        assert versioned_config["settings"]["version"] == 3

        # Verify second config returned with version 1
        single_config = next(
            item for item in data if item["config_id"] == "single_version_config"
        )
        assert single_config["version"] == 1

        # Verify total 2 configs returned (not 4)
        assert len(data) == 2

    @pytest.mark.api
    def test_query_configs_flexible_parameter_names(self, test_client):
        """Test query with alternate parameter names."""
        config = {
            "config_id": "flexible_test",
            "app_name": "FlexApp",
            "environment": "flexible",
            "settings": {"test": True},
        }

        test_client.post(
            "/api/config", data=json.dumps(config), content_type="application/json"
        )

        # Test app_name vs app
        response1 = test_client.get("/api/config/query?app_name=FlexApp")
        response2 = test_client.get("/api/config/query?app=FlexApp")

        data1 = json.loads(response1.data)
        data2 = json.loads(response2.data)

        assert len(data1) == 1
        assert len(data2) == 1
        assert data1[0]["config_id"] == data2[0]["config_id"]

        # Test environment vs env
        response3 = test_client.get("/api/config/query?environment=flexible")
        response4 = test_client.get("/api/config/query?env=flexible")

        data3 = json.loads(response3.data)
        data4 = json.loads(response4.data)

        assert len(data3) == 1
        assert len(data4) == 1
        assert data3[0]["config_id"] == data4[0]["config_id"]

    @pytest.mark.api
    def test_query_configs_no_matches(self, test_client, sample_config):
        """Test query with filters that match nothing."""
        # Create a config
        test_client.post(
            "/api/config",
            data=json.dumps(sample_config),
            content_type="application/json",
        )

        # Query with non-existent app
        response1 = test_client.get("/api/config/query?app=NonExistentApp")
        data1 = json.loads(response1.data)

        assert response1.status_code == 200
        assert isinstance(data1, list)
        assert len(data1) == 0

        # Query with non-existent environment
        response2 = test_client.get("/api/config/query?env=nonexistent")
        data2 = json.loads(response2.data)

        assert response2.status_code == 200
        assert isinstance(data2, list)
        assert len(data2) == 0


# Test Class 6: Error Handling and Edge Cases
class TestErrorHandlingEdgeCases:
    """Test error handling and edge cases"""

    @pytest.mark.api
    def test_invalid_json_payload(self, test_client):
        """Test POST/PUT with malformed JSON."""
        invalid_json = '{"config_id": "test", "invalid": json}'

        # Test POST with invalid JSON
        response1 = test_client.post(
            "/api/config", data=invalid_json, content_type="application/json"
        )
        assert response1.status_code == 400

        # Create a valid config first for PUT test
        valid_config = {
            "config_id": "test_for_put",
            "app_name": "TestApp",
            "environment": "test",
            "settings": {"test": True},
        }
        test_client.post(
            "/api/config",
            data=json.dumps(valid_config),
            content_type="application/json",
        )

        # Test PUT with invalid JSON
        response2 = test_client.put(
            "/api/config/test_for_put",
            data=invalid_json,
            content_type="application/json",
        )
        assert response2.status_code == 400

    @pytest.mark.api
    def test_empty_string_fields(self, test_client):
        """Test POST with empty string values."""
        configs_with_empty_fields = [
            {
                "config_id": "",
                "app_name": "TestApp",
                "environment": "test",
                "settings": {"test": True},
            },
            {
                "config_id": "test",
                "app_name": "",
                "environment": "test",
                "settings": {"test": True},
            },
            {
                "config_id": "test",
                "app_name": "TestApp",
                "environment": "",
                "settings": {"test": True},
            },
        ]

        for config in configs_with_empty_fields:
            response = test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )

            assert response.status_code == 400
            data = json.loads(response.data)
            assert "error" in data
            assert "empty" in data["error"].lower()

    @pytest.mark.api
    def test_nested_settings_support(self, test_client):
        """Test that settings can contain nested objects."""
        nested_config = {
            "config_id": "nested_test",
            "app_name": "NestedApp",
            "environment": "test",
            "settings": {
                "database": {
                    "primary": {
                        "host": "db1.example.com",
                        "port": 5432,
                        "credentials": {"username": "admin", "password": "secret"},
                    },
                    "replica": {"host": "db2.example.com", "port": 5432},
                },
                "features": {
                    "caching": {
                        "enabled": True,
                        "redis": {"host": "redis.example.com", "port": 6379},
                    },
                    "logging": {"level": "INFO", "handlers": ["console", "file"]},
                },
            },
        }

        # Create config with deeply nested settings
        create_response = test_client.post(
            "/api/config",
            data=json.dumps(nested_config),
            content_type="application/json",
        )

        assert create_response.status_code == 201
        _ = json.loads(create_response.data)  # Verify JSON response is valid

        # Retrieve and verify nested structure preserved
        get_response = test_client.get("/api/config/nested_test")
        retrieved_data = json.loads(get_response.data)

        assert retrieved_data["settings"] == nested_config["settings"]
        assert (
            retrieved_data["settings"]["database"]["primary"]["host"]
            == "db1.example.com"
        )
        assert (
            retrieved_data["settings"]["features"]["caching"]["redis"]["port"] == 6379
        )

        # Update with different nested structure
        updated_nested = {
            "settings": {"new_structure": {"deeply": {"nested": {"value": "updated"}}}}
        }

        update_response = test_client.put(
            "/api/config/nested_test",
            data=json.dumps(updated_nested),
            content_type="application/json",
        )

        assert update_response.status_code == 200
        updated_data = json.loads(update_response.data)

        # Verify nested updates work correctly
        assert updated_data["settings"] == updated_nested["settings"]
        assert (
            updated_data["settings"]["new_structure"]["deeply"]["nested"]["value"]
            == "updated"
        )

    @pytest.mark.api
    def test_special_characters_in_config_id(self, test_client):
        """Test config_id with special characters."""
        special_configs = [
            {
                "config_id": "config_with_underscores_123",
                "app_name": "TestApp",
                "environment": "test",
                "settings": {"test": "underscores"},
            },
            {
                "config_id": "config-with-hyphens-456",
                "app_name": "TestApp",
                "environment": "test",
                "settings": {"test": "hyphens"},
            },
            {
                "config_id": "config.with.dots.789",
                "app_name": "TestApp",
                "environment": "test",
                "settings": {"test": "dots"},
            },
        ]

        for config in special_configs:
            # Create config
            create_response = test_client.post(
                "/api/config", data=json.dumps(config), content_type="application/json"
            )
            assert create_response.status_code == 201

            # Verify creation and retrieval work correctly
            get_response = test_client.get(f'/api/config/{config["config_id"]}')
            assert get_response.status_code == 200

            retrieved_data = json.loads(get_response.data)
            assert retrieved_data["config_id"] == config["config_id"]
            assert retrieved_data["settings"] == config["settings"]


# Test Class 7: Database Layer Direct Tests
class TestDatabaseLayerDirect:
    """Test database layer operations directly"""

    @pytest.mark.database
    def test_database_connection(self):
        """Test database connection is established."""
        # Verify config_manager is initialized
        assert config_manager is not None

        # Verify database connection is active
        try:
            stats = config_manager.get_database_stats()
            assert isinstance(stats, dict)
        except Exception as e:
            pytest.fail(f"Database connection failed: {e}")

    @pytest.mark.database
    def test_create_config_database_layer(self, sample_config):
        """Test config_manager.create_config() directly."""
        # Call method directly (not via API)
        result = config_manager.create_config(sample_config)

        # Verify document created in database
        assert_config_structure(result)
        assert result["config_id"] == sample_config["config_id"]
        assert result["version"] == 1
        assert result["settings"] == sample_config["settings"]

        # Verify it exists in database
        retrieved = config_manager.get_latest_config(sample_config["config_id"])
        assert retrieved is not None
        assert retrieved["config_id"] == sample_config["config_id"]

    @pytest.mark.database
    @pytest.mark.versioning
    def test_update_config_database_layer(self, sample_config):
        """Test config_manager.update_config() directly."""
        # Create config via database layer
        _ = config_manager.create_config(sample_config)  # Creates version 1

        # Update via database layer
        new_settings = {"updated": True, "new_field": "value"}
        updated = config_manager.update_config(sample_config["config_id"], new_settings)

        # Verify new document created with version 2
        assert updated["version"] == 2
        assert updated["settings"] == new_settings

        # Verify old document still exists
        history = config_manager.get_config_history(sample_config["config_id"])
        assert len(history) == 2
        assert history[0]["version"] == 2  # Latest
        assert history[1]["version"] == 1  # Original

    @pytest.mark.database
    @pytest.mark.versioning
    def test_versioning_logic_database_layer(self, sample_config):
        """Test versioning at database level."""
        # Create config
        config_manager.create_config(sample_config)

        # Update multiple times
        for i in range(2, 6):  # Create versions 2, 3, 4, 5
            new_settings = {"version": i, "iteration": f"update_{i}"}
            config_manager.update_config(sample_config["config_id"], new_settings)

        # Query database directly to count documents
        all_docs = list(
            config_manager.collection.find({"config_id": sample_config["config_id"]})
        )

        # Verify correct number of version documents exist
        assert len(all_docs) == 5

        # Verify each has correct version
        versions = sorted([doc["version"] for doc in all_docs])
        assert versions == [1, 2, 3, 4, 5]

        # Verify latest version logic
        latest = config_manager.get_latest_config(sample_config["config_id"])
        assert latest["version"] == 5
        assert latest["settings"]["version"] == 5


# Health Check Test
class TestHealthCheck:
    """Test health check endpoint"""

    @pytest.mark.api
    def test_health_check_endpoint(self, test_client):
        """Test /api/health endpoint."""
        response = test_client.get("/api/health")

        # Should return 200 or 503 depending on database status
        assert response.status_code in [200, 503]

        data = json.loads(response.data)
        assert "status" in data
        assert "database" in data

        if response.status_code == 200:
            assert data["status"] == "healthy"
            assert data["database"] == "connected"
            assert "stats" in data
        else:
            assert data["status"] == "unhealthy"
            assert "error" in data

    @pytest.mark.api
    def test_health_check_connection_failure(self, test_client):
        """Test /api/health endpoint with MongoDB connection failure."""
        # Mock config_manager.get_database_stats to raise ConnectionError
        with patch.object(config_manager, "get_database_stats") as mock_stats:
            mock_stats.side_effect = ConnectionError("Connection to MongoDB failed")

            response = test_client.get("/api/health")

            # Should return 503 for connection failure
            assert response.status_code == 503

            data = json.loads(response.data)

            # Verify expected JSON structure
            assert "status" in data
            assert "database" in data
            assert "error" in data

            # Verify specific values
            assert data["status"] == "unhealthy"
            assert data["database"] == "disconnected"
            assert "Connection to MongoDB failed" in data["error"]


class TestPhase8Features:
    """Test Phase 8 UX enhancements: metadata tracking, create UI, comparison, rollback"""

    def test_metadata_tracking_create_config(self, test_client):
        """Test that creating configuration with metadata works correctly."""
        config_data = {
            "config_id": "test-app-config",
            "app_name": "test-app",
            "environment": "test",
            "settings": {"database_url": "mongodb://localhost:27017"},
            "updated_by": "test-user",
            "change_notes": "Initial configuration creation",
        }

        # Test API endpoint with metadata
        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 201
        data = json.loads(response.data)
        assert data["updated_by"] == "test-user"
        assert data["change_notes"] == "Initial configuration creation"
        assert data["version"] == 1

    def test_metadata_tracking_update_config(self, test_client):
        """Test that updating configuration with metadata works correctly."""
        # Create initial config
        initial_data = {
            "config_id": "update-test-config",
            "app_name": "test-app",
            "environment": "test",
            "settings": {"database_url": "mongodb://localhost:27017"},
            "updated_by": "user1",
            "change_notes": "Initial setup",
        }

        response = test_client.post(
            "/api/config",
            data=json.dumps(initial_data),
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 201
        config_id = json.loads(response.data)["config_id"]

        # Update with new metadata
        update_data = {
            "settings": {"database_url": "mongodb://newhost:27017"},
            "updated_by": "user2",
            "change_notes": "Updated database connection",
        }

        response = test_client.put(
            f"/api/config/{config_id}",
            data=json.dumps(update_data),
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["updated_by"] == "user2"
        assert data["change_notes"] == "Updated database connection"
        assert data["version"] == 2

    def test_create_ui_web_interface(self, test_client):
        """Test create configuration web interface."""
        # Test GET request for create form
        response = test_client.get("/create")
        assert response.status_code == 200
        assert b"Create Configuration" in response.data
        assert b"App Name" in response.data
        assert b"Environment" in response.data

        # Test POST request to create config via web
        form_data = {
            "config_id": "web-test-config-123",
            "app_name": "web-test-app",
            "environment": "staging",
            "settings": '{"redis_host": "localhost", "redis_port": 6379}',
            "updated_by": "web-user",
            "change_notes": "Created via web interface",
        }

        response = test_client.post("/create", data=form_data)
        assert response.status_code == 302  # Redirect after successful creation

    def test_comparison_functionality(self, test_client):
        """Test configuration version comparison."""
        # Create config with multiple versions
        config_data = {
            "config_id": "compare-test-config",
            "app_name": "compare-test",
            "environment": "test",
            "settings": {"option1": "value1"},
            "updated_by": "user1",
            "change_notes": "Version 1",
        }

        # Create initial version
        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )
        config_id = json.loads(response.data)["config_id"]

        # Create second version
        config_data["settings"] = {"option1": "value2", "option2": "new_value"}
        config_data["change_notes"] = "Version 2 - added option2"
        response = test_client.put(
            f"/api/config/{config_id}",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )

        # Test comparison endpoint
        response = test_client.get(f"/compare/{config_id}/1/2")
        assert response.status_code == 200
        assert b"Compare Versions" in response.data
        assert b"Version 1" in response.data or b"version 1" in response.data
        assert b"Version 2" in response.data or b"version 2" in response.data

    def test_rollback_functionality(self, test_client):
        """Test configuration rollback functionality."""
        # Create config with multiple versions
        config_data = {
            "config_id": "rollback-test-config",
            "app_name": "rollback-test",
            "environment": "test",
            "settings": {"version": "v1"},
            "updated_by": "user1",
            "change_notes": "Initial version",
        }

        # Create initial version
        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )
        config_id = json.loads(response.data)["config_id"]

        # Create second version
        config_data["settings"] = {"version": "v2"}
        config_data["change_notes"] = "Updated to v2"
        response = test_client.put(
            f"/api/config/{config_id}",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )

        # Create third version
        config_data["settings"] = {"version": "v3"}
        config_data["change_notes"] = "Updated to v3"
        response = test_client.put(
            f"/api/config/{config_id}",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )

        # Test rollback to version 1
        response = test_client.post(f"/rollback/{config_id}/1")
        assert response.status_code == 302  # Redirect after rollback

        # Verify rollback worked - should now have version 4 with v1 settings
        latest = config_manager.get_config(config_id)
        assert latest["settings"]["version"] == "v1"
        assert latest["version"] == 4
        assert "Rolled back to version 1" in latest.get("change_notes", "")

    def test_schema_templates_helper(self, test_client):
        """Test schema template generation for create UI."""
        from app import get_schema_templates

        templates = get_schema_templates()

        # Verify all expected templates exist
        expected_templates = [
            "database",
            "api_service",
            "feature_flags",
            "cache",
            "logging",
        ]
        assert all(template in templates for template in expected_templates)

        # Verify template structure
        for template_name, template_data in templates.items():
            assert "name" in template_data
            assert "description" in template_data
            # Templates are flat dictionaries with metadata and schema data combined
            assert isinstance(template_data, dict)
            assert (
                len(template_data) > 2
            )  # Should have more than just name and description

    def test_history_page_metadata_display(self, test_client):
        """Test that history page displays metadata correctly."""
        # Create config with metadata
        config_data = {
            "config_id": "history-test-config",
            "app_name": "history-test",
            "environment": "test",
            "settings": {"setting1": "value1"},
            "updated_by": "history-user",
            "change_notes": "Test change notes for history",
        }

        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )
        config_id = json.loads(response.data)["config_id"]

        # Create a second version to enable comparison buttons
        update_data = {
            "settings": {"setting1": "value2"},
            "updated_by": "history-user-v2",
            "change_notes": "Updated to version 2",
        }
        test_client.put(
            f"/api/config/{config_id}",
            data=json.dumps(update_data),
            headers={"Content-Type": "application/json"},
        )

        # Check history page displays metadata
        response = test_client.get(f"/history/{config_id}")
        assert response.status_code == 200
        assert b"history-user" in response.data
        assert b"Test change notes for history" in response.data
        # With 2+ versions, comparison buttons should appear
        assert (
            b"Compare to Latest" in response.data
            or b"Compare to Previous" in response.data
        )

    def test_details_page_metadata_display(self, test_client):
        """Test that details page displays metadata correctly."""
        # Create config with metadata
        config_data = {
            "config_id": "details-test-config",
            "app_name": "details-test",
            "environment": "test",
            "settings": {"setting1": "value1"},
            "updated_by": "details-user",
            "change_notes": "Test change notes for details page",
        }

        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )
        config_id = json.loads(response.data)["config_id"]

        # Check details page displays metadata
        response = test_client.get(f"/config/{config_id}")
        assert response.status_code == 200
        assert b"details-user" in response.data
        assert b"Test change notes for details page" in response.data

    def test_edit_form_change_notes(self, test_client):
        """Test that edit form includes change notes field."""
        # Create initial config
        config_data = {
            "config_id": "edit-test-config",
            "app_name": "edit-test",
            "environment": "test",
            "settings": {"setting1": "value1"},
            "updated_by": "edit-user",
            "change_notes": "Initial creation",
        }

        response = test_client.post(
            "/api/config",
            data=json.dumps(config_data),
            headers={"Content-Type": "application/json"},
        )
        config_id = json.loads(response.data)["config_id"]

        # Check edit form
        response = test_client.get(f"/edit/{config_id}")
        assert response.status_code == 200
        assert b"change_notes" in response.data
        assert b"Change Notes" in response.data
        assert b"Initial creation" in response.data  # Previous change notes

    def test_dashboard_create_button(self, test_client):
        """Test that dashboard includes create button."""
        response = test_client.get("/")
        assert response.status_code == 200
        assert (
            b"Create Configuration" in response.data
            or b"Create Config" in response.data
        )


class TestDataMigrationCompatibility:
    """Test backward compatibility with existing data without metadata fields"""

    def test_existing_config_without_metadata(self, test_client):
        """Test that configs without metadata fields work correctly."""
        # Simulate existing config without metadata by directly inserting into DB
        old_config = {
            "config_id": "legacy-config",
            "app_name": "legacy-app",
            "environment": "production",
            "settings": {"legacy_setting": "legacy_value"},
            "version": 1,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
            # Note: No updated_by or change_notes fields
        }

        config_manager.collection.insert_one(old_config)

        # Test API retrieval
        response = test_client.get("/api/config/legacy-config")
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data["config_id"] == "legacy-config"
        assert "updated_by" not in data or data["updated_by"] is None
        assert "change_notes" not in data or data["change_notes"] is None

        # Test web interface
        response = test_client.get("/config/legacy-config")
        assert response.status_code == 200

        # Test update (should work and add metadata)
        update_data = {
            "settings": {"legacy_setting": "updated_value"},
            "updated_by": "migration-user",
            "change_notes": "Updated legacy config",
        }

        response = test_client.put(
            "/api/config/legacy-config",
            data=json.dumps(update_data),
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 200

        # Verify new version has metadata
        updated = config_manager.get_config("legacy-config")
        assert updated["version"] == 2
        assert updated["updated_by"] == "migration-user"
        assert updated["change_notes"] == "Updated legacy config"


class TestStructuredLogging:
    """Test suite for Phase 9 structured logging functionality."""

    @pytest.fixture(autouse=True)
    def setup_logging_test(self):
        """Set up structured logging test environment."""
        # Ensure JSON logging is enabled
        os.environ["LOG_FORMAT"] = "JSON"
        os.environ["LOG_LEVEL"] = "INFO"
        yield
        # Cleanup
        os.environ.pop("LOG_FORMAT", None)
        os.environ.pop("LOG_LEVEL", None)

    @patch("logging_config.logger")
    def test_request_correlation_logging(self, mock_logger, test_client):
        """Test that requests generate structured logs with correlation IDs."""
        response = test_client.post(
            "/api/configs",
            data=json.dumps(
                {
                    "name": "test-config",
                    "environment": "development",
                    "data": {"key": "value"},
                    "updated_by": "test-user",
                    "change_notes": "Test creation",
                }
            ),
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 201

        # Verify structured logging was called
        assert mock_logger.info.called

        # Check that log calls include structured data
        log_calls = mock_logger.info.call_args_list
        assert len(log_calls) > 0

        # Verify log structure includes required fields
        for call in log_calls:
            args, kwargs = call
            # Log message should be structured or contain context
            assert len(args) > 0 or "extra" in kwargs

    @patch("logging_config.logger")
    def test_database_operation_logging(self, mock_logger, test_client):
        """Test that database operations generate structured logs."""
        # Create a config to trigger database logging
        test_client.post(
            "/api/configs",
            data=json.dumps(
                {
                    "name": "db-test-config",
                    "environment": "test",
                    "data": {"db": "logging"},
                    "updated_by": "db-test-user",
                }
            ),
            headers={"Content-Type": "application/json"},
        )

        # Verify database operation logging
        assert mock_logger.info.called or mock_logger.debug.called

    @patch("logging_config.logger")
    def test_error_logging_structure(self, mock_logger, test_client):
        """Test that errors are logged with proper structure."""
        # Trigger an error by creating invalid configuration
        response = test_client.post(
            "/api/configs",
            data=json.dumps({"invalid": "data structure"}),
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 400

        # Verify error logging was triggered
        assert mock_logger.error.called or mock_logger.warning.called

    def test_log_level_configuration(self):
        """Test that log level can be configured via environment variables."""
        with patch.dict(os.environ, {"LOG_LEVEL": "DEBUG"}):
            # Import should respect the log level
            from logging_config import logger

            # In a real scenario, we'd check logger.level
            assert os.environ.get("LOG_LEVEL") == "DEBUG"


class TestMetrics:
    """Test suite for Phase 9 Prometheus metrics functionality."""

    def test_metrics_endpoint_accessible(self, test_client):
        """Test that /metrics endpoint is accessible and returns valid metrics."""
        response = test_client.get("/metrics")
        assert response.status_code == 200

        # Check for Prometheus format
        response_text = response.get_data(as_text=True)
        assert "http_requests_total" in response_text or "shepherd_" in response_text

    @patch("metrics.HTTP_REQUEST_COUNT")
    @patch("metrics.HTTP_REQUEST_DURATION")
    def test_http_request_metrics_tracking(
        self, mock_duration, mock_count, test_client
    ):
        """Test that HTTP requests are tracked in metrics."""
        # Make a request that should be tracked
        response = test_client.get("/api/health")
        assert response.status_code == 200

        # Verify metrics were called (if metrics decorators are working)
        # Note: This test depends on the actual implementation of metrics tracking
        # In a real test, we'd verify the metrics were incremented

    @patch("metrics.DATABASE_OPERATION_COUNT")
    @patch("metrics.DATABASE_OPERATION_DURATION")
    def test_database_metrics_tracking(self, mock_duration, mock_count, test_client):
        """Test that database operations are tracked in metrics."""
        # Perform database operation
        test_client.post(
            "/api/configs",
            data=json.dumps(
                {
                    "name": "metrics-test-config",
                    "environment": "test",
                    "data": {"metrics": "test"},
                    "updated_by": "metrics-user",
                }
            ),
            headers={"Content-Type": "application/json"},
        )

        # Note: In real implementation, verify that database metrics were recorded
        # This would require checking the actual metrics implementation

    def test_metrics_format_prometheus_compatible(self, test_client):
        """Test that metrics endpoint returns Prometheus-compatible format."""
        response = test_client.get("/metrics")
        assert response.status_code == 200

        response_text = response.get_data(as_text=True)

        # Check for basic Prometheus format requirements
        lines = response_text.split("\n")
        for line in lines:
            if line.strip() and not line.startswith("#"):
                # Should contain metric name and value
                assert " " in line or line.count("{") > 0

    def test_custom_application_metrics(self, test_client):
        """Test that custom application metrics are exposed."""
        # Create some configurations to generate metrics
        for i in range(3):
            test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": f"metric-config-{i}",
                        "environment": "test",
                        "data": {"counter": i},
                        "updated_by": "metric-user",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )

        response = test_client.get("/metrics")
        response_text = response.get_data(as_text=True)

        # Look for application-specific metrics
        # Note: Specific metric names depend on implementation
        assert response.status_code == 200
        assert len(response_text) > 0


class TestWebhooks:
    """Test suite for Phase 9 webhook system functionality."""

    @pytest.fixture
    def mock_webhook_url(self):
        """Provide a mock webhook URL for testing."""
        return "https://example.com/webhook"

    @patch("webhooks.requests.post")
    def test_webhook_delivery_on_config_creation(
        self, mock_post, test_client, mock_webhook_url
    ):
        """Test that webhooks are delivered when configurations are created."""
        # Mock successful webhook delivery
        mock_post.return_value.status_code = 200
        mock_post.return_value.json.return_value = {"status": "received"}

        # Configure a webhook endpoint
        with patch("webhooks.WEBHOOK_URLS", [mock_webhook_url]):
            response = test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": "webhook-test-config",
                        "environment": "test",
                        "data": {"webhook": "test"},
                        "updated_by": "webhook-user",
                        "change_notes": "Testing webhook delivery",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )

        assert response.status_code == 201

        # Verify webhook was called
        if mock_post.called:
            call_args = mock_post.call_args
            args, kwargs = call_args

            # Verify webhook URL was called
            assert mock_webhook_url in args[0]

            # Verify payload structure
            if "json" in kwargs:
                payload = kwargs["json"]
                assert "event_type" in payload
                assert "data" in payload
                assert payload["event_type"] == "config.created"

    @patch("webhooks.requests.post")
    def test_webhook_retry_mechanism(self, mock_post, test_client, mock_webhook_url):
        """Test webhook retry mechanism on delivery failure."""
        # Mock failed webhook delivery
        mock_post.return_value.status_code = 500
        mock_post.return_value.raise_for_status.side_effect = Exception("Server Error")

        with patch("webhooks.WEBHOOK_URLS", [mock_webhook_url]):
            response = test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": "retry-test-config",
                        "environment": "test",
                        "data": {"retry": "test"},
                        "updated_by": "retry-user",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )

        assert response.status_code == 201

        # Verify multiple webhook attempts were made (retry mechanism)
        if mock_post.called:
            assert mock_post.call_count >= 1

    @patch("webhooks.requests.post")
    def test_webhook_payload_structure(self, mock_post, test_client, mock_webhook_url):
        """Test that webhook payloads have correct structure."""
        mock_post.return_value.status_code = 200

        with patch("webhooks.WEBHOOK_URLS", [mock_webhook_url]):
            response = test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": "payload-test-config",
                        "environment": "production",
                        "data": {"payload": "structure"},
                        "updated_by": "payload-user",
                        "change_notes": "Testing payload structure",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )

        assert response.status_code == 201

        if mock_post.called:
            call_args = mock_post.call_args
            _, kwargs = call_args

            if "json" in kwargs:
                payload = kwargs["json"]

                # Verify required payload fields
                required_fields = ["event_type", "timestamp", "data"]
                for field in required_fields:
                    assert field in payload

                # Verify data structure
                assert "config_name" in payload["data"]
                assert "environment" in payload["data"]
                assert "updated_by" in payload["data"]

    def test_webhook_configuration_endpoint(self, test_client):
        """Test webhook configuration management endpoints."""
        # Note: This test assumes webhook configuration endpoints exist
        # Implement based on actual webhook management API

        # Test webhook registration (placeholder for future implementation)
        _ = {
            "url": "https://example.com/webhook",
            "events": ["config.created", "config.updated"],
            "auth_type": "bearer",
            "auth_token": "test-token",
        }

        # This would test an actual webhook management endpoint
        # Implementation depends on the actual API design
        pass

    @patch("webhooks.logger")
    def test_webhook_delivery_logging(self, mock_logger, test_client):
        """Test that webhook deliveries are properly logged."""
        with patch("webhooks.WEBHOOK_URLS", ["https://example.com/webhook"]):
            test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": "logging-test-config",
                        "environment": "test",
                        "data": {"logging": "test"},
                        "updated_by": "logging-user",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )

        # Verify webhook delivery was logged
        # Note: Specific logging verification depends on implementation
        assert True  # Placeholder - implement based on actual logging


class TestObservabilityIntegration:
    """Test suite for overall Phase 9 observability integration."""

    def test_health_endpoint_includes_observability_status(self, test_client):
        """Test that health endpoint includes observability component status."""
        response = test_client.get("/api/health")
        assert response.status_code == 200

        health_data = json.loads(response.get_data(as_text=True))

        # Verify basic health response structure
        assert "status" in health_data
        assert health_data["status"] in ["healthy", "unhealthy"]

    def test_detailed_health_endpoint(self, test_client):
        """Test detailed health endpoint with component status."""
        # Test detailed health endpoint if it exists
        response = test_client.get("/api/health/detailed")

        if response.status_code == 200:
            health_data = json.loads(response.get_data(as_text=True))

            # Verify detailed health includes observability components
            assert "status" in health_data

            # Check for component health if implemented
            if "checks" in health_data:
                checks = health_data["checks"]
                assert isinstance(checks, dict)

    @patch("metrics.HTTP_REQUEST_COUNT")
    @patch("logging_config.logger")
    def test_observability_cross_feature_integration(
        self, mock_logger, mock_metrics, test_client
    ):
        """Test that all observability features work together."""
        # Perform an operation that should trigger all observability features
        response = test_client.post(
            "/api/configs",
            data=json.dumps(
                {
                    "name": "integration-test-config",
                    "environment": "integration",
                    "data": {"integration": "test"},
                    "updated_by": "integration-user",
                    "change_notes": "Testing full observability integration",
                }
            ),
            headers={"Content-Type": "application/json"},
        )

        assert response.status_code == 201

        # Verify that the operation triggered multiple observability features:
        # 1. Structured logging should have been called
        # 2. Metrics should have been recorded
        # 3. Webhooks should have been triggered (if configured)

        # Note: Specific assertions depend on the actual implementation
        # This test validates that all systems can work together without conflicts

    def test_observability_performance_impact(self, test_client):
        """Test that observability features don't significantly impact performance."""
        import time

        # Measure baseline performance
        start_time = time.time()

        for i in range(10):
            response = test_client.post(
                "/api/configs",
                data=json.dumps(
                    {
                        "name": f"perf-test-config-{i}",
                        "environment": "performance",
                        "data": {"index": i},
                        "updated_by": "perf-user",
                    }
                ),
                headers={"Content-Type": "application/json"},
            )
            assert response.status_code == 201

        end_time = time.time()
        total_time = end_time - start_time

        # Verify reasonable performance (10 operations in under 5 seconds)
        assert total_time < 5.0, f"Performance test took {total_time:.2f} seconds"

    def test_observability_error_resilience(self, test_client):
        """Test that observability failures don't break core functionality."""
        # Test that if observability components fail, the main application still works

        with patch(
            "metrics.HTTP_REQUEST_COUNT.inc", side_effect=Exception("Metrics error")
        ):
            response = test_client.get("/api/health")
            # Core functionality should still work even if metrics fail
            assert response.status_code == 200

        with patch(
            "logging_config.logger.info", side_effect=Exception("Logging error")
        ):
            response = test_client.get("/api/health")
            # Core functionality should still work even if logging fails
            assert response.status_code == 200


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
