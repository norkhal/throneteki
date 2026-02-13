#!/bin/bash
set -euo pipefail

# Throneteki GCP Deployment Initialization Script
# Run once on a fresh clone to set up the deployment at play.dragonstoneforge.com.
#
# Prerequisites:
#   - Docker with compose plugin installed
#   - git and openssl available
#   - DNS for play.dragonstoneforge.com pointing to this server's IP
#   - Ports 80 and 443 open in firewall
#
# Usage:
#   CERTBOT_EMAIL=you@example.com bash deploy/init.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="play.dragonstoneforge.com"
EMAIL="${CERTBOT_EMAIL:-}"

echo "=== Throneteki Deployment Init ==="
echo "Project directory: $PROJECT_DIR"
echo ""

# --- Step 1: Validate prerequisites ---
echo "[1/7] Checking prerequisites..."
for cmd in docker git openssl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd is not installed."
        exit 1
    fi
done

if docker compose version &> /dev/null; then
    COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE="docker-compose"
else
    echo "ERROR: docker compose is not available."
    exit 1
fi
echo "Using: $COMPOSE"

# --- Step 2: Initialize git submodules ---
echo ""
echo "[2/7] Initializing git submodules (card data)..."
cd "$PROJECT_DIR"
git submodule update --init --recursive

# --- Step 3: Generate secrets if local.json5 doesn't exist ---
echo ""
echo "[3/7] Checking secrets configuration..."
if [ ! -f "$PROJECT_DIR/config/local.json5" ]; then
    echo "Creating config/local.json5 with random secrets..."
    JWT_SECRET=$(openssl rand -hex 32)
    HMAC_SECRET=$(openssl rand -hex 32)
    cat > "$PROJECT_DIR/config/local.json5" << EOF
{
    secret: '${JWT_SECRET}',
    hmacSecret: '${HMAC_SECRET}',
}
EOF
    echo "Secrets generated and written to config/local.json5"
    echo "IMPORTANT: Back up this file. It is excluded from git."
else
    echo "config/local.json5 already exists, skipping secret generation."
fi

# --- Step 4: Build Docker images ---
echo ""
echo "[4/7] Building Docker images..."
cd "$PROJECT_DIR"
$COMPOSE -f docker-compose.gcp.yml build lobby node

# --- Step 5: Obtain SSL certificate ---
echo ""
echo "[5/7] Obtaining SSL certificate..."

# Check if cert already exists
if docker volume inspect throneteki_certbot_etc &> /dev/null; then
    CERT_EXISTS=$(docker run --rm -v throneteki_certbot_etc:/etc/letsencrypt alpine \
        sh -c "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem && echo yes || echo no")
else
    CERT_EXISTS="no"
fi

if [ "$CERT_EXISTS" = "yes" ]; then
    echo "SSL certificate already exists, skipping."
else
    if [ -z "$EMAIL" ]; then
        read -p "Enter email for Let's Encrypt notifications: " EMAIL
    fi

    if [ -z "$EMAIL" ]; then
        echo "ERROR: Email is required for Let's Encrypt. Set CERTBOT_EMAIL or provide when prompted."
        exit 1
    fi

    # Create certbot volumes if they don't exist
    docker volume create throneteki_certbot_etc &> /dev/null || true
    docker volume create throneteki_certbot_var &> /dev/null || true
    docker volume create throneteki_certbot_webroot &> /dev/null || true

    # Create a temporary nginx config for ACME challenge
    TEMP_NGINX_CONF=$(mktemp)
    cat > "$TEMP_NGINX_CONF" << 'NGINX_EOF'
worker_processes 1;
events { worker_connections 128; }
http {
    server {
        listen 80;
        server_name play.dragonstoneforge.com;
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        location / {
            return 200 'Waiting for SSL setup...';
            add_header Content-Type text/plain;
        }
    }
}
NGINX_EOF

    echo "Starting temporary nginx for ACME challenge..."
    docker run -d --name throneteki-temp-nginx \
        -p 80:80 \
        -v "$TEMP_NGINX_CONF:/etc/nginx/nginx.conf:ro" \
        -v throneteki_certbot_webroot:/var/www/certbot \
        nginx:alpine

    echo "Requesting certificate from Let's Encrypt..."
    docker run --rm \
        -v throneteki_certbot_etc:/etc/letsencrypt \
        -v throneteki_certbot_var:/var/lib/letsencrypt \
        -v throneteki_certbot_webroot:/var/www/certbot \
        certbot/certbot certonly \
        --webroot -w /var/www/certbot \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive

    echo "Stopping temporary nginx..."
    docker stop throneteki-temp-nginx && docker rm throneteki-temp-nginx
    rm -f "$TEMP_NGINX_CONF"

    echo "SSL certificate obtained successfully."
fi

# --- Step 6: Import card data ---
echo ""
echo "[6/7] Importing card data..."
cd "$PROJECT_DIR"

# Start mongo first, wait for it
$COMPOSE -f docker-compose.gcp.yml up -d mongo
echo "Waiting for MongoDB to start..."
sleep 10

echo "Running fetchdata.js..."
$COMPOSE -f docker-compose.gcp.yml run --rm lobby node server/scripts/fetchdata.js --no-images

echo "Running importstandalonedecks.js..."
$COMPOSE -f docker-compose.gcp.yml run --rm lobby node server/scripts/importstandalonedecks.js

# --- Step 7: Start all services ---
echo ""
echo "[7/7] Starting all services..."
cd "$PROJECT_DIR"
$COMPOSE -f docker-compose.gcp.yml up -d

echo ""
echo "=== Deployment Complete ==="
echo "Site: https://$DOMAIN"
echo ""
echo "Useful commands:"
echo "  View logs:        $COMPOSE -f docker-compose.gcp.yml logs -f"
echo "  Restart:          $COMPOSE -f docker-compose.gcp.yml restart"
echo "  Stop:             $COMPOSE -f docker-compose.gcp.yml down"
echo "  Update card data: $COMPOSE -f docker-compose.gcp.yml run --rm lobby node server/scripts/fetchdata.js --no-images"
echo ""
echo "Set up a cron job to reload nginx after cert renewal:"
echo '  0 0 1,15 * * docker exec throneteki-nginx-1 nginx -s reload 2>/dev/null'
