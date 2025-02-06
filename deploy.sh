aws cloudformation create-stack --stack-name WebSocketServerStack \
    --template-body file://websocket-server.yaml \
    --parameters ParameterKey=AWSAccountId,ParameterValue=$AWS_ACCOUNT_ID \
                 ParameterKey=KeyPairName,ParameterValue=websocket-key \
                 ParameterKey=VpcId,ParameterValue=$AWS_VPC_ID \
                 ParameterKey=GitHubRepoURL,ParameterValue=prochafilho/openai-realtime-api-node \
                 ParameterKey=AppDirectory,ParameterValue="."\
    --capabilities CAPABILITY_NAMED_IAM
