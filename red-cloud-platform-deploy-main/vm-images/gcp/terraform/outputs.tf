output "image_name" {
  description = "Name of the created image"
  value       = "infinia-${var.infinia_version}"
}

output "instance_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.infinia_vm.name
}

output "instance_zone" {
  description = "Zone of the VM instance"
  value       = google_compute_instance.infinia_vm.zone
}
