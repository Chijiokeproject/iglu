variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }
variable "database_name" {
  type    = string
  default = "app"
}
variable "master_username" {
  type    = string
  default = "dbadmin"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "allocated_storage" {
  type    = number
  default = 50
}
variable "multi_az" {
  type    = bool
  default = true
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "skip_final_snapshot" {
  type        = bool
  description = "Skip the final RDS snapshot during deletion. Keep false for recoverable teardown."
  default     = false
}
variable "final_snapshot_identifier" {
  type        = string
  description = "Optional final snapshot name. When omitted, a stable random suffix prevents collisions with snapshots from earlier database lifecycles."
  default     = null
}
variable "backup_retention_period" {
  type    = number
  default = 14
}
variable "tags" {
  type    = map(string)
  default = {}
}
