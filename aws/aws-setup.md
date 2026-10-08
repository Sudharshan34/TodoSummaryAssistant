# AWS Setup

Region: `ap-southeast-2` (Sydney). All resources are in the default VPC (`vpc-03ea6123c6519dab9`). Architecture diagram: `architecture-diagram.png`.

## Components

| Component | Name | Purpose |
|---|---|---|
| EC2 instance | `todo-server` | Runs Docker Compose: frontend, backend, Prometheus, Grafana, node-exporter, cAdvisor |
| RDS MySQL | `database-1` | Application database, not publicly accessible |
| Security group | `todo-ec2-sg` | Firewall for the EC2 instance |
| Security group | `todo-rds-sg` | Firewall for the database |
| IAM role | `todo-ec2-role` | Gives the EC2 instance AWS permissions without access keys |

## Networking
- **VPC:** the default VPC, with the default subnet group across three subnets.
- **EC2:** placed in a public subnet with a public IPv4 address (Elastic IP) so the app can be opened in a browser.
- **RDS:** placed in the same VPC with **Public access = No**. It has no public IP and can only be reached from inside the VPC. In the default VPC, "private" is achieved with Public access = No plus a locked-down security group, so a separate private subnet was not created (see assumptions).

## Security groups

**`todo-ec2-sg` (inbound)**

| Port | Source | Purpose |
|---|---|---|
| 80 | Anywhere (0.0.0.0/0) | Web application |
| 3001 | <<My IP or Anywhere>> | Grafana |
| 9090 | <<My IP or Anywhere>> | Prometheus |

SSH (port 22) is not open. Server access uses SSM Session Manager, so no inbound admin port and no SSH keys are needed. The backend port 8080 is not exposed to the internet; it is only reachable inside the Docker network.

**`todo-rds-sg` (inbound)**

| Port | Source | Purpose |
|---|---|---|
| 3306 (MySQL/Aurora) | `todo-ec2-sg` | Only the application server can connect |

The source is the EC2 security group, not an IP address, so access follows the server even if its IP changes.

## IAM
- The EC2 instance uses the role `todo-ec2-role`, so no AWS access keys exist on the server or in the repository.
- The role has `AmazonSSMManagedInstanceCore`, which allows Session Manager access and nothing else. It follows least privilege: no S3, RDS or admin permissions.
- GitHub Actions deploys using its repository secrets (see README), not AWS keys stored in code.

## Secrets and configuration
- DB URL, user, password, Cohere key and Slack webhook are stored in `/opt/todo/.env` on the server and in GitHub Actions secrets.
- The `.env` file is excluded by `.gitignore`. Only `.env.example` (with no real values) is committed.
- For stronger protection, move them to SSM Parameter Store or Secrets Manager (not done here, to keep the footprint small).

## Setup steps (reproducible)
1. Create the security groups `todo-ec2-sg` and `todo-rds-sg` with the rules above.
2. Create the IAM role `todo-ec2-role` (EC2 trusted entity) with `AmazonSSMManagedInstanceCore`.
3. Launch a free-tier EC2 instance (Amazon Linux) with the role, `todo-ec2-sg` and auto-assigned public IP, then associate an Elastic IP.
4. Create RDS MySQL (free tier) in the default VPC with Public access = No and security group `todo-rds-sg`.
5. Connect to EC2 with Session Manager and install Docker and Git: `dnf install -y docker git`, then `systemctl enable --now docker`.
6. Install the Docker Compose plugin, clone the repository to `/opt/todo` and create `/opt/todo/.env` from `.env.example`, with `DB_URL` pointing to the RDS endpoint.
7. Run `bash scripts/deploy.sh`. After this, GitHub Actions deploys every push to main automatically.

## Assumptions and limits
- A single instance and a single-AZ database are used to stay within the free tier. Production would use Multi-AZ RDS and an Auto Scaling group behind a load balancer.
- No separate private subnet was built; the default VPC is used.
- No Infrastructure as Code is included. The steps above recreate the setup.
- Stop or delete the EC2 instance, RDS instance and Elastic IP after the review to avoid charges.
