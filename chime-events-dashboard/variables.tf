variable "environment" {
  description = "The name of the environment"
}

variable "region" {
  description = "AWS region"
}

variable "access_control_allow_origin" {
  description = "The value for the Access-Control-Allow-Origin header. For example, you can specify https://example.com. The default value (*) allows all origins to access the API response."
}

variable "meeting_event_metric_namespace" {
  description = "The namespace for the metric data. To avoid conflicts with AWS service namespaces, you should not specify a namespace that begins with AWS/"
}

variable "meeting_event_api_stage_name" {
  description = "The name for the meeting event API"
}

variable "meeting_event_api_path_name" {
  description = "The path name for the meeting event API"
}