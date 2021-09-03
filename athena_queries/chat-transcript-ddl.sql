CREATE EXTERNAL TABLE IF NOT EXISTS amazonconnect_chat (
  `instanceId` string,
  `contactId` string,
  `system_msg` int,
  `customer_msg` int,
  `agent_msg` int,
  `total_msg` int 
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'serialization.format' = '1'
) LOCATION 's3://${ConnectChatTranscriptBucket}/chatusage/'