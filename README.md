# IT Infrastructure & DevOps Trainee — Practical Assignment

A hardened Ubuntu host running a containerized Nginx → Flask → PostgreSQL
stack, with automated health checks, backups, and basic metrics monitoring.

## 1. Architecture

```
                        Internet
                            |
                            v
                    [ UFW Firewall ]
              allows: 2222/tcp 80/tcp 443/tcp
                            |
                            v
        [ Nginx :80 ]  --proxy_pass-->  [ Flask app :5000 ]  -->  [ PostgreSQL ]
                                                                    (named volume,
                                                                     persists data)

  [ infra_health_check.sh ] --cron every 15min--> /var/log/infra_health.log
  [ db_backup.sh ]          --manual/cron------->  /var/backups/db/*.sql.gz
  [ node-exporter ] --scraped by--> [ prometheus :9090 ]
```

## 2. Repository Structure

```
.
├── README.md                      # this file
├── .env.example                   # copy to .env, fill in DB credentials
├── .gitignore
├── docker-compose.yml              # nginx + app + db
├── docker-compose.monitoring.yml   # prometheus + node-exporter
├── nginx/default.conf              # reverse proxy config
├── app/                             # Flask backend
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
├── monitoring/prometheus.yml
├── scripts/
│   ├── setup_server.sh             # Task 1: user + SSH + UFW hardening
│   ├── infra_health_check.sh       # Task 3: resource/container health check
│   └── db_backup.sh                # Task 4: DB dump + compress + retain
└── cron/infra_health_check.cron    # cron schedule (every 15 min)
```

## 3. Prerequisites

- Ubuntu 22.04/24.04 (VM or cloud instance) with a public/private IP you control
- An SSH key pair generated locally: `ssh-keygen -t ed25519 -C "trainee"`
- Docker Engine + Docker Compose plugin installed on the server:
  ```bash
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER   # log out/in to apply
  ```

## 4. Task 1 — Server Provisioning & Hardening

## Task 1 — Server Provisioning & Hardening

Goal: a proper admin user instead of root, SSH locked to key-only auth on a non-default port, and a firewall that only allows what's needed.

Did this by hand first to actually understand each step, then scripted it in [`scripts/setup_server.sh`](./scripts/setup_server.sh) for repeatability.

**Environment:** Ubuntu Server 24.04 LTS, VMware, CLI-only.

**1. Update the system**
```bash
sudo apt update && sudo apt upgrade -y
```

**2. Create `trainee` and add to sudo**
```bash
sudo adduser trainee
sudo usermod -aG sudo trainee
groups trainee   # confirms 'sudo' group
```

**3. Generate an SSH key pair (local machine)**
```powershell
ssh-keygen -t ed25519 -C "trainee"
Get-Content ~/.ssh/id_ed25519.pub
```

**4. Install the public key on the server**
```bash
sudo mkdir -p /home/trainee/.ssh
sudo nano /home/trainee/.ssh/authorized_keys
sudo chmod 700 /home/trainee/.ssh
sudo chmod 600 /home/trainee/.ssh/authorized_keys
sudo chown -R trainee:trainee /home/trainee/.ssh
```

**5. Harden sshd_config**
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo nano /etc/ssh/sshd_config
```
```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```
```bash
sudo sshd -t                  # validate before reload
sudo systemctl restart ssh    # unit is 'ssh', not 'sshd', on this build
```

**6. Verify before disconnecting**
```powershell
ssh -i ~/.ssh/id_ed25519 -p 2222 trainee@192.168.52.185
```
Logged in with no password prompt — confirms key auth, new port, and `PasswordAuthentication no` all working, before closing the original session.

**7. Configure UFW**
```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH custom port'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw status verbose
```
<img width="1101" height="332" alt="Screenshot 2026-09-10 211225" src="https://github.com/user-attachments/assets/a9d81fdb-0a08-4ffe-855c-ace91c9e5fbf" />


## 5. Task 2 — Docker Compose Stack

1. On the server, clone this repo and configure secrets:
   ```bash
   git clone <your-repo-url>.git
   cd <repo>
   cp .env.example .env && nano .env   
   ```
2. Build and start the stack:
   ```bash
   docker compose up -d --build
   ```
3. Verify all three containers are healthy:
   ```bash
   docker ps
   ```
<img width="1496" height="134" alt="Screenshot 2026-09-11 120444" src="https://github.com/user-attachments/assets/cb6b0b48-9d12-4565-92c9-9bb9de6bf29a" />


4. Verify the reverse proxy routes correctly:
   ```bash
   curl http://localhost/
   curl http://localhost/db-check
   ```
   <img width="1005" height="112" alt="image" src="https://github.com/user-attachments/assets/608ea3b8-b43d-431c-aae8-30e27fe900f9" />


## 6. Task 3 — Health Check Automation

1. Deploy the script:
   ```bash
   sudo mkdir -p /opt/scripts
   sudo cp scripts/infra_health_check.sh /opt/scripts/
   sudo chmod +x /opt/scripts/infra_health_check.sh
   ```
2. Run it manually to confirm it works:
   ```bash
   sudo /opt/scripts/infra_health_check.sh
   cat /var/log/infra_health.log
   ```
   <img width="1243" height="233" alt="Screenshot 2026-09-11 121232" src="https://github.com/user-attachments/assets/f5d3fe48-638e-4ed8-8ad1-2e20d2aaf8a2" />


3. Install the cron schedule (runs every 15 minutes):
   ```bash
   sudo cp cron/infra_health_check.cron /etc/cron.d/infra_health_check
   sudo chmod 644 /etc/cron.d/infra_health_check
   ```
   Confirm it's registered: `sudo cat /etc/cron.d/infra_health_check`

## 7. Task 4 — Backups & Disaster Recovery

1. Deploy and run the backup script:
   ```bash
   sudo cp scripts/db_backup.sh /opt/scripts/
   sudo chmod +x /opt/scripts/db_backup.sh
   sudo /opt/scripts/db_backup.sh
   ls -lh /var/backups/db/
   ```
   Old backups older than 7 days are pruned automatically (retention policy).

2. **Restore procedure** (documented, tested):

Backup produced: `db_backup_20260911.sql.gz` (format: `db_backup_YYYYMMDD.sql.gz`)

```bash
# Decompress and restore into the existing 'db' container
gunzip -k /var/backups/db/db_backup_20260911.sql.gz
docker exec -i db psql -U appuser -d appdb < /var/backups/db/db_backup_20260911.sql
```

To restore into a fresh database instead (e.g. volume was lost):
```bash
docker exec -i db psql -U appuser -d postgres -c "DROP DATABASE IF EXISTS appdb;"
docker exec -i db psql -U appuser -d postgres -c "CREATE DATABASE appdb;"
docker exec -i db psql -U appuser -d appdb < /var/backups/db/db_backup_20260911.sql
```
<img width="1180" height="216" alt="Screenshot 2026-09-11 121607" src="https://github.com/user-attachments/assets/6b07743c-c482-4cd3-96e5-3ea559cd47d2" />


### Basic Metrics/Monitoring

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

Ports 9090/9100 aren't opened on UFW (keeps Task 1's firewall policy intact) — accessed via SSH tunnel instead:
```powershell
ssh -i ~/.ssh/id_ed25519 -p 2222 -L 9090:localhost:9090 trainee@192.168.52.185
```
Then `http://localhost:9090/targets` → confirm `node-exporter` shows `UP`.
  
<img width="1858" height="565" alt="image" src="https://github.com/user-attachments/assets/8300a025-bc41-4b80-88d0-e1a2bf05c910" />

## 8. Task 5 — Git Workflow

This repo was built using feature branches merged into `main`:

```bash
git init
git checkout -b feature/docker-setup
# ... add docker-compose.yml, nginx/, app/ ...
git add . && git commit -m "feat: add nginx, flask app, and postgres docker-compose stack"
git checkout main && git merge feature/docker-setup

git checkout -b feature/scripts
# ... add scripts/, cron/ ...
git add . && git commit -m "feat: add health check and db backup automation scripts"
git checkout main && git merge feature/scripts

git checkout -b docs/readme
git add README.md && git commit -m "docs: add full setup and verification runbook"
git checkout main && git merge docs/readme

git push origin main
```

Commit message convention: `feat:`, `fix:`, `docs:`, `chore:` prefixes
(Conventional Commits) for a clean, readable history.

## 9. Verification Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | Firewall rules | `sudo ufw status verbose` |
| 2 | Containers running | `docker ps` |
| 3 | Reverse proxy routing | `curl http://localhost/` |
| 4 | Health check + log | `sudo /opt/scripts/infra_health_check.sh && cat /var/log/infra_health.log` |
| 5 | Cron registered | `sudo cat /etc/cron.d/infra_health_check` |
| 6 | Backup exists | `ls -lh /var/backups/db/` |
| 7 | Monitoring target up | Prometheus UI → Status → Targets |



