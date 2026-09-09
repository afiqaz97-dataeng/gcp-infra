variable "project_id" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "subscription_name" {
  description = "Set to null to create the topic without a subscription."
  type        = string
  default     = null
}

variable "ack_deadline_seconds" {
  type    = number
  default = 30
}

variable "message_retention_duration" {
  type    = string
  default = "604800s" # 7 days
}

resource "google_pubsub_topic" "this" {
  project = var.project_id
  name    = var.topic_name
}

resource "google_pubsub_subscription" "this" {
  count   = var.subscription_name == null ? 0 : 1
  project = var.project_id
  name    = var.subscription_name
  topic   = google_pubsub_topic.this.name

  ack_deadline_seconds      = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
}

output "topic_name" {
  value = google_pubsub_topic.this.name
}

output "subscription_name" {
  value = var.subscription_name == null ? null : google_pubsub_subscription.this[0].name
}
