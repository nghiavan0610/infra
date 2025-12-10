# MySQL

Production-ready MySQL 8.0 with monitoring.

## Quick Start

```bash
# Start MySQL
docker compose up -d

# Check status
docker compose ps
docker compose logs -f
```

## Create User & Database

```bash
# Create user with new database
./scripts/create-user.sh myapp_user password123 myapp

# Create user for existing database
./scripts/create-user.sh myapp_user password123
```

## Connect

```bash
# MySQL CLI
docker exec -it mysql mysql -u root -p

# From host
mysql -h localhost -P 3306 -u app -p
```

## Connection Strings

```
# Standard
mysql://user:password@localhost:3306/database

# With charset
mysql://user:password@localhost:3306/database?charset=utf8mb4
```

## Configuration

Edit `.env` for basic settings:
- `MYSQL_ROOT_PASSWORD` - Root password
- `MYSQL_DATABASE` - Default database
- `MYSQL_USER` / `MYSQL_PASSWORD` - Default user
- `MYSQL_BUFFER_POOL_SIZE` - InnoDB buffer pool (default: 256M)
- `MYSQL_MAX_CONNECTIONS` - Max connections (default: 200)

Edit `config/my.cnf` for advanced MySQL settings.

## Monitoring

Metrics exported on port 9104 for Prometheus.

Key metrics:
- `mysql_up` - Server availability
- `mysql_global_status_connections` - Connection count
- `mysql_global_status_queries` - Query count
- `mysql_global_status_slow_queries` - Slow queries

## Backup

```bash
# Dump all databases
docker exec mysql mysqldump -u root -p --all-databases > backup.sql

# Dump specific database
docker exec mysql mysqldump -u root -p myapp > myapp.sql

# Restore
docker exec -i mysql mysql -u root -p < backup.sql
```

## Performance Tuning

For production, adjust in `.env`:
```bash
# 25% of available RAM for buffer pool
MYSQL_BUFFER_POOL_SIZE=1G

# Based on expected concurrent connections
MYSQL_MAX_CONNECTIONS=500
```

## Slow Query Log

Enabled by default. View slow queries:
```bash
docker exec mysql cat /var/lib/mysql/slow.log
```
