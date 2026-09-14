const { executeQuery } = require('../config/database');

/**
 * Database setup script
 * Creates necessary tables if they don't exist
 */
async function setupDatabase() {
    try {
        console.log('Starting database setup...');

        // Create users table
        const createUsersTableQuery = `
            IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='users' AND xtype='U')
            CREATE TABLE users (
                id INT PRIMARY KEY IDENTITY(1,1),
                name NVARCHAR(255) NOT NULL,
                email NVARCHAR(255) NOT NULL UNIQUE,
                age INT,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )
        `;

        // Create sample data insertion query
        const insertSampleDataQuery = `
            IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@example.com')
            INSERT INTO users (name, email, age, created_at, updated_at)
            VALUES 
                ('Admin User', 'admin@example.com', 30, GETDATE(), GETDATE()),
                ('John Doe', 'john.doe@example.com', 25, GETDATE(), GETDATE()),
                ('Jane Smith', 'jane.smith@example.com', 28, GETDATE(), GETDATE())
        `;

        // Create indexes for better performance
        const createIndexesQuery = `
            IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_users_email' AND object_id = OBJECT_ID('users'))
            CREATE INDEX IX_users_email ON users(email);
            
            IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_users_created_at' AND object_id = OBJECT_ID('users'))
            CREATE INDEX IX_users_created_at ON users(created_at);
        `;

        // Execute table creation
        console.log('Creating users table...');
        await executeQuery(createUsersTableQuery);
        console.log('Users table created or already exists.');

        // Execute index creation
        console.log('Creating indexes...');
        await executeQuery(createIndexesQuery);
        console.log('Indexes created or already exist.');

        // Insert sample data
        console.log('Inserting sample data...');
        await executeQuery(insertSampleDataQuery);
        console.log('Sample data inserted or already exists.');

        // Verify table structure
        const verifyQuery = `
            SELECT 
                TABLE_NAME,
                COLUMN_NAME,
                DATA_TYPE,
                IS_NULLABLE,
                CHARACTER_MAXIMUM_LENGTH
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'users'
            ORDER BY ORDINAL_POSITION
        `;

        const structure = await executeQuery(verifyQuery);
        console.log('\nUsers table structure:');
        console.table(structure.recordset);

        // Count records
        const countQuery = 'SELECT COUNT(*) as user_count FROM users';
        const countResult = await executeQuery(countQuery);
        console.log(`\nTotal users in database: ${countResult.recordset[0].user_count}`);

        console.log('\n✅ Database setup completed successfully!');
        
    } catch (error) {
        console.error('❌ Database setup failed:', error.message);
        throw error;
    }
}

/**
 * Drop all tables (for development/reset purposes)
 * WARNING: This will delete all data!
 */
async function resetDatabase() {
    try {
        console.log('WARNING: This will delete all data in the users table!');
        
        const dropTableQuery = `
            IF EXISTS (SELECT * FROM sysobjects WHERE name='users' AND xtype='U')
            DROP TABLE users
        `;

        await executeQuery(dropTableQuery);
        console.log('Database reset completed. All tables dropped.');
        
    } catch (error) {
        console.error('Database reset failed:', error.message);
        throw error;
    }
}

/**
 * Check database connection and basic functionality
 */
async function testDatabaseConnection() {
    try {
        console.log('Testing database connection...');
        
        // Test simple query
        const result = await executeQuery('SELECT @@VERSION as version');
        console.log('✅ Database connection successful');
        console.log('SQL Server version:', result.recordset[0].version);
        
        // Test table existence
        const tableCheck = await executeQuery(`
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_NAME = 'users'
        `);
        
        if (tableCheck.recordset.length > 0) {
            console.log('✅ Users table exists');
        } else {
            console.log('⚠️ Users table does not exist');
        }
        
        return true;
    } catch (error) {
        console.error('❌ Database connection test failed:', error.message);
        return false;
    }
}

// Export functions
module.exports = {
    setupDatabase,
    resetDatabase,
    testDatabaseConnection
};

// If this script is run directly
if (require.main === module) {
    const command = process.argv[2];
    
    async function run() {
        try {
            if (command === 'reset') {
                await resetDatabase();
                console.log('Database reset completed.');
            } else if (command === 'test') {
                await testDatabaseConnection();
            } else {
                await setupDatabase();
            }
            process.exit(0);
        } catch (error) {
            console.error('Script execution failed:', error);
            process.exit(1);
        }
    }
    
    run();
}