locals {
  name    = "vpc-${var.env}-shared"
  regions = toset([for s in values(var.subnets) : s.region])
  cidrs = flatten([
    for s in values(var.subnets) : concat([s.ip_cidr_range], values(s.secondary_ranges))
  ])
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# --- VPC and subnets --------------------------------------------------------

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = local.name
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode
  description             = "Shared VPC for the ${var.env} environment"

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = lower("sn-${var.env}-${each.key}")
  network                  = google_compute_network.this.id
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
  project       = var.project_id
  name          = "${local.name}-allow-internal"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = local.cidrs

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.iap_ssh_enabled ? 1 : 0

  project       = var.project_id
  name          = "${local.name}-allow-iap-ssh"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"] # Google IAP TCP forwarding range

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# --- Egress: Cloud Router + Cloud NAT per region ----------------------------

resource "google_compute_router" "this" {
  for_each = var.enable_nat ? local.regions : toset([])

  project = var.project_id
  name    = "cr-${local.name}-${each.key}"
  region  = each.key
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  for_each = google_compute_router.this

  project                            = var.project_id
  name                               = "nat-${local.name}-${each.key}"
  region                             = each.key
  router                             = each.value.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Shared VPC host enablement ---------------------------------------------

resource "google_compute_shared_vpc_host_project" "this" {
  count = var.enable_shared_vpc ? 1 : 0

  project    = var.project_id
  depends_on = [google_compute_network.this]
}
