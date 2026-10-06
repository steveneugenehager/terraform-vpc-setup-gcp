locals {
  # One VPC per environment, placed in that environment's host project
  vpcs = {
    for key, cfg in var.networks : key => merge(cfg, {
      project_id = local.host_projects[key].project_id
      env        = local.host_projects[key].env
      name       = "vpc-${local.host_projects[key].env}-shared"
    })
  }

  subnets = merge([
    for key, vpc in local.vpcs : {
      for sn_key, sn in vpc.subnets :
      "${key}-${sn_key}" => merge(sn, {
        vpc_key    = key
        project_id = vpc.project_id
        name       = lower("sn-${vpc.env}-${sn_key}")
      })
    }
  ]...)

  nat_regions = merge([
    for key, vpc in local.vpcs : {
      for region in distinct([for s in values(vpc.subnets) : s.region]) :
      "${key}-${region}" => {
        vpc_key    = key
        project_id = vpc.project_id
        region     = region
        name       = "${vpc.name}-${region}"
      }
    } if vpc.enable_nat
  ]...)

  vpc_cidrs = {
    for key, vpc in local.vpcs : key => flatten([
      for s in values(vpc.subnets) : concat([s.ip_cidr_range], values(s.secondary_ranges))
    ])
  }
}

check "every_network_has_a_host_project" {
  assert {
    condition     = length(setsubtract(keys(var.networks), keys(local.host_projects))) == 0
    error_message = "var.networks has keys with no matching net-host project: ${join(", ", setsubtract(keys(var.networks), keys(local.host_projects)))}"
  }
}

# --- APIs -------------------------------------------------------------------

resource "google_project_service" "compute" {
  for_each = local.vpcs

  project            = each.value.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# --- VPCs and subnets -------------------------------------------------------

resource "google_compute_network" "vpc" {
  for_each = local.vpcs

  project                 = each.value.project_id
  name                    = each.value.name
  auto_create_subnetworks = false
  routing_mode            = each.value.routing_mode
  description             = "Shared VPC for the ${each.value.env} environment"

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  for_each = local.subnets

  project                  = each.value.project_id
  name                     = each.value.name
  network                  = google_compute_network.vpc[each.value.vpc_key].id
  region                   = each.value.region
  ip_cidr_range            = each.value.ip_cidr_range
  private_ip_google_access = each.value.private_google_access

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  dynamic "log_config" {
    for_each = each.value.flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# --- Baseline firewall rules ------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  for_each = local.vpcs

  project       = each.value.project_id
  name          = "${each.value.name}-allow-internal"
  network       = google_compute_network.vpc[each.key].id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = local.vpc_cidrs[each.key]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  for_each = var.iap_ssh_enabled ? local.vpcs : {}

  project       = each.value.project_id
  name          = "${each.value.name}-allow-iap-ssh"
  network       = google_compute_network.vpc[each.key].id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"] # Google IAP TCP forwarding range

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# --- Egress: Cloud Router + Cloud NAT per VPC/region ------------------------

resource "google_compute_router" "router" {
  for_each = local.nat_regions

  project = each.value.project_id
  name    = "cr-${each.value.name}"
  region  = each.value.region
  network = google_compute_network.vpc[each.value.vpc_key].id
}

resource "google_compute_router_nat" "nat" {
  for_each = local.nat_regions

  project                            = each.value.project_id
  name                               = "nat-${each.value.name}"
  region                             = each.value.region
  router                             = google_compute_router.router[each.key].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Shared VPC host enablement ---------------------------------------------

resource "google_compute_shared_vpc_host_project" "host" {
  for_each = { for k, v in local.vpcs : k => v if v.enable_shared_vpc }

  project    = each.value.project_id
  depends_on = [google_compute_network.vpc]
}
