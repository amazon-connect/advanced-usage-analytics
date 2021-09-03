# Cloudformation Documentation 

## Main stack

https://aws.amazon.com/premiumsupport/knowledge-center/cloudformation-nested-stacks-values/

## Frontend stack
### Input Params
* CcpUrl
* myBucketArn -- this bucket stores the connection data. 
* storageDestinationS3 -- this bucket is where the connects data wants to be stored
* -- SamlUrl //need to work on 

### Resources 
* Cloudfront -- Custom CCP
    * CFDistro
    * CFReadPolicy
    * CloudFrontOAI

* S3 -- This bucket hosts static html page served by Cloudfront, this is created
    * WebHostingS3Bucket

* Lambda -- This Lambda generates the HTML page, uploads it to S3, which embeds the Custom CCP Cloudfront
    * CustomResourceLambdaFunction
    * LambdaIAMRole
    * LambdaInvokePermission
    * LambdaTrigger

* API Gateway -- Passes connections data generated by custom CCP to Firehose 
    * apiDeployment
    * apigwRole
    * apigwRolePolicy
    * myRestApi

* Firehose -- takes data from API Gateway and dumps into S3
    * Firehose
    * firehoserole
    * firehoses3policy

## Backend stack
### Input Params 

* instanceIdParam
* instanceNameParam   
* storageDestinationS3 -- bucket stores CTRs

### Resources 

* Firehose -- CTR firehose (should be optional, by adding Condition in resource and in Condition section)
    * FireHoseCTRStreamLogGroup
    * FirehoseCTRStream
    * FirehoseCTRStreamLogS3

* Kinesis stream -- agent event -> dumps into firehose
    * AgentEventKinesisStream

* Firehose -- Agent event stream (also should be optional)
    * FireHoseAgentEvents
    * FireHoseAgentEventsLogGroup
    * FireHoseAgentEventsLogS3

* Firehose resources shared across both 
    * FirehoseLogsPolicy
    * FirehosePolicy
    * FirehoseRole
    * FirehoseS3Policy
    * FirehoseStreamsSubscribePolicy    

* Lambda -- Custom Lambda to modify s3 bucket notification && adds firehose encryption
    * CustomResourceLambdaFunction
    * LambdaIAMRole
    * LambdaInvokePermission
    * LambdaTrigger

* Lambda -- FormatLogsforDBLambda -- This we can remove this one

* Glue - DB used to store meta data for Athena
    * ConnectGlueDatabase

* Athena -- Create datasets, tables and saved queries 
    * Creates Table for frontend connection data
        * APILogsAthenaNamedQuery -- needs to be updated to use connections data
    * Creates Table for CTR data
        * ContactTraceRecordsAthenaNamedQuery
    * Calculates usage -- joins CTR and connections Table 
        * ReconciliationReportAthenaNamedQuery -- needs to be updated
    * Creates Table for Agent event data
        * AgentEventAthenaNamedQuery

## Chat Stack
### Input
* NotificationBucket
* TranscriptBucketPrefix

### Resources

* Lambda -- Gets calculates the usage from transcripts triggered by s3 notification 
    * S3NotificationLambdaFunction    

* Lambda -- Custom resources, sets up s3 notification on the chat transcript s3 bucket
    * CustomResourceLambdaFunction    
    * LambdaTrigger

* Lambda policy/roles shared for both Lambdas (which need to be updated)
    * LambdaIAMRole
    * LambdaInvokePermission  