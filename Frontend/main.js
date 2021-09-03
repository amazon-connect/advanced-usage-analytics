// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

var instanceURL = document.currentScript.getAttribute('ccpUrl');
var region = document.currentScript.getAttribute('region');
var apiUrl = document.currentScript.getAttribute('apiGatewayUrl');
var ccpDomElement = document.currentScript.getAttribute('ccpDomElement'); //the ID of the DOM element where the CCP will be appended
var samlUrl = document.currentScript.getAttribute('samlUrl');
var ccpParams = {
    ccpUrl: instanceURL,            // REQUIRED
    region: region,
    softphone: {                    // optional
        allowFramedSoftphone: true   // optional
    }
};
// If the instance is a SAML instance, loginUrl must be set to pop the login
if (samlUrl && samlUrl !== 'undefined' && samlUrl !== ''){
  ccpParams.loginUrl = samlUrl;
  console.log('Added SAML login URL');
}

var contacts = {}; //create variable to append new data from streams.js refresh hooks
var currentAgent; //current Agent data is logged against contact data
// var currentContact; // global variable created for in-browser debugging

String.prototype.toProperCase = function () {
    return this.replace(/\w\S*/g, function(txt){return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();});
};

if (window.Worker) {
    //Create worker to handle durable storage and submission of records to the API
    var bufferWorker = new Worker('connect-ccp-metric-worker.js');
    bufferWorker.postMessage({type: 'updateApiEndpoint', apiUrl: apiUrl});        
    bufferWorker.addEventListener('message', (event) => {
        console.log(`Received message from worker: ${JSON.stringify(event.data)}`)
        if (event.data.type == 'contactSubmitted') {
            //Clear browser memory when worker durably stores data
            event.data.contacts.forEach(contactId => delete contacts[contactId]);
        } else if (event.data.type == 'initializedPendingContact') {
            //Add unsubmitted locally stored contact records to memory
            event.data.contacts.forEach(contact => contacts[contact.contactId] = contact);
        }
    });
} else {
    //...handle for cases where browser doesn't support web workers
    console.log(`Browser does not support workers! Logging contact details will not work.`)
}

async function saveConnectionState(connection, agent, arr) {
    //This function appends the current connection status to object specified
    let connectionIndex = arr.findIndex(con => con.id === connection.connectionId);
    let tempConnection = arr[connectionIndex] || {};
    tempConnection['history'] = tempConnection['history'] || [];
    //log current status from streams.js library
    let connectionState = connection.getState();
    let isActive = connection.isActive();
    let endpoint = connection.getAddress();
    let type = connection.getType();
    let id = connection.connectionId;
    let endpointCountryIso;
    result = await Promise.all([connectionState, isActive, endpoint, type]);

    //log all status changes
    tempConnection['history'].push({
        'status': connectionState['type'],
        'timestamp': connectionState['timestamp'],
        'active': isActive
    });

    //log the first time connection reaches connecting, connected, disconnected states
    if (!tempConnection['connectingTimestamp'] && connectionState['type'] == 'connecting') tempConnection['connectingTimestamp'] = connectionState['timestamp'];
    if (!tempConnection['connectedTimestamp'] && connectionState['type'] == 'connected') tempConnection['connectedTimestamp'] = connectionState['timestamp'];
    if (!tempConnection['disconnectedTimestamp'] && connectionState['type'] == 'disconnected') tempConnection['disconnectedTimestamp'] = connectionState['timestamp'];
    
    tempConnection['type'] = type;
    tempConnection['active'] = isActive;
    tempConnection['lastUpdate'] = connectionState['timestamp'];
    tempConnection['status'] = connectionState['type'];
    tempConnection['endpoint'] = endpoint;
    tempConnection['id'] = id;
    if (agent) tempConnection['agentStatus'] = agent.getConfiguration();
    //Get connection country ISO code
    try { 
        if (type=='agent') {
             endpointCountryIso = window.libphonenumber.parsePhoneNumber(tempConnection.agentStatus.extension).country;  
             tempConnection.endpoint.phoneNumber = tempConnection.agentStatus.extension;
        }
        else {
             endpointCountryIso = window.libphonenumber.parsePhoneNumber(endpoint.phoneNumber).country; 
        }
        tempConnection['endpointCountryISO'] = endpointCountryIso;
    } catch (err) {
        console.log(err);
    }
    connectionIndex = arr.findIndex(con => con.id === connection.connectionId);
    if (connectionIndex >= 0) {
        arr[connectionIndex] = tempConnection;
    } else {
        arr.push(tempConnection);
    }
    return true;
}

function createContactTraceStream(contact, newcontact, agent){
    //Updates the contact passed to the stream
    //Log all 'contact-stage' attributes
    //Logs only the first time a given attribute or state is provided
    try {
        if (!contact.type) {
            contact.type = newcontact.getType();
        }
        
        if (!contact.inbound) contact.inbound = newcontact.isInbound();
        if (!contact.initialConnectionId) contact.initialConnectionId = newcontact.getInitialConnection().connectionId;
        contact.connections = contact.connections || [];

        for (let item of newcontact.getConnections()) {
            saveConnectionState(item, agent, contact.connections);
        }
        // newcontact.getConnections().forEach(async function(item, i) {
        //     saveConnectionState(item, agent, contact.connections);
        // });

        //Log the attributes of by contact state (i.e., connected, pending, etc.)
        let status = newcontact.getStatus();
        if (!contact.initialTimestamp) newcontact.initialTimestamp = status.timestamp;
        //Take a snapshot of each Contact Status once, the first time the status is reached.
        if (status.type && !contact['stage'+status.type.toProperCase()]) {
            contact['stage'+status.type.toProperCase()] = {};
            contact['stage'+status.type.toProperCase()]['type'] = status.type;
            //set all status attributes if object is null
            for (i=0; Object.keys(status).length > i; i++) {
            if (!contact['stage'+status.type.toProperCase()][Object.keys(status)[i]]) {
                contact['stage'+status.type.toProperCase()][Object.keys(status)[i]] = status[Object.keys(status)[i]];
            }
            }
            //other function calls here
            contact['stage'+status.type.toProperCase()].attributes = newcontact.getAttributes();
            contact['stage'+status.type.toProperCase()].queue = newcontact.getQueue();
            contact['stage'+status.type.toProperCase()].thirdPartyConnections = newcontact.getThirdPartyConnections();
        }
        return contact;
    } catch (err) {
        console.log(err);
    }  
}

async function storeContactTraceStream(contact, agent, eventtype) {
    console.log('Received Event - Contact: ' + JSON.stringify(contact) + ' Agent: ' + JSON.stringify(agent) + ' Event Type: ' + eventtype);
    if (contact) {
        //update contact
        if (contacts[contact.contactId] && eventtype != 'Destroyed' && eventtype != 'Ended') { 
            console.log('>>> Updating existing contact');
            contacts[contact.contactId] = await createContactTraceStream(contacts[contact.contactId], contact, agent);
        } else if (eventtype != 'Destroyed' && eventtype != 'Ended') {
            console.log('>>> Creating new contact');
            contacts[contact.contactId] = await createContactTraceStream(contact, contact, agent);
        }
        bufferWorker.postMessage({type: 'putContact', contact: contacts[contact.contactId], event: eventtype});
    }
}

function init() {
//Instantiate the CCP in the custom page if not already initated
    if (!window.connect.core.initialized) {
        connect.core.initCCP(document.getElementById(ccpDomElement), ccpParams);
    }
    connect.agent(function(agent) {
    //here we subscribe to agent updates
        console.log('Agent Configuration on Page load');
        console.log(agent.getConfiguration());
        currentAgent = agent;
        //keep agent status up to date
        agent.onRefresh(function(agent) {
            currentAgent = agent;
        });
    });

    connect.contact(function(contact) {
    //This function subscribes to contact actions to store the contact trace details
        //currentContact = contact; //set the latest contact global variable for debugging purposes

        contact.onRefresh(function(contact){
            storeContactTraceStream(contact, currentAgent, 'Refresh');
        });

        //function to be invoked on incoming call
        contact.onIncoming(function(contact) { 
            storeContactTraceStream(contact, currentAgent, 'Incoming');
        });

        //function to be invoked on pending call
        contact.onPending(function(contact) { 
            storeContactTraceStream(contact, currentAgent, 'Pending');
        });

        //function to be invoked on connecting call
        contact.onConnecting(function(contact) { 
            storeContactTraceStream(contact, currentAgent, 'Connecting');
        });

        //function to be invoked on accepted contact
        contact.onAccepted(function(contact){
            storeContactTraceStream(contact, currentAgent, 'Accepted');      
        });

        //function to be invoked on missed contact
        contact.onMissed(function(contact){
            storeContactTraceStream(contact, currentAgent, 'Missed');
        });

        //function to be invoked on connected contact
        contact.onConnected(function(contact){
            storeContactTraceStream(contact, currentAgent, 'Connected');
        });

        //function to be invoked on after contact work state
        contact.onACW(function(contact) {
            storeContactTraceStream(contact, currentAgent, 'ACW');
        });

        //function to be invoked on contact ended
        contact.onEnded(function(contact) {
            storeContactTraceStream(contact, currentAgent, 'Ended');
        });

        //function to be invoked on contact destroy
         contact.onDestroy(function(contact) {
            storeContactTraceStream(contact, currentAgent, 'Destroyed');
         });

    });
}

init();