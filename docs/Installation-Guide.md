# Installation Guide

This guide will walk you through installing the Cops & Robbers game mode on your FiveM server.

## Prerequisites

- FiveM Server (latest version)
- MySQL/MariaDB Database
- Basic knowledge of FiveM server administration

## Step 1: Download the Resource

1. Clone or download the repository:
```bash
git clone https://github.com/Indom-hub/Cops-and-Robbers.git
```

2. Place the `cops-and-robbers` folder in your server's `resources` directory.

## Step 2: Database Setup

1. Import the SQL schema:
```sql
mysql -u your_username -p your_database < cops-and-robbers/sql/schema.sql
```

2. Configure your database connection in `server.cfg`:
```cfg
set mysql_connection_string "mysql://user:password@localhost/database?charset=utf8mb4"
```

## Step 3: Server Configuration

Add the following to your `server.cfg`:

```cfg
# Cops & Robbers Configuration
ensure cops-and-robbers

# Optional configurations
setr cops_robbers_max_cops 10
setr cops_robbers_max_robbers 20
setr cops_robbers_economy_multiplier 1.0
```

## Step 4: Dependencies

Ensure you have the following dependencies installed:
- **mysql-async** or **oxmysql**
- **es_extended** (optional, for ESX integration)
- **qb-core** (optional, for QBCore integration)

## Step 5: Start Your Server

1. Start your FiveM server
2. Check the console for any errors
3. Connect to your server and enjoy!

## Troubleshooting

### Common Issues

**Database Connection Failed**
- Verify your MySQL credentials
- Ensure the database exists
- Check firewall settings

**Resource Not Starting**
- Check for missing dependencies
- Review server console for errors
- Verify file permissions

**Performance Issues**
- Adjust max player settings
- Optimize database queries
- Consider server hardware upgrades