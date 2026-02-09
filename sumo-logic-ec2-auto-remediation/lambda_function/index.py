import json
import boto3
import os
import logging

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

INSTANCE_ID = os.environ.get("EC2_INSTANCE_ID")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")

logging.basicConfig(level=logging.INFO)

def handler(event, context):
    logging.info("Received alert: %s", json.dumps(event))

    if not INSTANCE_ID or not SNS_TOPIC_ARN:
        error_msg = "EC2_INSTANCE_ID or SNS_TOPIC_ARN environment variable not set"
        logging.error(error_msg)
        return {
            "statusCode": 500,
            "body": error_msg
        }

    try:
        ec2.reboot_instances(InstanceIds=[INSTANCE_ID])
        logging.info(f"Reboot initiated for EC2 instance {INSTANCE_ID}")

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="Sumo Logic Alert - EC2 Restarted",
            Message=f"EC2 instance {INSTANCE_ID} restarted due to high latency."
        )
        logging.info(f"SNS notification sent to topic {SNS_TOPIC_ARN}")

        return {
            "statusCode": 200,
            "body": "EC2 rebooted and notification sent"
        }

    except Exception as e:
        logging.error(f"Error during EC2 reboot or SNS publish: {str(e)}")
        return {
            "statusCode": 500,
            "body": f"Error: {str(e)}"
        }
