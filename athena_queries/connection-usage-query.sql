-- Formate data from CCP usage analytics query
with streamsdata as (
  
  -- Select nested data from CCP frontend
    with rawccpdataset as (
        SELECT 
        ccp.connections as con,
        ccp.contactid,
        ccp.inbound,
        ccp.initialConnectionId,
        ccp.initialTimestamp,
        ccp.stageConnecting,
        ccp.stageConnected,
        ccp.stageEnded,
        ccp.stageError
        FROM "amazonconnect_ccpstream" ccp
    ) 
  -- Flatten connection data into table and join back to CTR data
    SELECT  raw.contactid, 
            conns.id AS conn_id,  
            min(array_min(TRANSFORM(CAST(conns.history AS ARRAY<JSON>), x -> JSON_EXTRACT_SCALAR(x,'$[2]')))) AS initialconnecthistorytimestamp,
            arbitrary(conns.type) AS type, 
            arbitrary(conns.agentStatus).extension AS extension,
            arbitrary(conns.endpoint.type) AS endpoint_type,
            arbitrary(conns.endpoint.phonenumber) AS endpoint_number,
            bool_and(CAST(conns.agentStatus.softphoneEnabled AS boolean)) AS softphoneEnabled,
            bool_or(CAST(inbound AS boolean)) AS inbound,
            arbitrary(initialConnectionId) AS initialConnectionId,
            min(conns.connectingTimestamp) AS connectingTimestamp,
            min(conns.connectedTimestamp) AS connectedTimestamp,
            min(conns.disconnectedTimestamp) AS disconnectedTimestamp,
            arbitrary(conns.endpointCountryISO) AS endpointCountryISO
    FROM rawccpdataset raw
    CROSS JOIN unnest(con) AS t(conns)
    GROUP BY contactid, conns.id
    order by initialconnecthistorytimestamp ASC
), 
-- CTR data
ctrdata as (
    select * from "amazonconnect_ctr" ctr
)

-- here we can do the usage analytics logic after we join these two data sets.
select 
ctrdata.awsaccountid,
ctrdata.instancearn,
ctrdata.channel,
ctrdata.queue.name as queue_name,
ctrdata.systemendpoint.address as system_endpoint,
ctrdata.contactid,
ctrdata.initialContactId,
ctrdata.customerendpoint.address as customer_endpoint,
streamsdata.conn_id as connection_id,
streamsdata.initialConnectionId,
streamsdata.type,
streamsdata.extension,
streamsdata.softphoneEnabled,
streamsdata.inbound,
streamsdata.connectingTimestamp,
streamsdata.connectedTimestamp,
streamsdata.disconnectedTimestamp,
streamsdata.endpointCountryISO,
ctrdata.Agent.ARN as AgentARN,
ctrdata.transferredtoendpoint as TransferEndpoint,
ctrdata.initiationmethod as Call_Initiation_Method,
ctrdata.InitiationTimestamp as CTR_Initiation_Timestamp,
ctrdata.Agent.ConnectedToAgentTimestamp as Connected_To_Agent_Timestamp,
ctrdata.DisconnectTimestamp as Disconnect_Timestamp,
ctrdata.ConnectedToSystemTimestamp as Connected_To_System_Timestamp,
ctrdata.TransferCompletedTimestamp as Transfer_Completed_Timestamp,

-- Calculate relevant usage amounts based on the records

CASE
    WHEN ((ctrdata.contactid = streamsdata.conn_id OR (streamsdata.conn_id IS NULL AND ctrdata.initialContactId IS NULL )) AND ctrdata.initiationmethod <> 'CALLBACK') THEN 
        CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.InitiationTimestamp)) as INTEGER) 
    WHEN ((ctrdata.contactid = streamsdata.conn_id) AND ctrdata.initiationmethod = 'CALLBACK') THEN 
        CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp)) as INTEGER)
    END AS Connect_Service_Seconds,

CASE (streamsdata.type = 'agent' AND streamsdata.softphoneEnabled = false)
    WHEN true THEN 
        CAST(
            CAST( to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS DECIMAL(20))-
            CAST( to_unixtime( from_iso8601_timestamp(streamsdata.connectedTimestamp) ) AS DECIMAL(20))
        AS INTEGER )
    END as AgentDeskPhone_Telco_inSeconds,

CASE  (streamsdata.type <> 'agent' AND streamsdata.contactid <> streamsdata.conn_id)
    WHEN true THEN 
        CASE (streamsdata.disconnectedTimestamp IS NOT NULL)
        WHEN true THEN
            CAST(
                CAST( to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS DECIMAL(20))-
                CAST( to_unixtime( from_iso8601_timestamp(streamsdata.connectedTimestamp) ) AS DECIMAL(20))
            AS INTEGER )
        ELSE
            CAST(
                CAST( to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS DECIMAL(20))-
                CAST( to_unixtime( from_iso8601_timestamp(ctrdata.TransferCompletedTimestamp) ) AS DECIMAL(20))
            AS INTEGER )
        END
    END AS Thirdparty_Telco_inSeconds,

CASE  (ctrdata.contactid = streamsdata.conn_id OR (streamsdata.conn_id IS NULL AND ctrdata.initialContactId IS NULL ))
    WHEN true THEN
        CAST(
            CAST( to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS DECIMAL(20))-
            CAST( to_unixtime( from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp) ) AS DECIMAL(20))
            AS INTEGER )
        END AS CustomerCallLength_Telco_inSeconds,

-- Calculate relevant usage amounts ROUNDED
-- If contact id == initial conn id then that conn is the telephony connection between customer and connect. And thus the Telephony usage estimate we calculate via the CTR. The rest of the connections, if endpoint is phone number then we calculate that usage in here. 
-- check here. (add the duration of the CTRs in the chain) 
-- service min
CASE  
    WHEN ((ctrdata.contactid = streamsdata.conn_id OR (streamsdata.conn_id IS NULL AND ctrdata.initialContactId IS NULL )) AND ctrdata.initiationmethod <> 'CALLBACK') THEN 
        CASE (CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.InitiationTimestamp)) as INTEGER) < 10)
        WHEN true THEN 10
           ELSE CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.InitiationTimestamp)) as INTEGER)
        END
    WHEN ((ctrdata.contactid = streamsdata.conn_id) AND ctrdata.initiationmethod = 'CALLBACK') THEN 
        CASE (CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp)) as INTEGER) < 10)
        WHEN true THEN 10
           ELSE CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp)) as INTEGER)
        END
END AS Connect_Service_Seconds_Rounded,

-- calculating agent deskphone conneciton time
-- this case is for the connection agent, if its agent conn and using deskphone then we count telco seconds

CASE (streamsdata.type = 'agent' AND streamsdata.softphoneEnabled = false)
    WHEN true THEN 
        CASE (CAST(to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(streamsdata.connectedTimestamp)) as INTEGER) < (60))            
        WHEN true THEN CAST(60 AS INTEGER)            
        ELSE CAST(
            CAST( to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS DECIMAL(20))-
            CAST( to_unixtime( from_iso8601_timestamp(streamsdata.connectedTimestamp) ) AS DECIMAL(20))
            AS INTEGER )
        END
END as AgentDeskPhone_Telco_inSeconds_Rounded,

-- case for when its a third party connection, but not the original customer conn, that one we will use CTR to calculate.
CASE  (streamsdata.type <> 'agent' AND streamsdata.contactid <> streamsdata.conn_id)
    WHEN true THEN 
        CASE (streamsdata.disconnectedTimestamp IS NOT NULL)
        WHEN true THEN
            CASE (CAST(to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(streamsdata.connectedTimestamp)) as INTEGER) < (60))            
            WHEN true THEN CAST(60 AS INTEGER)            
            ELSE CAST(
                CAST( to_unixtime(from_iso8601_timestamp(streamsdata.disconnectedTimestamp)) AS DECIMAL(20))-
                CAST( to_unixtime( from_iso8601_timestamp(streamsdata.connectedTimestamp) ) AS DECIMAL(20))
                AS INTEGER )
            END
        ELSE 
            CASE (CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.TransferCompletedTimestamp)) as INTEGER) < (60))            
            WHEN true THEN CAST(60 AS INTEGER)            
            ELSE CAST(
                CAST( to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS DECIMAL(20))-
                CAST( to_unixtime( from_iso8601_timestamp(ctrdata.TransferCompletedTimestamp) ) AS DECIMAL(20))
                AS INTEGER )
            END
        END
END AS Thirdparty_Telco_inSeconds_Rounded,

CASE  (ctrdata.contactid = streamsdata.conn_id OR (streamsdata.conn_id IS NULL AND ctrdata.initialContactId IS NULL ))
    WHEN true THEN
        CASE (CAST(to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS INTEGER)-CAST(to_unixtime(from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp)) as INTEGER) < (60))            
        WHEN true THEN CAST(60 AS INTEGER)            
        ELSE CAST(
            CAST( to_unixtime(from_iso8601_timestamp(ctrdata.DisconnectTimestamp)) AS DECIMAL(20))-
            CAST( to_unixtime( from_iso8601_timestamp(ctrdata.ConnectedToSystemTimestamp) ) AS DECIMAL(20))
            AS INTEGER )
        END
END AS CustomerCallLength_Telco_inSeconds_Rounded


FROM ctrdata
LEFT JOIN streamsdata
ON streamsdata.contactid = ctrdata.contactid
WHERE channel = 'VOICE'
ORDER BY CTR_Initiation_Timestamp DESC