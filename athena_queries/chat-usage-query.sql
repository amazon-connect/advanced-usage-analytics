select 
chatusage.instanceid,
ctr.queue.name,
ctr.ContactId,
ctr.channel,
ctr.InitiationTimestamp as CallInitiationTimestamp,
ctr.Agent.ConnectedToAgentTimestamp as ConnectedToAgentTimestamp,
ctr.DisconnectTimestamp as DisconnectTimestamp,
ctr.ConnectedToSystemTimestamp as ConnectedToSystemTimestamp,
chatusage.system_msg as ChatUsageSystemMsg,
chatusage.customer_msg as ChatUsageCustomerMsg,
chatusage.agent_msg as ChatUsageAgentMsg,
chatusage.total_msg as ChatUsageTotalMsg


FROM "amazonconnect_chat" chatusage 
LEFT JOIN "amazonconnect_ctr" ctr
ON ctr.ContactId = chatusage.contactid 
WHERE ctr.channel = 'CHAT'