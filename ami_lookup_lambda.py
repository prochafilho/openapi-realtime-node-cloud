import json
import boto3
import cfnresponse

def lambda_handler(event, context):
    """Retrieve the latest Amazon Linux 2 AMI ID and send a response to CloudFormation."""
    try:
        request_type = event.get("RequestType", "Create")

        # If it's a DELETE request, send a success response and exit
        if request_type == "Delete":
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return

        ec2_client = boto3.client("ec2", region_name="us-east-1")
        response = ec2_client.describe_images(
            Filters=[
                {"Name": "name", "Values": ["amzn2-ami-hvm-*-x86_64-gp2"]},
                {"Name": "state", "Values": ["available"]}
            ],
            Owners=["amazon"]
        )

        latest_image = sorted(response["Images"], key=lambda x: x["CreationDate"], reverse=True)[0]
        response_data = {"ImageId": latest_image["ImageId"]}

        # ✅ Send SUCCESS response back to CloudFormation
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)

    except Exception as e:
        print(f"Error retrieving AMI: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {"Message": str(e)})

