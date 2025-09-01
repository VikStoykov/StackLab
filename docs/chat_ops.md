# Intro

In this tutorial, I'll demonstrate how to set up integration between CloudWatch alarms and a Slack channel. Whenever a new CloudWatch alarm is created, we'll receive a Slack notification confirming the registration of the alarm. To test this integration, we'll configure a CloudWatch alarm to trigger when the CPU usage of an EC2 instance exceeds 80%. Additionally, we'll configure the system to send a notification to Slack when the alarm is resolved.

Here's how it will work: When a CloudWatch alarm is triggered, it will send a message to an SNS topic. This message will then trigger a Lambda function, which will parse the payload containing the alarm message. Based on the current and previous state of the alarm, the Lambda function will generate a custom message and send it to the designated Slack channel.

## How to configure Slack

1. Create profile in Slack
2. Get a Slack channel webhook URL
2.1 To get a Slack channel webhook URL, you need to create an Incoming Webhook integration in your Slack workspace. Here's how you can do it:
2.2 Open Slack:
Open Slack and navigate to your workspace.
2.3 Go to App Directory:
Click on the "Apps" option located on the left sidebar.
2.4 Search for Incoming Webhooks:
In the Apps section, search for "Incoming Webhooks" in the search bar at the top.
2.5 Add Configuration:
Once you find the "Incoming Webhooks" app, click on it to open it. Then, click on the "Add to Slack" button to add the integration to your workspace.
2.6 Choose Channel:
Select the channel where you want to post messages using the webhook. Click on the "Add Incoming WebHooks integration" button.
2.7 Copy Webhook URL:
After adding the integration, you'll be redirected to a page where you can configure the webhook. Here, you'll find the Webhook URL. It will look something like this:
```https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX```
Copy this URL as it's your webhook URL.
2.8 Configure Settings (Optional):
You can configure other settings like customizing the name and icon for the webhook. Once you're done, click on the "Save Settings" button.
That's it! You now have the webhook URL for your Slack channel. You can use this URL to send messages to the channel programmatically. Make sure to keep the webhook URL secure and avoid sharing it publicly.

## How to test

```curl -X POST --data-urlencode "payload={\"channel\": \"#devops\", \"username\": \"webhookbot\", \"text\": \"This is posted to #my-channel-here and comes from a bot named webhookbot.\", \"icon_emoji\": \":ghost:\"}" https://hooks.slack.com/services/XXX/YYY/ZZZ```

![Alt text](/images/slack_channel.png)

## Run terraform module

```sudo terraform validate```
```sudo terraform plan -target=module.notify```
```sudo terraform apply -target=module.notify```

![Alt text](/images/chatops.gif)

This will create:

* IAM role for the SNS with access to CloudWatch

* Permissions for SNS to write logs to CloudWatch

* SNS topic to receive notifications from CloudWatch

* Generate a random string to create a unique S3 bucket

* Create an S3 bucket to store lambda source code (zip archives)

* Disable all public access to the S3 bucket

* Create an IAM role for the lambda function

* Allow lambda to write logs to CloudWatch

* Create ZIP archive with a lambda function

* Upload ZIP archive with lambda to S3 bucket

* Create lambda function using ZIP archive from S3 bucket

* Create CloudWatch log group with 2 weeks retention policy

* Grant access to SNS topic to invoke a lambda function

* Trigger lambda function when a message is published to "alarms" topic

AWS created Lambda function:
![Alt text](/images/aws_lambda.png)

AWS CloudWatch:
![Alt text](/images/aws_cloudwatch.png)

Slack message:
![Alt text](/images/slack_message.png)

Slack message on successfull deployment:
![Alt text](/images/tommy_meow.png)

## Thanks to

[Video](https://www.youtube.com/watch?v=ox_HJ8w7FPI)
[Document](https://antonputra.com/amazon/send-aws-cloudwatch-alarms-to-slack/)
