CREATE EXTERNAL TABLE amazonconnect_agentevents (
  AWSAccountId string,
  AgentARN string,
  CurrentAgentSnapshot struct<
      AgentStatus: struct<
        ARN: string,
        Name: string,
        StartTimestamp: string
      >,
      Configuration: struct<
        AgentHierarchyGroups: string,
        FirstName: string,
        LastName: string,
        RoutingProfile: struct<
            ARN: string,
            Concurrency: array<
              struct<
                  AvailableSlots: int,
                  Channel: string,
                  MaximumSlots: int
              >
            >,
            DefaultOutboundQueue: struct<
              ARN: string,
              Channels: array<
                  string
              >,
              Name: string
            >,
            InboundQueues: array<
              struct<
                  ARN: string,
                  Channels: array<string>,
                  Name: string
              >
            >,
            Name: string
        >,
        Username: string
      >,
      Contacts: array<string>
  >,
  EventId string,
  EventTimestamp string,
  EventType string,
  InstanceARN string,
  PreviousAgentSnapshot struct<
      AgentStatus: struct<
        ARN: string,
        Name: string,
        StartTimestamp: string
      >,
      Configuration: struct<
        AgentHierarchyGroups: array<string>,
        FirstName: string,
        LastName: string,
        RoutingProfile: struct<
            ARN: string,
            Concurrency: array<
              struct<
                  AvailableSlots: int,
                  Channel: string,
                  MaximumSlots: int
              >
            >,
            DefaultOutboundQueue: struct<
              ARN: string,
              Channels: array<string>,
              Name: string
            >,
            InboundQueues: array<
              struct<
                  ARN: string,
                  Channels: array<string>,
                  Name: string
              >
            >,
            Name: string
        >,
        Username: string
      >,
      Contacts: array<
        struct<
            Channel: string,
            ConnectedToAgentTimestamp: string,
            ContactId: string,
            InitialContactId: string,
            InitiationMethod: string,
            Queue: struct<
              ARN: string,
              Name: string
            >,
            QueueTimestamp: string,
            State: string,
            StateStartTimestamp: string
        >
      >
  >,
  Version string
) 
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://${storageDestinationS3}/AgentEvents'