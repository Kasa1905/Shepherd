// MongoDB Initialization Script for Shepherd CMS (safe version)
// IMPORTANT: No real credentials in this file. Uses env variables with sane local defaults.

print('Starting MongoDB initialization for Shepherd (safe)...');

// Select database
var dbName = 'shepherd';
db = db.getSiblingDB(dbName);

// Resolve env vars defensively (mongosh has `process` only in some contexts)
function getenv(name, fallback) {
  try {
    if (typeof process !== 'undefined' && process.env && process.env[name]) {
      return process.env[name];
    }
  } catch (e) {}
  return fallback;
}

var appUser = getenv('MONGODB_APP_USERNAME', 'shepherd_user');
var appPass = getenv('MONGODB_APP_PASSWORD', 'change_me');

// Create application user with readWrite role
try {
  db.createUser({
    user: appUser,
    pwd: appPass,
    roles: [{ role: 'readWrite', db: dbName }]
  });
  print('Created application user with readWrite permissions.');
} catch (e) {
  if (e.codeName === 'DuplicateKey') {
    print('User already exists, skipping user creation.');
  } else {
    throw e;
  }
}

// Create collections and indexes
try { db.createCollection('configurations'); } catch (e) { /* may already exist */ }

db.configurations.createIndex({ config_id: 1, version: -1 }, { unique: true, background: true });
db.configurations.createIndex({ config_id: 1 }, { background: true });
db.configurations.createIndex({ app_name: 1, environment: 1 }, { background: true });
db.configurations.createIndex({ created_at: 1 }, { background: true });

// Seed demo data with placeholders (safe; replace via app UI/API)
var now = new Date().toISOString();
var sampleConfigs = [
  {
    config_id: 'database-config-dev', app_name: 'database-config', environment: 'development', version: 1,
    settings: { host: 'localhost', port: 5432, database: 'app_dev', username: '<DB_USERNAME>', password: '<DB_PASSWORD>', pool_size: 10, timeout: 30 },
    created_at: now, updated_at: now
  },
  {
    config_id: 'database-config-prod', app_name: 'database-config', environment: 'production', version: 1,
    settings: { host: 'prod-db.company.com', port: 5432, database: 'app_prod', username: '<DB_USERNAME>', password: '<DB_PASSWORD>', pool_size: 50, timeout: 60, ssl: true, backup_enabled: true },
    created_at: now, updated_at: now
  },
  {
    config_id: 'api-config-dev', app_name: 'api-config', environment: 'development', version: 1,
    settings: { base_url: 'https://api-dev.company.com', timeout: 30, retries: 3, rate_limit: 100, authentication: { type: 'bearer', token_refresh_url: '/auth/refresh' }, endpoints: { users: '/api/v1/users', orders: '/api/v1/orders', products: '/api/v1/products' } },
    created_at: now, updated_at: now
  },
  {
    config_id: 'cache-config-prod', app_name: 'cache-config', environment: 'production', version: 1,
    settings: { redis: { host: 'redis-cluster.company.com', port: 6379, password: '<REDIS_PASSWORD>', db: 0, cluster_mode: true, nodes: ['redis-1.company.com:6379','redis-2.company.com:6379','redis-3.company.com:6379'] }, ttl: { default: 3600, user_sessions: 7200, api_cache: 300 }, compression: true },
    created_at: now, updated_at: now
  }
];

try {
  db.configurations.insertMany(sampleConfigs, { ordered: false });
  print('Inserted sample configurations.');
} catch (e) {
  print('Seeding skipped or partially inserted: ' + e);
}

// Add a v2 example for versioning
try {
  db.configurations.insertOne({
    config_id: 'database-config-dev', app_name: 'database-config', environment: 'development', version: 2,
    settings: { host: 'localhost', port: 5432, database: 'app_dev', username: '<DB_USERNAME>', password: '<DB_PASSWORD>', pool_size: 15, timeout: 45, connection_retry: 3, health_check_interval: 60 },
    created_at: now, updated_at: now
  });
  print('Created version 2 of database-config-dev');
} catch (e) {
  print('v2 insert skipped: ' + e);
}

var configCount = db.configurations.countDocuments();
var indexCount = db.configurations.getIndexes().length;
print('Initialization complete:');
print('- Configurations inserted: ' + configCount);
print('- Indexes created: ' + indexCount);
print('- Database: ' + dbName);
print('- User: application user (readWrite permissions)');
