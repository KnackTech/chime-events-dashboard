resource "aws_iam_role" "meeting_event_uploader_role" {
  name = "meeting_event_uploader_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole",
      }
    ]
  })
}

resource "aws_iam_role_policy" "meeting_event_uploader_policy" {
  role = aws_iam_role.meeting_event_uploader_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "cloudwatch:PutMetricData"]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}