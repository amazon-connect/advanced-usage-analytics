SELECT 
  ctr.awsaccountid,
  ctr.instancearn,
  ctr.channel,
  ctr.queue.name as queue_name,
  ctr.systemendpoint.address as system_endpoint,
  ctr.contactid,
  ctr.initialContactId,
  ctr.customerendpoint.address as customer_endpoint,
  ctr.Agent.ARN as AgentARN,
  ctr.transferredtoendpoint as TransferEndpoint,
  ctr.initiationmethod as Call_Initiation_Method,
  ctr.InitiationTimestamp as CTR_Initiation_Timestamp,
  ctr.Agent.ConnectedToAgentTimestamp as Connected_To_Agent_Timestamp,
  ctr.DisconnectTimestamp as Disconnect_Timestamp,
  ctr.ConnectedToSystemTimestamp as Connected_To_System_Timestamp,
  ctr.TransferCompletedTimestamp as Transfer_Completed_Timestamp,

  -- Calculate relevant usage amounts estimates

  CASE  
    WHEN (ctr.initiationmethod <> 'CALLBACK') THEN 
        CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.InitiationTimestamp)) as INTEGER)
    WHEN (ctr.initiationmethod = 'CALLBACK') THEN 
        CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp)) as INTEGER)
  END AS Connect_Service_Seconds,

  CAST(
      CAST( to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS DECIMAL(20))-
      CAST( to_unixtime( from_iso8601_timestamp(ctr.TransferCompletedTimestamp) ) AS DECIMAL(20))
      AS INTEGER )
  AS Thirdparty_Telco_inSeconds,

  CAST(
    CAST( to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS DECIMAL(20))-
    CAST( to_unixtime( from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp) ) AS DECIMAL(20))
  AS INTEGER ) AS CustomerCallLength_Telco_inSeconds,

  -- Calculate relevant usage amounts ROUNDED
  -- If contact id == initial conn id then that conn is the telephony connection between customer and connect. And thus the Telephony charge we calculate via the CTR. The rest of the connections, if endpoint is phone number then we calculate that charge in here. 
  -- check here. (add the duration of the CTRs in the chain) 
  -- service min
  CASE  
      WHEN (ctr.initiationmethod <> 'CALLBACK') THEN 
          CASE (CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.InitiationTimestamp)) as INTEGER) < 10)
          WHEN true THEN 10
            ELSE CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.InitiationTimestamp)) as INTEGER)
          END
      WHEN (ctr.initiationmethod = 'CALLBACK') THEN 
          CASE (CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp)) as INTEGER) < 10)
          WHEN true THEN 10
            ELSE CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp)) as INTEGER)
          END
  END AS Connect_Service_Seconds_Rounded,

  -- case for when its a third party connection, but not the original customer conn, that one we will use CTR to calculate.

  CASE (CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.TransferCompletedTimestamp)) as INTEGER) < (60))            
    WHEN true THEN CAST(60 AS INTEGER)            
  ELSE CAST(
      CAST( to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS DECIMAL(20))-
      CAST( to_unixtime( from_iso8601_timestamp(ctr.TransferCompletedTimestamp) ) AS DECIMAL(20))
      AS INTEGER )
  END AS Thirdparty_Telco_inSeconds_Rounded,

  -- caller telco usage

  CASE (CAST(to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp)) as INTEGER) < (60))            
    WHEN true THEN CAST(60 AS INTEGER)            
  ELSE CAST(
      CAST( to_unixtime(from_iso8601_timestamp(ctr.DisconnectTimestamp)) AS DECIMAL(20))-
      CAST( to_unixtime( from_iso8601_timestamp(ctr.ConnectedToSystemTimestamp) ) AS DECIMAL(20))
      AS INTEGER )
  END AS CustomerCallLength_Telco_inSeconds_Rounded

FROM "amazonconnect_ctr" ctr
ORDER BY ctr.InitiationTimestamp DESC