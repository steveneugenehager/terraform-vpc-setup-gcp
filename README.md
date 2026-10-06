# Network stage: per-environment Shared VPCs

This stage creates one custom-mode VPC in each environment's net-host project.
Each host project was created by the **projects stage**, one per environment
folder. The VPC configuration lives in a shared module; each environment has
its own small root configuration, its own variables, and its own state file.

All Terraform operations run as a dedicated **Terraform service account**,
which you impersonate with your own Google credentials. No service account
keys are created or stored.

## Layout

```
terraform-vpc-setup-gcp/
├── .gitignore
├── .tflint.hcl               # TFLint config (Google ruleset)
├── README.md
├── modules/
│   └── vpc/                  # common config, used by every environment
│       ├── main.tf           # VPC, subnets, firewall, Cloud Router/NAT, Shared VPC host
│       ├── variables.tf      # inputs, with validation rules
│       ├── outputs.tf
│       └── versions.tf
└── envs/
    └── <env>/                # one root config per environment (lab, dev, prod, ...)
        ├── backend.tf        # GCS backend (prefix network/<env>) + provider, both impersonating the SA
        ├── main.tf           # reads host project ID from remote state, calls modules/vpc
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars  # this environment's values
```

Terraform is **only run from an `envs/<env>` folder**. `modules/vpc` is never
run directly; it has no backend, provider, or tfvars and is loaded through the
`module "vpc"` block in each environment's `main.tf`.

## What each environment gets

| Resource | Name | Notes |
|---|---|---|
| Compute API | – | Enabled on the host project (not disabled on destroy) |
| VPC | `vpc-<env>-shared` | Custom mode, `GLOBAL` routing by default |
| Subnets | `sn-<env>-<key>` | Private Google Access on; optional flow logs and secondary ranges |
| Firewall | `vpc-<env>-shared-allow-internal` | TCP/UDP/ICMP from the VPC's own primary and secondary ranges |
| Firewall | `vpc-<env>-shared-allow-iap-ssh` | TCP 22 from `35.235.240.0/20` (IAP); toggle with `iap_ssh_enabled` |
| Cloud Router + NAT | `cr-` / `nat-vpc-<env>-shared-<region>` | One per region that has a subnet; toggle with `enable_nat` |
| Shared VPC host | – | Registers the project as a host; toggle with `enable_shared_vpc` |

## Authentication: Terraform service account

Terraform authenticates as you (Application Default Credentials) and then
impersonates the Terraform service account in the seed project. Every API
call, including state reads and writes, is made as that service account.

```
you (ADC)  ──serviceAccountTokenCreator──▶  sa-terraform@<seed-project>  ──roles──▶  GCP resources + state bucket
```

### One-time setup

```bash
SEED=<seed-project-id>                        # e.g. shv-cld-admn-btstrp-4329
SA=sa-terraform@${SEED}.iam.gserviceaccount.com
ME=user:<your-email>
ORG=<org-id>
FOLDER=<folder containing the environment folders>
BUCKET=<state-bucket>

# 1. Create the SA and enable the API used for impersonation
gcloud iam service-accounts create sa-terraform --project="$SEED" --display-name="Terraform"
gcloud services enable iamcredentials.googleapis.com --project="$SEED"

# 2. Allow yourself to impersonate it
gcloud iam service-accounts add-iam-policy-binding "$SA" --project="$SEED" \
  --member="$ME" --role="roles/iam.serviceAccountTokenCreator"

# 3. Grant the SA what the network stage needs
for ROLE in roles/serviceusage.serviceUsageAdmin roles/compute.networkAdmin; do
  gcloud resource-manager folders add-iam-policy-binding "$FOLDER" \
    --member="serviceAccount:$SA" --role="$ROLE"
done
gcloud organizations add-iam-policy-binding "$ORG" \
  --member="serviceAccount:$SA" --role="roles/compute.xpnAdmin"
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$SA" --role="roles/storage.objectAdmin"
```

| Principal | Role | Scope | Why |
|---|---|---|---|
| You | `roles/iam.serviceAccountTokenCreator` | Terraform SA | Impersonate the SA |
| Terraform SA | `roles/compute.networkAdmin` | Environment folder(s) | VPCs, subnets, firewall, routers, NAT |
| Terraform SA | `roles/serviceusage.serviceUsageAdmin` | Environment folder(s) | Enable the Compute API |
| Terraform SA | `roles/compute.xpnAdmin` | Organization (or folder) | Shared VPC host enablement |
| Terraform SA | `roles/storage.objectAdmin` | State bucket | Read projects-stage state; read/write network state |

Your personal account needs no other roles for this stage. Remove any you
granted yourself while testing.

If the projects stage already enables `compute.googleapis.com`, you can delete
`google_project_service.compute` from the module and drop the
`serviceUsageAdmin` grant.

### Where impersonation is configured

The SA is set in three places in each environment, because each one makes its
own connection to GCP:

```hcl
# backend.tf: state reads/writes
backend "gcs" {
  bucket                      = "<state-bucket>"
  prefix                      = "network/<env>"
  impersonate_service_account = "sa-terraform@<seed-project>.iam.gserviceaccount.com"
}

# backend.tf: resource creation
provider "google" {
  impersonate_service_account = "sa-terraform@<seed-project>.iam.gserviceaccount.com"
}

# main.tf: reading the projects stage's state
data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket                      = var.state_bucket
    prefix                      = var.projects_state_prefix
    impersonate_service_account = "sa-terraform@<seed-project>.iam.gserviceaccount.com"
  }
}
```

Backend blocks can't use variables, so the email is written out literally.
Changing backend settings after an `init` requires `terraform init -reconfigure`
(the state stays where it is; don't use `-migrate-state`).

### Signing in

```bash
gcloud auth application-default login     # plain user login; no --impersonate flag
```

Your org's session-control policy may force periodic reauthentication. If
Terraform fails with `invalid_grant` / `invalid_rapt`, run the command again.

## How it finds the host projects

Host project IDs include a random suffix, so they are not typed by hand. Each
environment reads them from the projects stage's existing output:

```hcl
output "host_project_ids" {
  value = { for env, p in google_project.host : env => p.project_id }
}
```

and passes `host_project_ids[var.env]` to the module. `var.env` must be one of
that output's keys (the environment folder names).

## State layout

All state lives in the GCS bucket created by the bootstrap (seed) project:

```
gs://<state-bucket>/
├── <projects-stage-prefix>/default.tfstate   # read by every env (remote state)
└── network/
    └── <env>/default.tfstate                 # one per environment
```

## Prerequisites

- Terraform >= 1.5 and the `hashicorp/google` provider (>= 6.0, < 8.0)
- `gcloud` CLI, signed in with ADC
- The projects stage applied, with `host_project_ids` in its state
- The Terraform SA set up as described above
- Validation tools (optional but recommended): [TFLint](https://github.com/terraform-linters/tflint),
  [Trivy](https://trivy.dev) or [Checkov](https://www.checkov.io), `jq`

## First-time setup for an environment

1. **`backend.tf`**: set `bucket`, keep `prefix = "network/<env>"`, and set
   `impersonate_service_account` in both the backend and provider blocks.
2. **`main.tf`**: set `impersonate_service_account` in the
   `terraform_remote_state` config.
3. **`terraform.tfvars`**:
   - `env`: the environment folder name, exactly as it appears as a key in `host_project_ids`
   - `state_bucket`: the state bucket
   - `projects_state_prefix`: the `prefix` from the projects stage's `backend "gcs"` block
   - `subnets`: this environment's subnets and CIDRs

## Validation

Run these in order. Steps 1 to 3 need no GCP access and are cheap enough to
run on every change.

### 1. Formatting and syntax

```bash
terraform fmt -check -recursive    # from the repo root; use without -check to fix
cd envs/<env>
terraform init
terraform validate                 # syntax, types, references
```

### 2. Lint

`validate` only checks that the config is well formed. TFLint with the Google
ruleset also catches provider-level mistakes such as invalid regions or
attribute values, plus unused declarations.

```bash
tflint --init                      # once, downloads the Google ruleset from .tflint.hcl
tflint --recursive                 # from the repo root
```

### 3. Security and policy scan

Run once per environment, from the repo root, so the scanner sees that
environment's variable values (Trivy does not load `terraform.tfvars` on its own):

```bash
trivy config --tf-vars envs/<env>/terraform.tfvars envs/<env>
# or: checkov -d envs/<env> --var-file envs/<env>/terraform.tfvars
```

Without `--tf-vars`, Trivy warns that variable values were not found and
can't evaluate settings driven by tfvars, such as flow logs.

Expect some findings you accept on purpose (for example, flow logs off in
non-prod). Suppress them inline with a comment explaining why, rather than
ignoring the tool.

### 4. Input validation (built in)

The module rejects bad input at `plan` time:

- every subnet `ip_cidr_range` and secondary range must be a valid CIDR
- `routing_mode` must be `GLOBAL` or `REGIONAL`

### 5. Plan review

```bash
terraform plan -out=tfplan
terraform show tfplan              # review before applying
terraform apply tfplan             # applies exactly what was reviewed
```

Look closely for `destroy` or `-/+` (replace) on networks or subnets.
Replacing a subnet that has workloads attached will fail or cause an outage.
`*.tfplan` files are git-ignored.

### 6. Post-apply verification with gcloud

These checks ask GCP directly what exists, independent of Terraform's state,
and compare it with what the environment's `terraform.tfvars` asked for.
Run them from the environment folder after `apply`.

Set up variables once:

```bash
cd envs/<env>
ENV=<env>                                                  # e.g. lab
P=$(terraform output -json network | jq -r .project_id)    # host project
VPC=vpc-${ENV}-shared
SA=sa-terraform@<seed-project>.iam.gserviceaccount.com     # optional, see note below
```

#### VPC

```bash
gcloud compute networks describe "$VPC" --project="$P" \
  --format="table(name, routingConfig.routingMode, autoCreateSubnetworks)"
```

Expect: one VPC named `vpc-<env>-shared`, routing mode `GLOBAL` (or what you
set), and `autoCreateSubnetworks` = `False` (custom mode). Also confirm there is
no leftover `default` network:

```bash
gcloud compute networks list --project="$P"     # SUBNET_MODE should be CUSTOM
```

#### Subnets

```bash
gcloud compute networks subnets list --project="$P" --network="$VPC" \
  --format="table(name, region.basename(), ipCidrRange, privateIpGoogleAccess, logConfig.enable:label=FLOW_LOGS, secondaryIpRanges[].rangeName.list():label=SECONDARY)"
```

Check each row against `subnets` in `terraform.tfvars`:

| Column | Should match |
|---|---|
| `NAME` | `sn-<env>-<key>` for every key in `subnets`, and nothing extra |
| `REGION` | that subnet's `region` |
| `RANGE` | that subnet's `ip_cidr_range` |
| `PRIVATE_IP_GOOGLE_ACCESS` | `True` unless you set `private_google_access = false` |
| `FLOW_LOGS` | `True` where `flow_logs = true`, empty otherwise |
| `SECONDARY` | the keys of `secondary_ranges`, if any |

Inspect one subnet in full, including secondary CIDRs and flow-log settings:

```bash
gcloud compute networks subnets describe sn-${ENV}-use1 --region=us-east1 --project="$P" \
  --format="yaml(name, ipCidrRange, gatewayAddress, privateIpGoogleAccess, secondaryIpRanges, logConfig)"
```

Compare the subnets with what Terraform says it manages:

```bash
terraform output -json subnets | jq -r 'to_entries[] | "\(.key)\t\(.value.region)\t\(.value.cidr)"'
```

#### Firewall rules

```bash
gcloud compute firewall-rules list --project="$P" --filter="network~/${VPC}$" \
  --format="table(name, direction, priority, sourceRanges.list(), allowed[].map().firewall_rule().list())"
```

Expect exactly two rules: `vpc-<env>-shared-allow-internal`, whose source
ranges are your subnets' primary and secondary CIDRs, and
`vpc-<env>-shared-allow-iap-ssh`, from `35.235.240.0/20` on `tcp:22`
(unless `iap_ssh_enabled = false`).

#### Cloud Router and NAT

```bash
gcloud compute routers list --project="$P" --filter="network~/${VPC}$" \
  --format="table(name, region.basename(), network.basename())"

for R in $(gcloud compute routers list --project="$P" --filter="network~/${VPC}$" --format="value(name,region.basename())" | tr '\t' ','); do
  NAME=${R%,*}; REGION=${R#*,}
  gcloud compute routers nats list --router="$NAME" --region="$REGION" --project="$P" \
    --format="table(name, natIpAllocateOption, sourceSubnetworkIpRangesToNat, logConfig.filter)"
done
```

Expect one router (`cr-vpc-<env>-shared-<region>`) and one NAT for every region
that has a subnet, unless `enable_nat = false`.

#### Shared VPC host

```bash
gcloud compute projects describe "$P" --format="value(xpnProjectStatus)"
```

Expect `HOST`. To list every host project in the org:

```bash
gcloud compute shared-vpc organizations list-host-projects <org-id>
```

#### Running as the Terraform service account

The commands above run as your own `gcloud` login. Your personal account may
not have read access to the host projects once those roles have been removed.
In that case, run them as the SA by adding a flag:

```bash
gcloud compute networks subnets list --project="$P" --network="$VPC" \
  --impersonate-service-account="$SA"
```

Or set it once for the shell session:

```bash
gcloud config set auth/impersonate_service_account "$SA"
# ... run checks ...
gcloud config unset auth/impersonate_service_account
```

#### Drift check

Then confirm Terraform and GCP agree:

```bash
terraform plan                     # should report: No changes.
```

### Optional: pre-commit

[pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform)
can run `terraform fmt`, `terraform validate`, `tflint`, and `trivy`
automatically on every commit.

## Usage

```bash
cd envs/<env>
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Re-run `terraform init` only after changing the backend or a module `source`
path (`-reconfigure` if the backend settings changed). Edits inside
`modules/vpc` are picked up by `plan` directly.

## Making changes

- **One environment only** (CIDRs, flow logs, NAT): edit that environment's
  `terraform.tfvars` and plan/apply in its folder.
- **All environments** (new firewall rule, naming, defaults): edit
  `modules/vpc`, then plan in each environment, lowest first and prod last.
- **New environment**: copy an existing `envs/<env>` folder, change the backend
  prefix and `terraform.tfvars`, and make sure the projects stage has a host
  project for it and the SA's folder-level roles cover it.

## CIDR plan

Ranges must not overlap across environments, so the VPCs can later be peered
or connected through a hub without renumbering. Use one /16 per environment,
split into /20 subnets per region, for example:

| Environment | Range | us-east1 | us-central1 | GKE secondary |
|---|---|---|---|---|
| env 1 | 10.10.0.0/16 | 10.10.0.0/20 | 10.10.16.0/20 | – |
| env 2 | 10.20.0.0/16 | 10.20.0.0/20 | 10.20.16.0/20 | – |
| env 3 | 10.30.0.0/16 | 10.30.0.0/20 | 10.30.16.0/20 | – |
| prod | 10.40.0.0/16 | 10.40.0.0/20 | 10.40.16.0/20 | pods 10.140.0.0/16, services 10.141.0.0/20 |

## Outputs

Each environment exposes:

- `network`: VPC `project_id`, `id`, `name`, and `self_link`
- `subnets`: map of subnet key to `self_link`, `region`, and `cidr`

Later stages (service projects, GKE, and so on) can read these through
`terraform_remote_state` with prefix `network/<env>`, using the same SA.

## Version control

- Commit `.terraform.lock.hcl` in each env folder after the first `init`.
- `terraform.tfvars` files are committed; they hold configuration, not secrets.
  Put anything sensitive in an ignored `*.local.tfvars` or `*.secret.tfvars`.
- State, plan files, `.terraform/`, and `*.json` (to catch stray keys) are ignored.
