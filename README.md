# DevOps & CI/CD Proof of Concept – Flask on AWS ECS

A DevOps proof of concept: a GitHub Actions pipeline that tests, containerizes and deploys a Python/Flask app to AWS ECS Fargate (staging and production), with the infrastructure defined in Terraform (Infrastructure-as-Code) and keyless AWS authentication via OIDC.

The deployed app is a study dashboard from a separate course project on object-oriented programming; here it serves as the workload.

## Architecture

```
GitHub (push to main)
   │
   ▼
GitHub Actions ── lint + tests ──► build Docker image ──► push to Amazon ECR
   │                                                        │
   │  (OIDC, no static AWS keys)                            ▼
   └──────────────────────────────► ECS Fargate: staging service (auto deploy)
                                     ECS Fargate: prod service    (manual promote)
```

| Folder / file | Purpose |
|---|---|
| `app/` | Flask app (routes, services/domain classes, templates, static assets) |
| `.data/` | Local JSON storage (created on first run, not versioned), mounted as a volume in Docker Compose |
| `tests/` | pytest smoke test (Flask test client) |
| `Dockerfile`, `docker-compose.yml` | Container image (gunicorn, non-root user) and local setup |
| `.github/workflows/` | CI/CD pipelines |
| `terraform/` | AWS infrastructure (ECR, ECS, IAM, OIDC, logging) |

## CI/CD pipeline

**`ci-staging.yml`** runs on every push to `main` and on pull requests:

1. **build-and-test** (also on pull requests): installs dependencies, runs flake8 and pytest.
2. **docker-build-and-push** (only on push to `main` with `DEPLOY_ENABLED`): authenticates to AWS via OIDC, builds the image and pushes it to ECR tagged with the commit SHA and `latest`.
3. **deploy-staging** (only on push to `main` with `DEPLOY_ENABLED`): forces a new deployment of the ECS staging service, which pulls `:latest`.

**`deploy-prod.yml`** is started manually (`workflow_dispatch`) and promotes the current image to the production ECS service.

The AWS jobs need the following repository settings (Settings → Secrets and variables → Actions):

| Name | Kind | Value |
|---|---|---|
| `AWS_ROLE` | Secret | ARN of the IAM role for GitHub Actions (Terraform output `aws_role_arn_for_github`) |
| `DEPLOY_ENABLED` | Variable | `true` while the AWS stack exists; without it, only lint and tests run |

## Infrastructure (Terraform)

`terraform/main.tf` provisions in `eu-central-1`:

- ECR repository for the app image
- ECS cluster with two Fargate services (staging, prod), public IP, port 8000, no load balancer
- Task definition with CloudWatch log group (7 days retention)
- Security group allowing inbound TCP 8000
- IAM roles for task execution and the app task
- GitHub OIDC identity provider and an IAM role that only this repository can assume

Setup:

```bash
cd terraform
terraform init
terraform apply \
  -var="aws_profile=<your-aws-cli-profile>" \
  -var="github_owner=<your-github-user>" \
  -var="github_repo=<your-repo-name>"
```

Then store the output `aws_role_arn_for_github` as the `AWS_ROLE` secret and set the variable `DEPLOY_ENABLED=true` in the GitHub repository. Because the ECS services start before an image exists, run the staging pipeline once after `apply`.

The Terraform state is kept locally and is not part of this repository. To tear everything down: `terraform destroy`.

### PoC limitations

This is a learning project, not a production setup:

- The GitHub Actions role uses broad managed policies (`AmazonEC2ContainerRegistryPowerUser`, `AmazonECS_FullAccess`).
- No load balancer, HTTPS or custom domain; services are reached by their public task IP.
- Deployments use the mutable `:latest` tag.
- Local Terraform state instead of a remote backend (S3 + locking).
- The Flask `SECRET_KEY` is a fixed development value.
- No authentication: anyone who can reach the app can change its data.

The AWS resources were torn down after the project; the code is kept as a reference.

## Run locally

Requirements: Docker.

```bash
git clone https://github.com/tommorgenstern/python-oop-study-dashboard-devops-cicd
cd python-oop-study-dashboard-devops-cicd
docker compose build --no-cache
docker compose up
```

Then open http://localhost:8000. To load fictional demo data, open http://localhost:8000/seed (this overwrites existing data).

Without Docker:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
flask --app wsgi run --port 8000
```

## License

[MIT](LICENSE)
