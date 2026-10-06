# Network stage: per-environment Shared VPCs

This stage creates one custom-mode VPC in each environment's net-host project.
Each project was created by the **projects stage**, one host project per
environment folder. The VPC configuration lives in a shared module; each
environment has its own small root configuration, its own variables, and its
own state file.

## Layout

```
net-vpcs/
├── .gitignore
├── README.md
├── modules/
│   └── vpc/                  # common config, used by every environment
│       ├── main.tf           # VPC, subnets, firewall, Cloud Router/NAT, Shared VPC host
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
└── envs/
    ├── dev/                  # one root config per environment
    │   ├── backend.tf        # GCS backend, prefix network/dev
    │   ├── main.tf           # reads host project ID, calls modules/vpc
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars  # this environment's values
    ├── test/
    ├── stage/
    └── prod/
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

## How it finds the host projects

Host project IDs include a random suffix, so they are not typed by hand. Each
environment reads them from the projects stage's state:

```hcl
data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = var.projects_state_prefix
  }
}

# project_id = data.terraform_remote_state.projects.outputs.host_project_ids[var.env]
```

This relies on the projects stage's existing output:

```hcl
output "host_project_ids" {
  value = { for env, p in google_project.host : env => p.project_id }
}
```

`var.env` must be one of that output's keys (the environment folder names).

## State layout

All state lives in the GCS bucket created by the bootstrap (seed) project:

```
gs://<state-bucket>/
├── <projects-stage-prefix>/default.tfstate   # read by every env (remote state)
└── network/
    ├── dev/default.tfstate
    ├── test/default.tfstate
    ├── stage/default.tfstate
    └── prod/default.tfstate
```

## Prerequisites

- Terraform >= 1.5 and the `hashicorp/google` provider (>= 6.0, < 8.0).
- The projects stage applied, with `host_project_ids` in its state.
- The identity running Terraform needs:
  - `roles/compute.networkAdmin` on each host project
  - `roles/compute.xpnAdmin` at the org or folder level (for Shared VPC host enablement)
  - `roles/serviceusage.serviceUsageAdmin` on each host project (to enable the Compute API)
  - read access to the projects stage's state object, and read/write on `network/<env>/`

## First-time setup

For each environment folder:

1. **`backend.tf`**: set `bucket` to your state bucket. The `prefix`
   (`network/<env>`) is already set; backend blocks can't use variables.
2. **`terraform.tfvars`**:
   - `env`: the environment folder name, exactly as it appears as a key in `host_project_ids`
   - `state_bucket`: same bucket as above
   - `projects_state_prefix`: the `prefix` from the projects stage's `backend "gcs"` block
   - `subnets`: this environment's subnets and CIDRs
3. Rename the `envs/<env>` folder if your environment names differ from
   `dev`/`test`/`stage`/`prod`, and update the backend prefix to match.

## Usage

```bash
cd envs/dev
terraform init
terraform validate
terraform plan
terraform apply
```

Repeat in `envs/test`, `envs/stage`, then `envs/prod`.

Re-run `terraform init` only after changing the backend or a module `source`
path. Edits inside `modules/vpc` are picked up by `plan` directly.

## Making changes

- **One environment only** (CIDRs, flow logs, NAT): edit that environment's
  `terraform.tfvars` and plan/apply in its folder.
- **All environments** (new firewall rule, naming, defaults): edit
  `modules/vpc`, then plan in each environment, dev first and prod last.
- **New environment**: copy an existing `envs/<env>` folder, change the backend
  prefix and `terraform.tfvars`, and make sure the projects stage has a host
  project for it.

## CIDR plan

Ranges must not overlap across environments, so the VPCs can later be peered
or connected through a hub without renumbering. The example values use one
/16 per environment, split into /20 subnets per region:

| Environment | Range | us-east1 | us-central1 | GKE secondary |
|---|---|---|---|---|
| dev | 10.10.0.0/16 | 10.10.0.0/20 | 10.10.16.0/20 | – |
| test | 10.20.0.0/16 | 10.20.0.0/20 | 10.20.16.0/20 | – |
| stage | 10.30.0.0/16 | 10.30.0.0/20 | 10.30.16.0/20 | – |
| prod | 10.40.0.0/16 | 10.40.0.0/20 | 10.40.16.0/20 | pods 10.140.0.0/16, services 10.141.0.0/20 |

## Outputs

Each environment exposes:

- `network`: VPC `id`, `name`, and `self_link`
- `subnets`: map of subnet key to `self_link`, `region`, and `cidr`

Later stages (service projects, GKE, and so on) can read these through
`terraform_remote_state` with prefix `network/<env>`.

## Version control

- Commit `.terraform.lock.hcl` in each env folder after the first `init`.
- `terraform.tfvars` files are committed; they hold configuration, not secrets.
  Put anything sensitive in an ignored `*.local.tfvars` or `*.secret.tfvars`.
- State, plan files, and `.terraform/` are ignored.
