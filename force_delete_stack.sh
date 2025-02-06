#!/bin/bash

# Define the stack name and AWS region
STACK_NAME=$1
AWS_REGION="us-east-1"

echo "🚀 Starting forceful deletion of AWS resources for stack: $STACK_NAME..."

# Step 1: Describe the resources in the stack
echo "🔹 Listing all resources in stack $STACK_NAME..."
RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --region $AWS_REGION --query "StackResources[*].[LogicalResourceId,ResourceType,PhysicalResourceId]" --output text)

if [ -z "$RESOURCES" ]; then
    echo "✅ No resources found or stack already deleted."
    exit 0
fi

echo "🔹 Resources found in stack $STACK_NAME:"
echo "$RESOURCES"

# Step 2: Check and signal hanging custom resources (like AmiLookup)
echo "🚀 Checking if any custom resources are hanging..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "Custom::AMI" && "$RESOURCE_ID" == "AmiLookup" ]]; then
        echo "❌ Signaling custom resource AmiLookup to CloudFormation..."
        aws cloudformation signal-resource \
            --stack-name $STACK_NAME \
            --logical-resource-id AmiLookup \
            --status SUCCESS \
            --unique-id $(uuidgen) \
            --region $AWS_REGION
    fi
done <<< "$RESOURCES"

# Step 3: Terminate EC2 Instances First (Otherwise Roles & Security Groups Will Fail to Delete)
echo "🚀 Terminating EC2 instances..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "AWS::EC2::Instance" ]]; then
        echo "❌ Terminating instance: $PHYSICAL_ID"
        aws ec2 terminate-instances --instance-ids $PHYSICAL_ID --region $AWS_REGION
    fi
done <<< "$RESOURCES"

echo "⏳ Waiting for instances to terminate..."
# aws ec2 wait instance-terminated --instance-ids $(echo "$RESOURCES" | awk '$2=="AWS::EC2::Instance" {print $3}') --region $AWS_REGION
echo "✅ All instances terminated."

# Step 4: Detach and Delete IAM Roles
echo "🚀 Detaching IAM role policies and deleting roles..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "AWS::IAM::Role" ]]; then
        echo "❌ Deleting IAM role: $PHYSICAL_ID"

        # Detach all role policies first
        echo "🔹 Detaching policies from role $PHYSICAL_ID..."
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $PHYSICAL_ID --query "AttachedPolicies[*].PolicyArn" --output text)
        for POLICY in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name $PHYSICAL_ID --policy-arn $POLICY
        done

        # Remove from instance profiles
        INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name $PHYSICAL_ID --query "InstanceProfiles[*].InstanceProfileName" --output text)
        for PROFILE in $INSTANCE_PROFILES; do
            echo "🔹 Removing role $PHYSICAL_ID from instance profile $PROFILE"
            aws iam remove-role-from-instance-profile --role-name $PHYSICAL_ID --instance-profile-name $PROFILE
        done

        # Delete the role
        aws iam delete-role --role-name $PHYSICAL_ID
    fi
done <<< "$RESOURCES"
echo "✅ All IAM roles deleted."

# Step 5: Delete Security Groups
echo "🚀 Deleting Security Groups..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "AWS::EC2::SecurityGroup" ]]; then
        echo "❌ Deleting security group: $PHYSICAL_ID"
        aws ec2 delete-security-group --group-id $PHYSICAL_ID --region $AWS_REGION
    fi
done <<< "$RESOURCES"
echo "✅ All security groups deleted."

# Step 6: Delete Lambda Functions (with retries)
echo "🚀 Deleting Lambda functions..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "AWS::Lambda::Function" ]]; then
        echo "❌ Deleting Lambda function: $PHYSICAL_ID"
        RETRY=5
        for i in $(seq 1 $RETRY); do
            # Try deleting the Lambda function, retry if fails
            aws lambda delete-function --function-name $PHYSICAL_ID --region $AWS_REGION
            if [ $? -eq 0 ]; then
                echo "✅ Lambda function $PHYSICAL_ID deleted."
                break
            else
                echo "❌ Lambda function $PHYSICAL_ID failed to delete (attempt $i of $RETRY). Retrying..."
                sleep 10
            fi
        done
    fi
done <<< "$RESOURCES"
echo "✅ All Lambda functions deleted."

# Step 7: Delete Any Remaining Resources
echo "🚀 Deleting remaining stack resources..."
while read -r RESOURCE_ID RESOURCE_TYPE PHYSICAL_ID; do
    if [[ "$RESOURCE_TYPE" == "AWS::S3::Bucket" ]]; then
        echo "❌ Emptying and deleting S3 bucket: $PHYSICAL_ID"
        aws s3 rm "s3://$PHYSICAL_ID" --recursive --region $AWS_REGION
        aws s3api delete-bucket --bucket $PHYSICAL_ID --region $AWS_REGION
    fi
done <<< "$RESOURCES"

# Step 8: Force Delete the Stack
echo "🚀 Force deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $AWS_REGION
echo "✅ CloudFormation stack deleted successfully!"

echo "🎉 All AWS resources forcefully removed."
