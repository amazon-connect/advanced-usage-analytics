CREATE EXTERNAL TABLE amazonconnect_CTR (
AWSAccountId string,
AWSContactTraceRecordFormatVersion string,
Agent struct<
    ARN: string,
    AfterContactWorkDuration: int,
    AfterContactWorkEndTimestamp: string,
    AfterContactWorkStartTimestamp: string,
    AgentInteractionDuration: int,
    ConnectedToAgentTimestamp: string,
    CustomerHoldDuration: int,
    HierarchyGroups: string,
    LongestHoldDuration: int,
    NumberOfHolds: int,
    RoutingProfile: struct<
        ARN: string,
        Name: string
    >,
    Username: string
>,
AgentConnectionAttempts int,
Attributes string,
Channel string,
ConnectedToSystemTimestamp string,
ContactId string,
CustomerEndpoint struct< 
    Address: string,
    Type: string 
>,
DisconnectTimestamp string,
InitialContactId string,
InitiationMethod string,
InitiationTimestamp string,
InstanceARN string,
LastUpstringTimestamp string,
MediaStreams array< 
    struct<
        Type: string
    >
>,
NextContactId string,
PreviousContactId string,
Queue struct<
    ARN: string,
    DequeueTimestamp: string,
    Duration: int,
    EnqueueTimestamp: string,
    Name: string
>,
Recording string,
Recordings string,
SystemEndpoint struct<
    Address: string,
    Type: string 
>,
TransferCompletedTimestamp string,
TransferredToEndpoint string  
) 
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://${storageDestinationS3}/CTR'