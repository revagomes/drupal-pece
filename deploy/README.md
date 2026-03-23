# PECE Deployment Guide

This directory contains production deployment infrastructure for PECE v2.x. Two deployment targets are supported:

| | Docker Compose + Easypanel | Kubernetes (K3s) |
|---|---|---|
| **Target** | VPS 1 (Ubuntu 22.04, Docker CE 29.3) | VPS 2 (future — needs OS upgrade) |
| **Status** | ✅ Active PoC | 🔜 Future |
| **Reverse proxy** | Easypanel's Traefik (managed) | Ingress controller |
| **Orchestration** | `docker compose` | `kubectl` / K3s |
| **Image registry** | GHCR | GHCR |
| **IaC** | Scripts + Makefile | OpenTofu + Makefile |

---

## Directory Structure

```
deploy/
├── README.md                         # This file
├── Makefile                          # Deployment automation
├── containerfiles/                   # Shared container image definitions
│   ├── Containerfile.php            # PHP-FPM production image
│   ├── Containerfile.nginx          # Nginx production image
│   └── nginx.conf                   # Nginx configuration (baked into image)
├── docker-compose/                   # VPS 1 — Docker Compose + Easypanel
│   ├── docker-compose.yml           # Production stack
│   └── .env.example                 # Environment variable template
├── kubernetes/                       # VPS 2 — Kubernetes (future)
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── pvc.yaml
│   ├── deployment-php.yaml
│   ├── deployment-nginx.yaml
│   ├── statefulset-mariadb.yaml
│   ├── service-{php,nginx,mariadb}.yaml
│   ├── ingress.yaml
│   └── hpa.yaml
├── opentofu/                         # Infrastructure as Code (K8s target)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── modules/kubernetes/
└── scripts/
    ├── build.sh                     # Container image build (both targets)
    ├── deploy-compose.sh            # Deploy via Docker Compose to VPS 1
    ├── rollback-compose.sh          # Rollback Docker Compose deployment
    ├── deploy-k8s.sh                # Deploy to Kubernetes cluster
    └── rollback-k8s.sh              # Rollback Kubernetes deployment
```

---

## Target 1: Docker Compose + Easypanel (VPS 1)

### Architecture

```
Internet → Easypanel Traefik (port 80/443) → localhost:8080 → Nginx → PHP-FPM → MariaDB
```

Nginx binds to host port **8080** only. Easypanel's Traefik handles TLS termination and domain routing — no second reverse proxy is needed or started.

### VPS 1 Prerequisites

1. **Docker CE ≥ 24** and **Docker Compose v2** installed
2. **Easypanel** running (manages Traefik on ports 80/443)
3. Deploy directory created:
   ```bash
   mkdir -p /opt/pece2
   ```
4. **SSH deploy key** added to `~/.ssh/authorized_keys` on the VPS:
   ```bash
   # On your local machine — generate a dedicated key (no passphrase)
   ssh-keygen -t ed25519 -f ~/.ssh/pece_deploy -N ""
   # Add the public key to the VPS
   ssh-copy-id -i ~/.ssh/pece_deploy.pub user@your-vps
   ```
5. **Easypanel custom app** pointing to `localhost:8080` with your domain — this lets Traefik route traffic and issue a TLS certificate automatically.

### GitHub Actions Secrets

Add these secrets in **GitHub → Repository → Settings → Secrets → Actions**:

| Secret | Description | Example |
|--------|-------------|---------|
| `VPS_HOST` | VPS IP or hostname | `1.2.3.4` |
| `VPS_USER` | SSH user | `deploy` |
| `VPS_SSH_KEY` | Private SSH key (ed25519, no passphrase) | Contents of `~/.ssh/pece_deploy` |
| `VPS_DEPLOY_PATH` | Deploy directory on VPS | `/opt/pece2` |
| `DB_PASSWORD` | MariaDB application user password | Generated strong password |
| `DB_ROOT_PASSWORD` | MariaDB root password | Generated strong password |
| `DRUPAL_TRUSTED_HOST` | Drupal trusted host pattern (regex) | `^pece\.example\.com$` |
| `DB_NAME` | Database name (optional, default: `drupal`) | `drupal` |
| `DB_USER` | Database user (optional, default: `drupal`) | `drupal` |

### Automated Deployment (GitHub Actions)

Push to `feature/k8s-do-deployment` to trigger the deploy workflow:

```bash
git push origin feature/k8s-do-deployment
```

The workflow (`.github/workflows/deploy.yml`):
1. Builds PHP and Nginx images from `deploy/containerfiles/`
2. Pushes to GHCR with `latest` and `sha-<short>` tags
3. SSHs into VPS 1, writes `.env`, copies `docker-compose.yml`
4. Runs `docker compose pull && docker compose up -d`

### Manual Deployment

```bash
# Set required environment variables
export VPS_HOST=1.2.3.4
export VPS_USER=deploy
export VPS_SSH_KEY=~/.ssh/pece_deploy
export VPS_DEPLOY_PATH=/opt/pece2
export DB_PASSWORD=your_db_password
export DB_ROOT_PASSWORD=your_root_password
export DRUPAL_TRUSTED_HOST='^pece\.example\.com$'

# Deploy
make compose-deploy

# Or directly via script
cd deploy && ./scripts/deploy-compose.sh
```

### Rollback

```bash
# Rollback to a specific image tag (shown in GitHub Actions run logs)
make compose-rollback TAG=sha-abc1234

# Or via script
cd deploy && ./scripts/rollback-compose.sh --tag sha-abc1234
```

### Makefile Targets (Docker Compose)

| Target | Description |
|--------|-------------|
| `make compose-deploy` | Deploy to VPS 1 |
| `make compose-rollback TAG=sha-<short>` | Rollback to previous image tag |
| `make compose-status VPS_HOST=... VPS_USER=... VPS_SSH_KEY=...` | Show running services |
| `make compose-logs VPS_HOST=... VPS_USER=... VPS_SSH_KEY=...` | Tail service logs |

### First-Time Drupal Install

After a successful deploy, run the Drupal site install from inside the PHP container on the VPS:

```bash
ssh -i ~/.ssh/pece_deploy deploy@your-vps
cd /opt/pece2

# Install Drupal with PECE profile
docker compose exec php vendor/bin/drush si pece \
  --site-name="PECE" \
  -y

# Clear caches
docker compose exec php vendor/bin/drush cr
```

---

## Target 2: Kubernetes (VPS 2 — Future)

VPS 2 requires an OS upgrade from kernel 3.13 to Ubuntu 22.04 before K3s can be installed. The manifests are ready and will remain untouched until then.

### Architecture

```
Internet → Ingress Controller → Nginx Service → PHP-FPM Service → MariaDB StatefulSet
```

### Prerequisites

- K3s or Kubernetes ≥ 1.28 cluster
- `kubectl` configured
- OpenTofu ≥ 1.6

### Quick Start

```bash
# 1. Provision infrastructure with OpenTofu
cd deploy/opentofu
tofu init
tofu plan -var-file=production.tfvars
tofu apply -var-file=production.tfvars

# 2. Configure secrets (never commit real values)
cd deploy/kubernetes
cp secrets.yaml secrets.local.yaml
# Edit secrets.local.yaml with real credentials
kubectl apply -f secrets.local.yaml

# 3. Deploy
make k8s-deploy ENV=production
```

### Makefile Targets (Kubernetes)

| Target | Description |
|--------|-------------|
| `make k8s-build` | Build container images |
| `make k8s-deploy` | Deploy to Kubernetes cluster |
| `make k8s-rollback` | Rollback to previous version |
| `make k8s-status` | Show deployment status |
| `make k8s-logs` | View deployment logs |

---

## Container Images

Both targets use the same images built from `deploy/containerfiles/`.

**PHP-FPM (`pece/php`)**
- Base: `php:8.3-fpm-bookworm` (multi-stage build)
- Includes Composer dependencies, Drupal core, PECE profile
- Runs as `www-data` (non-root)
- PHP-FPM on port 9000

**Nginx (`pece/nginx`)**
- Base: `nginx:1.25-alpine`
- Drupal-optimized FastCGI configuration
- Upstream: `php:9000` (matches service name in both compose and K8s)
- HTTP on port 80 (host-mapped to 8080 in compose)

### Build Images Manually

```bash
# Build all images (uses podman by default, set BUILD_ENGINE=docker to use Docker)
cd deploy
make build BUILD_ENGINE=docker IMAGE_TAG=v1.0.0

# Build and push to GHCR
make push CONTAINER_REGISTRY=ghcr.io/pece-project/drupal-pece IMAGE_TAG=v1.0.0
```

---

## Security Notes

- **Never commit secrets** — use `.env` files (gitignored) or GitHub Actions secrets
- **SSH deploy key** should be a dedicated ed25519 key, no passphrase, restricted to the VPS
- **Rotate credentials** regularly — DB passwords and Drupal hash salt
- **MariaDB** is on the internal Docker network only — not exposed to the host
- **`docker compose down -v` is never called** by deploy/rollback scripts — named volumes are preserved

## Additional Resources

- [PECE Project](https://pece-project.github.io/drupal-pece/)
- [Docker Compose reference](https://docs.docker.com/compose/)
- [Easypanel documentation](https://easypanel.io/docs)
- [Kubernetes documentation](https://kubernetes.io/docs/)
- [OpenTofu documentation](https://opentofu.org/docs/)
