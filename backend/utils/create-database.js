const sql = require('mssql');
require('dotenv').config();

/**
 * Create database if it doesn't exist
 * This script connects to master database first
 */
async function createDatabase() {
    let masterPool = null;
    
    try {
        // Connect to master database first
        let serverName = process.env.DB_SERVER || '.';
        // Handle '.' as localhost for Node.js mssql
        if (serverName === '.') {
            serverName = 'localhost';
        }
        
        const port = parseInt(process.env.DB_PORT) || 1433;
        
        // Use connection string for SQL Authentication
        const connectionString = `Server=${serverName},${port};Database=master;User Id=${process.env.DB_USER};Password=${process.env.DB_PASSWORD};TrustServerCertificate=True;`;
        
        console.log('Connecting to SQL Server (master database)...');
        console.log(`Server: ${serverName}:${port}`);
        console.log(`User: ${process.env.DB_USER}`);
        
        masterPool = await sql.connect(connectionString);
        console.log('✅ Connected to SQL Server successfully');

        const targetDatabase = process.env.DB_DATABASE || 'IoT_Database';
        
        // Check if database exists
        const checkDbQuery = `
            SELECT name FROM sys.databases 
            WHERE name = '${targetDatabase}'
        `;
        
        const result = await masterPool.request().query(checkDbQuery);
        
        if (result.recordset.length > 0) {
            console.log(`✅ Database '${targetDatabase}' already exists`);
        } else {
            // Create database
            console.log(`Creating database '${targetDatabase}'...`);
            const createDbQuery = `CREATE DATABASE [${targetDatabase}]`;
            await masterPool.request().query(createDbQuery);
            console.log(`✅ Database '${targetDatabase}' created successfully`);
        }

        // Close connection
        await masterPool.close();
        
        return true;
    } catch (error) {
        console.error('❌ Error:', error.message);
        
        if (error.message.includes('Login failed')) {
            console.error('\nTroubleshooting:');
            console.error('1. Ensure SQL Server is running');
            console.error('2. Ensure Windows Authentication is enabled');
            console.error('3. Ensure your Windows user has SQL Server access');
        }
        
        if (masterPool) {
            try {
                await masterPool.close();
            } catch (e) {}
        }
        
        throw error;
    }
}

// Run if called directly
if (require.main === module) {
    createDatabase()
        .then(() => {
            console.log('\n✅ Database setup complete!');
            console.log('You can now run: npm run db:setup');
            process.exit(0);
        })
        .catch((error) => {
            console.error('\n❌ Database creation failed');
            process.exit(1);
        });
}

module.exports = { createDatabase };