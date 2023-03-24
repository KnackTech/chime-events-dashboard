terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region                   = "us-east-1"
  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
  
  profile = ""
}

module "chime_events_dashboard" {
  source = "./chime-events-dashboard"

  environment                    = "development"
  region                         = "us-east-1"
  access_control_allow_origin    = "*"
  meeting_event_api_path_name    = "meetingevents"
  meeting_event_api_stage_name   = "development"
  meeting_event_metric_namespace = "AmazonChimeSDKMeetingEvents"
}


# In case need a sanity test, here's an EC2 instance to boot up
# resource "aws_instance" "app_server" {
#   ami                    = "ami-052efd3df9dad4825"
#   instance_type          = "t2.micro"
#   vpc_security_group_ids = ["sg-05815e5af07672e9b"]
#   subnet_id              = "subnet-05bf47f4135cd50a8"

#   tags = {
#     Name = "ExampleAppServerInstance"
#   }
# }