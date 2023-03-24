locals {
  service_name  = "chime-events-dashboard"
  combined_name = "${var.environment}_${local.service_name}"
}

resource "aws_lambda_function" "meeting_event_uploader" {
  filename      = "${path.module}/meeting_event_uploader.zip"
  role          = aws_iam_role.meeting_event_uploader_role.arn
  handler       = "meeting_event_uploader.handler"
  function_name = "${var.environment}-meeting-event-uploader"

  runtime  = "nodejs16.x"

  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.meeting_event_log_group.name,
      ACCESS_CONTROL_ALLOW_ORIGIN: var.access_control_allow_origin,
      MEETING_EVENT_METRIC_NAMESPACE: var.meeting_event_metric_namespace
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "permission_for_meeting_event_uploader" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.meeting_event_uploader.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.meeting_event_api.id}/*/POST/${var.meeting_event_api_path_name}"
}

resource "aws_cloudwatch_log_group" "meeting_event_log_group" {
  name = "MeetingEventLogGroup"
}

resource "aws_api_gateway_rest_api" "meeting_event_api" {
  name = "MeetingEventsAPI"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "meeting_events_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.meeting_event_api.id
  parent_id = aws_api_gateway_rest_api.meeting_event_api.root_resource_id
  path_part = var.meeting_event_api_path_name
}

resource "aws_api_gateway_method" "meeting_event_api_method" {
  rest_api_id = aws_api_gateway_rest_api.meeting_event_api.id
  resource_id = aws_api_gateway_resource.meeting_events_api_resource.id
  http_method = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "meeting_event_api_method_gateway" {
  rest_api_id = aws_api_gateway_rest_api.meeting_event_api.id
  resource_id             = aws_api_gateway_resource.meeting_events_api_resource.id
  http_method             = aws_api_gateway_method.meeting_event_api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.meeting_event_uploader.arn}/invocations"  
}

resource "aws_api_gateway_deployment" "meeting_event_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.meeting_event_api_method_gateway,
    aws_api_gateway_method.meeting_event_api_method
  ]

  rest_api_id = aws_api_gateway_rest_api.meeting_event_api.id
}

resource "aws_api_gateway_stage" "meeting_event_api_stage" {
  stage_name = var.meeting_event_api_stage_name
  rest_api_id = aws_api_gateway_rest_api.meeting_event_api.id
  deployment_id = aws_api_gateway_deployment.meeting_event_api_deployment.id
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.meeting_event_api_access_log_group.arn
    
    format = jsonencode({ 
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      })
  }
}

resource "aws_api_gateway_account" "meeting_event_api_account" {
  depends_on = [
    aws_iam_role.meeting_event_api_access_log_role
  ]
  
  cloudwatch_role_arn = aws_iam_role.meeting_event_api_access_log_role.arn
}

resource "aws_iam_role" "meeting_event_api_access_log_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "sts:AssumeRole",
          Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
      }
    ],
  })

  path = "/"
  managed_policy_arns = [ "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs" ]
}

resource "aws_cloudwatch_log_group" "meeting_event_api_access_log_group" {
  name = "MeetingEventAPIAccessLogGroup"
}

resource "aws_cloudwatch_dashboard" "meeting_event_dashboard" {
  dashboard_name = "ChimeEventsDashboard"
  dashboard_body = <<EOF
{
    "widgets": [
      {
        "type": "log",
        "x": 12,
        "y": 6,
        "width": 12,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | fields @timestamp, @message\n| filter name = \"meetingStartRequested\" and attributes.sdkName = \"amazon-chime-sdk-js\"\n| stats count(*) as startRequested by attributes.browserName as browser, attributes.browserMajorVersion as version\n| sort startRequested desc\n| limit 10",
            "region": "${var.region}",
            "stacked": false,
            "title": "Top 10 browsers (JavaScript)",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 0,
        "y": 6,
        "width": 12,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | fields @timestamp, @message\n| filter name in [\"meetingStartRequested\"]\n| stats count(*) as startRequested by attributes.osName as operatingSystem\n| sort startRequested desc\n| limit 10",
            "region": "${var.region}",
            "stacked": false,
            "title": "Top 10 operating systems",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 0,
        "y": 30,
        "width": 24,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | filter name in [\"audioInputFailed\", \"videoInputFailed\"]\n| fields\nfromMillis(@timestamp) as timestamp,\nattributes.sdkName as sdkName,\nconcat(attributes.osName, \" \", attributes.osVersion) as operatingSystem,\nconcat(attributes.browserName, \" \", attributes.browserMajorVersion) as browser,\nreplace(name, \"InputFailed\", \"\") as kind,\nconcat(attributes.audioInputErrorMessage, attributes.videoInputErrorMessage) as reason\n| sort @timestamp desc\n",
            "region": "${var.region}",
            "stacked": false,
            "title": "Audio and video input failures",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 0,
        "y": 18,
        "width": 24,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | filter name in [\"meetingStartFailed\"]\n| fields fromMillis(@timestamp) as timestamp,\nattributes.sdkName as sdkName,\nconcat(attributes.osName, \" \", attributes.osVersion) as operatingSystem,\nconcat(attributes.browserName, \" \", attributes.browserMajorVersion) as browser,\nattributes.meetingStatus as failedStatus,\nconcat(attributes.signalingOpenDurationMs / 1000, \"s\")  as signalingOpenDurationMs,\nattributes.retryCount as retryCount\n| sort @timestamp desc\n",
            "region": "${var.region}",
            "stacked": false,
            "title": "Meeting join failures",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 0,
        "y": 24,
        "width": 24,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | filter name in [\"meetingFailed\"]\n| fields\nfromMillis(@timestamp) as timestamp,\nattributes.sdkName as sdkName,\nconcat(attributes.osName, \" \", attributes.osVersion) as operatingSystem,\nconcat(attributes.browserName, \" \", attributes.browserMajorVersion) as browser,\nattributes.meetingStatus as failedStatus,\nconcat(attributes.meetingDurationMs / 1000, \"s\") as meetingDurationMs,\nattributes.retryCount as retryCount,\nattributes.poorConnectionCount as poorConnectionCount\n| sort @timestamp desc\n",
            "region": "${var.region}",
            "stacked": false,
            "title": "Dropped attendees",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 12,
        "y": 0,
        "width": 12,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | filter name in [\"meetingStartRequested\"]\n| stats count(*) as startRequested by attributes.sdkName as SDK, attributes.sdkVersion as version",
            "region": "${var.region}",
            "stacked": false,
            "title": "SDK versions",
            "view": "table"
        }
      },
      {
        "type": "log",
        "x": 0,
        "y": 0,
        "width": 12,
        "height": 6,
        "properties": {
            "query": "SOURCE \"${aws_cloudwatch_log_group.meeting_event_log_group.name}\" | filter name in [\"meetingStartRequested\"]\n| stats count(*) as platform by attributes.sdkName",
            "region": "${var.region}",
            "stacked": false,
            "title": "SDK platforms (JavaScript, iOS, and Android)",
            "view": "pie"
        }
      },
      {
        "type": "text",
        "x": 0,
        "y": 36,
        "width": 24,
        "height": 9,
        "properties": {
            "markdown": "\n## How to search events for a specific attendee?\n\nYou can use Amazon CloudWatch Logs Insights to search and analyze Amazon Chime SDK attendees.  For more information, see [Analyzing Log Data with CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html) in the *AWS CloudWatch Logs User Guide*.\n\n1. Click on the row number (▶) to expand a row.\n2. You can see detailed failure information.\n  - **attributes.meetingErrorMessage** explains the reason for the meeting failure.\n  - **attributes.audioInputErrorMessage** and **attributes.videoInputErrorMessage** indicate problems with the microphone and camera.\n  - **attributes.meetingHistory** shows up to last 15 attendee actions and events.\n3. To view a specific attendee's events, take note of **attributes.attendeeId** and choose **Insights** in the navigation pane.\n4. Select your ChimeBrowserMeetingEventLogs log group that starts with your stack name.\n  ```\n  __your_stack_name__ChimeBrowserMeetingEventLogs-...\n  ```\n5. In the query editor, delete the current contents, enter the following filter function, and then choose **Run query**.\n  ```\n  filter attributes.attendeeId = \"__your_attendee_id__\"\n  ```\n\n  The results show the number of SDK events from device selection to meeting end.\n"
        }
      },
      {
        "type": "metric",
        "x": 12,
        "y": 12,
        "width": 12,
        "height": 6,
        "properties": {
            "metrics": [
                [ "${var.meeting_event_metric_namespace}", "meetingStartDurationMs", "sdkName", "amazon-chime-sdk-js" ]
            ],
            "view": "timeSeries",
            "stacked": false,
            "region": "${var.region}",
            "title": "Meeting start duration (P50)",
            "period": 300,
            "stat": "p50",
            "legend": {
                "position": "bottom"
            },
            "yAxis": {
                "left": {
                    "min": 0
                }
            }
        }
      },
      {
        "type": "metric",
        "x": 0,
        "y": 12,
        "width": 12,
        "height": 6,
        "properties": {
            "metrics": [
                [ "${var.meeting_event_metric_namespace}", "meetingStartDurationMs", "sdkName", "amazon-chime-sdk-js" ]
            ],
            "view": "timeSeries",
            "stacked": false,
            "region": "${var.region}",
            "title": "Meeting start duration (P95)",
            "period": 300,
            "stat": "p95",
            "legend": {
                "position": "bottom"
            },
            "yAxis": {
                "left": {
                    "min": 0
                }
            }
        }
      }
    ]
}
EOF
}

output "meeting_event_api_endpoint" {
  value = "https://${aws_api_gateway_rest_api.meeting_event_api.id}.execute-api.${var.region}.amazonaws.com/${var.meeting_event_api_stage_name}/${var.meeting_event_api_path_name}"
}

output "meeting_event_dashboard" {
  description = "Meeting event dashboard"
  value = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.meeting_event_dashboard.dashboard_arn}"
}