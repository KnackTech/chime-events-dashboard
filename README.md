# Amazon Chime SDK Meeting Events Dashboard

Originally published in this great blog post and all the code credit goes to the original author: 
https://aws.amazon.com/blogs/business-productivity/monitoring-and-troubleshooting-with-amazon-chime-sdk-meeting-events

The blog post above describes deploying a Amazon Chime events dashboard to monitor and troubleshoot `amazon-chime-sdk-js` usage. The only problem we had at Knack when reading this blog post is that we manage our infra via Terraform and the post had only CloudFormation templates so we migrated that to Terraform and wanted to share the code if anybody else needed it.

We wrote more about this here: https://engineering.joinknack.com/chime-events-dashboard/