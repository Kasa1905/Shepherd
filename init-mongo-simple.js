// Simple MongoDB Initialization Script for Local Development
// This script runs when MongoDB container starts for the first time

// Switch to shepherd database
db = db.getSiblingDB('shepherd');

// Create a sample configuration to verify setup
db.configurations.insertOne({
    config_id: "welcome",
    app_name: "Shepherd CMS",
    environment: "local",
    version: 1,
    settings: {
        message: "Welcome to Shepherd Configuration Management System!",
        setup_complete: true,
        first_run: new Date().toISOString()
    },
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    updated_by: "system",
    change_notes: "Initial setup",
    metadata: {
        type: "system",
        auto_generated: true
    }
});

print('✅ Shepherd database initialized successfully!');
print('📝 Sample configuration created: welcome');
print('🚀 Ready to use!');
