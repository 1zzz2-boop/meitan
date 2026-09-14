# HarmonyOS IoT Backend

A Node.js backend service for HarmonyOS IoT application with SQL Server database connectivity.

## Features

- RESTful API with Express.js
- SQL Server database connectivity using mssql package
- CRUD operations for user management
- Health check endpoints
- Environment-based configuration
- Database migration and setup scripts
- CORS enabled
- Security headers with Helmet
- Request logging with Morgan

## Prerequisites

- Node.js (v18 or higher)
- SQL Server (local or remote instance)
- npm or yarn package manager

## Installation

1. Clone the repository
2. Navigate to the backend directory:
   ```bash
   cd backend
   ```
3. Install dependencies:
   ```bash
   npm install
   ```
4. Copy environment variables file:
   ```bash
   cp .env.example .env
   ```
5. Configure your `.env` file with your SQL Server credentials

## Database Setup

### 1. Configure SQL Server
Ensure SQL Server is running and accessible. Update the following in your `.env` file:

```env
DB_SERVER=localhost
DB_PORT=1433
DB_DATABASE=your_database_name
DB_USER=your_username
DB_PASSWORD=your_password
DB_ENCRYPT=false
```

### 2. Run Database Setup
Initialize the database with required tables:

```bash
npm run db:setup
```

This will:
- Create the `users` table if it doesn't exist
- Create necessary indexes
- Insert sample data

### 3. Test Database Connection
Verify database connectivity:

```bash
npm run db:test
```

## Running the Application

### Development Mode
```bash
npm run dev
```
Starts the server with nodemon for automatic restart on file changes.

### Production Mode
```bash
npm start
```

The server will start on `http://localhost:3000` (or the port specified in your `.env` file).

## API Endpoints

### Health Check
- `GET /api/health` - Basic health check
- `GET /api/health/detailed` - Detailed system health information

### User Management
- `GET /api/users` - Get all users
- `GET /api/users/:id` - Get user by ID
- `POST /api/users` - Create a new user
- `PUT /api/users/:id` - Update user by ID
- `DELETE /api/users/:id` - Delete user by ID
- `GET /api/users/search/:email` - Search users by email

### Example Requests

#### Create a new user
```bash
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "age": 30
  }'
```

#### Get all users
```bash
curl http://localhost:3000/api/users
```

#### Get user by ID
```bash
curl http://localhost:3000/api/users/1
```

## Project Structure

```
backend/
├── src/
│   └── app.js              # Main Express application
├── config/
│   └── database.js         # Database configuration and connection
├── controllers/
│   └── user.controller.js  # User controller
├── routes/
│   ├── health.routes.js    # Health check routes
│   └── user.routes.js      # User routes
├── services/
│   └── user.service.js     # User service layer
├── models/                 # Data models (to be implemented)
├── middleware/             # Custom middleware (to be implemented)
├── utils/
│   └── database-setup.js   # Database migration and setup
├── server.js               # Server entry point
├── .env                    # Environment variables (gitignored)
├── .env.example            # Environment variables template
├── package.json            # Dependencies and scripts
└── README.md               # This file
```

## Database Schema

### Users Table
```sql
CREATE TABLE users (
    id INT PRIMARY KEY IDENTITY(1,1),
    name NVARCHAR(255) NOT NULL,
    email NVARCHAR(255) NOT NULL UNIQUE,
    age INT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| DB_SERVER | SQL Server hostname | localhost |
| DB_PORT | SQL Server port | 1433 |
| DB_DATABASE | Database name | - |
| DB_USER | Database username | - |
| DB_PASSWORD | Database password | - |
| DB_ENCRYPT | Use encryption | false |
| PORT | Server port | 3000 |
| NODE_ENV | Environment mode | development |

## Available Scripts

- `npm start` - Start the server in production mode
- `npm run dev` - Start the server in development mode with hot reload
- `npm run db:setup` - Set up database tables and sample data
- `npm run db:reset` - Reset database (WARNING: deletes all data)
- `npm run db:test` - Test database connection

## Troubleshooting

### Database Connection Issues
1. Ensure SQL Server is running
2. Verify credentials in `.env` file
3. Check if TCP/IP is enabled in SQL Server Configuration Manager
4. Verify firewall settings allow connections on port 1433

### Port Already in Use
Change the `PORT` variable in `.env` file to an available port.

### Module Not Found Errors
Run `npm install` to ensure all dependencies are installed.

## Security Notes

1. Never commit `.env` file to version control
2. Use strong passwords for database users
3. Enable encryption (`DB_ENCRYPT=true`) in production
4. Implement authentication and authorization for production use
5. Use HTTPS in production environments

## License

ISC