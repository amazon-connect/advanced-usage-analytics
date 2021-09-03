CREATE EXTERNAL TABLE amazonconnect_ccpstream (
contactId string,
inbound string,
initialConnectionId string,
initialTimestamp string,
type string,
connections array<
  struct<
    id: string,
    connectingTimestamp: string,
    connectedTimestamp: string,
    disconnectedTimestamp: string,
    agentStatus: struct<
      agentPreferences: string,
      agentStates: array<string>,
      dialableCountries: array<string>,
      softPhoneEnabled: boolean,
      extension: string,
      name: string,
      permissions: array<string>,
      routingProfile: struct<
        channelConcurrencyMap: struct<
          CHAT: int,
          VOICE: int
        >,
        defaultOutboundQueue: struct<
          name: string,
          queueARN: string,
          queueId: string
        >,
        name: string,
        queues: array<
          struct<
            name: string,
            queueARN: string,
            queueId: string
          >
        >,
        routingProfileARN: string,
        routingProfileId: string
      >
    >,
    active: string,
    endpoint: struct<
          agentLogin: string,
          endpointARN: string,
          endpointId: string,
          name: string,
          phoneNumber: string,
          queue: string,
          type: string
    >,
    endpointCountryIso: string,
    history: array<
      struct<
        active: string,
        status: string,
        `timestamp`: string
      >
    >,
    lastUpdate: string,
    status: string,
    type: string
  >
>,
stageConnecting struct<
  attributes: string,
  queue: struct<
        name: string,
        queueARN: string,
        queueId: string
  >,
  thirdPartyConnections: array<string>,
  `timestamp`: string,
  type: string
>,
stageConnected struct<
  attributes: string,
  queue: struct<
        name: string,
        queueARN: string,
        queueId: string
  >,
  thirdPartyConnections: array<string>,
  `timestamp`: string,
  type: string
>,
stageEnded struct<
  attributes: string,
  queue: struct<
        name: string,
        queueARN: string,
        queueId: string
  >,
  thirdPartyConnections: array<string>,
  `timestamp`: string,
  type: string
>,
stageError struct<
  attributes: string,
  queue: struct<
        name: string,
        queueARN: string,
        queueId: string
  >,
  thirdPartyConnections: array<string>,
  `timestamp`: string,
  type: string
>
)  ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://${ConnectionDataBucket}/CCPStreams/'
