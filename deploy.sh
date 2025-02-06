#!/bin/bash

# 🚀 Step 1: Define Deployment Variables
UNIQUE_SUFFIX=$(date +%s)  # Generates a unique timestamp-based suffix
STACK_NAME="WebSocketMainStack-$UNIQUE_SUFFIX"
APP_BUCKET="websocket-deployment-$UNIQUE_SUFFIX"  # Unique S3 bucket name
AWS_REGION="us-east-1"  # Set your AWS region

# AWS Parameters
GITHUB_REPO_URL="prochafilho/openai-realtime-api-node"
APP_DIRECTORY="."
KEY_PAIR_NAME="websocket-key"

echo "🚀 Deploying CloudFormation stacks with unique suffix: $UNIQUE_SUFFIX"

# 🚀 Step 2: Ensure S3 Bucket Exists
echo "🔹 Checking if S3 bucket exists..."
if aws s3api head-bucket --bucket "$APP_BUCKET" 2>/dev/null; then
    echo "✅ S3 bucket $APP_BUCKET already exists."
else
    echo "🚀 Creating unique S3 bucket: $APP_BUCKET..."
    
    if [ "$AWS_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$APP_BUCKET" --region "$AWS_REGION"
    else
        aws s3api create-bucket --bucket "$APP_BUCKET" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
fi

# 🚀 Ensure the Lambda function ZIP package exists
if [ ! -f "twilio-webhook-lambda.zip" ]; then
    echo "🚀 Creating Lambda function package twilio-webhook-lambda.zip..."
    zip twilio-webhook-lambda.zip twilio_webhook_lambda.py
fi

# 🚀 Step 3: Upload CloudFormation Templates & Lambda Code to S3
echo "🔹 Uploading CloudFormation templates to S3..."
aws s3 cp main-stack.yaml s3://$APP_BUCKET/ --region $AWS_REGION
aws s3 cp websocket-server-stack.yaml s3://$APP_BUCKET/ --region $AWS_REGION
aws s3 cp twilio-lambda-stack.yaml s3://$APP_BUCKET/ --region $AWS_REGION
aws s3 cp twilio-integration-stack.yaml s3://$APP_BUCKET/ --region $AWS_REGION
aws s3 cp twilio-webhook-lambda.zip s3://$APP_BUCKET/ --region $AWS_REGION

# 🚀 Step 4: Deploy Main CloudFormation Stack
echo "🔹 Deploying Main CloudFormation Stack: $STACK_NAME..."
CREATE_OUTPUT=$(aws cloudformation create-stack --stack-name $STACK_NAME \
    --template-url https://s3.$AWS_REGION.amazonaws.com/$APP_BUCKET/main-stack.yaml \
    --region $AWS_REGION \
    --parameters ParameterKey=UniqueSuffix,ParameterValue=$UNIQUE_SUFFIX \
                 ParameterKey=AWSAccountId,ParameterValue=$AWS_ACCOUNT_ID \
                 ParameterKey=Region,ParameterValue=$AWS_REGION \
                 ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR_NAME \
                 ParameterKey=VpcId,ParameterValue=$AWS_VPC_ID \
                 ParameterKey=SecretId,ParameterValue=$SECRET_ID \
                 ParameterKey=GitHubRepoURL,ParameterValue=$GITHUB_REPO_URL \
                 ParameterKey=AppDirectory,ParameterValue=$APP_DIRECTORY \
                 ParameterKey=TwilioAccountSid,ParameterValue=$TWILIO_ACCOUNT_SID \
                 ParameterKey=TwilioAuthToken,ParameterValue=$TWILIO_AUTH_TOKEN \
                 ParameterKey=TwilioPhoneNumber,ParameterValue=$TWILIO_PHONE_NUMBER \
                 ParameterKey=S3Bucket,ParameterValue=$APP_BUCKET \
    --capabilities CAPABILITY_NAMED_IAM 2>&1)

if [[ "$CREATE_OUTPUT" == *"ValidationError"* ]]; then
    echo "❌ CloudFormation stack creation failed!"
    echo "$CREATE_OUTPUT"
    exit 1
fi

# 🚀 Step 5: Monitor Stack Deployment
echo "⏳ Waiting for Main Stack deployment to complete..."
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $AWS_REGION

echo "✅ Main Stack deployment complete!"
