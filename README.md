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
├── docker-compose.monitoring.yml   # optional: prometheus + node-exporter
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

1. Copy `scripts/setup_server.sh` to the server and run it as root:
   ```bash
   sudo ./setup_server.sh
   ```
   It will: update packages, create the `trainee` user, install your SSH
   public key, set `Port 2222`, `PermitRootLogin no`,
   `PasswordAuthentication no`, and configure UFW to allow only
   `2222/tcp`, `80/tcp`, `443/tcp`.

2. **Before closing your current session**, open a new terminal and confirm:
   ```bash
   ssh -p 2222 trainee@<server-ip>
   ```
3. Verify the firewall:
   ```bash
   sudo ufw status verbose
   ```
   📸 *Screenshot 1: output of this command.*

## 5. Task 2 — Docker Compose Stack

1. On the server, clone this repo and configure secrets:
   ```bash
   git clone <your-repo-url>.git
   cd <repo>
   cp .env.example .env && nano .env   # set a real POSTGRES_PASSWORD
   ```
2. Build and start the stack:
   ```bash
   docker compose up -d --build
   ```
3. Verify all three containers are healthy:
   ```bash
   docker ps
   ```
   📸 *Screenshot 2: output of `docker ps` showing nginx, app, db all `Up`.*

4. Verify the reverse proxy routes correctly:
   ```bash
   curl http://localhost/
   curl http://localhost/db-check
   ```
   Or open `http://<server-ip>/` in a browser.
   📸 *Screenshot 3: browser output of the app response.*

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
   📸 *Screenshot 4: terminal output of the script run + log contents.*

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
   Produces: `/var/backups/db/db_backup_YYYYMMDD.sql.gz`
   Old backups older than 7 days are pruned automatically (retention policy).

2. **Restore procedure** (documented, tested):
   ```bash
   # 1. Decompress
   gunzip -k /var/backups/db/db_backup_YYYYMMDD.sql.gz

   # 2. Restore into the running db container
   docker exec -i db psql -U appuser -d appdb < /var/backups/db/db_backup_YYYYMMDD.sql
   ```
   To restore into a *fresh* database instead:
   ```bash
   docker exec -i db psql -U appuser -d postgres -c "DROP DATABASE IF EXISTS appdb;"
   docker exec -i db psql -U appuser -d postgres -c "CREATE DATABASE appdb;"
   docker exec -i db psql -U appuser -d appdb < db_backup_YYYYMMDD.sql
   ```

3. (Optional) Schedule daily backups via cron:
   ```bash
   echo "0 2 * * * root /opt/scripts/db_backup.sh >> /var/log/db_backup.log 2>&1" | sudo tee /etc/cron.d/db_backup
   ```

### Basic Metrics/Monitoring

```bash
docker compose -f docker-compose.monitoring.yml up -d
```
- Node Exporter metrics: `http://<server-ip>:9100/metrics`
- Prometheus UI: `http://<server-ip>:9090` (check **Status → Targets** to
  confirm `node-exporter` is `UP`)

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

### Screenshots (attach in this section before submitting)

- [ ] `sudo ufw status verbose`
- [ ] `docker ps`
- [ ] Browser hitting `http://<server-ip>/`
- [ ] `infra_health_check.sh` run + `/var/log/infra_health.log` contents

## 10. Teardown

```bash
docker compose down -v          # stops containers, removes volumes
docker compose -f docker-compose.monitoring.yml down
sudo rm -rf /opt/scripts
sudo rm -f /etc/cron.d/infra_health_check /etc/cron.d/db_backup
```

## 11. Evaluation Criteria Mapping

| Component | Weight | Where it's addressed |
|---|---|---|
| System Security & Linux | 20% | `scripts/setup_server.sh` — sudo user, SSH key-only auth on port 2222, root login disabled, UFW default-deny with explicit allow rules |
| Docker & Networking | 30% | `docker-compose.yml`, `nginx/default.conf` — 3-service stack, internal network, Nginx reverse proxy to Flask on :5000, Postgres on named volume |
| Bash Automation & Cron | 20% | `scripts/infra_health_check.sh`, `cron/infra_health_check.cron` — CPU/RAM/disk checks, container status check, threshold-based `[WARNING]` logging, 15-min cron |
| Backups & Recovery | 15% | `scripts/db_backup.sh` — timestamped, compressed dump, 7-day retention; restore steps documented above |
| Documentation & Git | 15% | This README (runbook) + feature-branch workflow described in Section 8 |
