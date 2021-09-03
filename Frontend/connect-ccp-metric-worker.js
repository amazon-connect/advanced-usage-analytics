var debug = false; //set debug to true to persist all submitted records locally in IndexDB
var apiGatewayEndpoint;
const postIntervalSeconds = 300; //change frequency in which worker sends completed contact records to API
const pendingRecordTimeoutSeconds = 86400; //time in seconds before considering any pending contact records stored in the IndexDB to be abandoned and sent to the API
const dbName = 'contactsIDB'; //indexedDB name for local durable storage

//Instantiate variables for worker
var busy = 0;
var completeObjectStoreLength = 0;


    
//Open IndexedDB
let db;
let req = indexedDB.open(dbName, 1);
req.onupgradeneeded = function(e) {
  let db = e.target.result;
  var pendingObjectStore = db.createObjectStore("contactsPending", { keyPath: "contactId" });
  var completeObjectStore = db.createObjectStore("contactsComplete", { keyPath: "contactId" });
  if (debug) {
    var sentObjectStore = db.createObjectStore("contactsSubmitting", { autoIncrement: true });
  }
  self.postMessage("Successfully upgraded db");
};

req.onsuccess = function(e) {
  //On success, initialize the database for processing records
  db = req.result;
  self.postMessage("Successfully opened db");
  var completeCountRequest = db.transaction(["contactsComplete"]).objectStore("contactsComplete").count();
  var currentContactsCompleteRequest = db.transaction(["contactsComplete"]).objectStore("contactsComplete").getAll();
  var currentContactsPendingRequest = db.transaction(["contactsPending"]).objectStore("contactsPending").getAll();
  busy++;
  
  completeCountRequest.onsuccess = function () {
    completeObjectStoreLength = completeCountRequest.result; //Store the count of currently completed contacts pending submission to the API
    busy--;
  };
  busy++;
  
  currentContactsCompleteRequest.onsuccess = function () {
    postMessage({type: 'initializedPendingContact', contacts: currentContactsCompleteRequest.result}); //Any contacts that are not ready to be submitted to the API and are potentially in progress (i.e., due to browser refresh are loaded back into page memory to have additional data appended)
    busy--;
  };
  busy++;

  currentContactsPendingRequest.onsuccess = function () {
      currentContactsPendingRequest.result.forEach( (contact) => {
        if (Date.parse(contact['initialTimestamp']) < Date.now()-(pendingRecordTimeoutSeconds*1000)) {
          storeContactTraceStream(contact); 
        } else {
          postMessage({type: 'initializedPendingContact', contacts: [contact]});
        }
      });
    busy--;
  };
  completeCountRequest.onerror = function () {
    postMessage('completeCountRequest error'); 
    busy--;
  };
  currentContactsCompleteRequest.onerror = function () {
    postMessage('currentContactsCompleteRequest error'); 
    busy--;
  };
  currentContactsPendingRequest.onerror = function () {
    postMessage('currentContactsPendingRequest error'); 
    busy--;
  };
};

req.onerror = function(e) {
  self.postMessage("Db open error: " + JSON.stringify(e.target.errorCode));
};

function storeContactTraceStream(record, eventtype) {
  let transaction = db.transaction(["contactsPending", "contactsComplete"], "readwrite");
  busy++;

  transaction.oncomplete = function(event) {
    postMessage({type: 'contactStored', contact: {contactId: record.contactId}});
    busy--;
  };

  transaction.onerror = function(event) {
    console.log('Error storing ' + record);
    busy--;
  };

  let completeObjectStore = transaction.objectStore("contactsComplete");
  let pendingObjectStore = transaction.objectStore("contactsPending");

  if ((record['stageEnded'] && eventtype == 'Destroyed') || record['stageError'] || Date.parse(record['initialTimestamp']) < Date.now()-(pendingRecordTimeoutSeconds*1000)) {
    //If record has errored, ended, or has been pending for more than 24 hours, mark as complete
    var request = completeObjectStore.put(record);
    request.onsuccess = function(event) {
      // console.log("inserted " + JSON.stringify(record) + " to completeObjectStore");
      pendingObjectStore.delete(record.contactId);  // Remove record from pending object store.
    };
    var completeCountRequest = completeObjectStore.count();

    completeCountRequest.onsuccess = function () {
      completeObjectStoreLength = completeCountRequest.result;
    };
  } else {
    var request = pendingObjectStore.put(record);
    request.onsuccess = function(event) {
      // console.log("inserted " + JSON.stringify(record) + " to pendingObjectStore");
    }
  }
};

//Function to submit logs to the API
var submitLogs = function() {
  console.log("Submitting logs to metrics API: "+ Date.now());
  if(busy < 1 && completeObjectStoreLength > 0 && apiGatewayEndpoint) {
    //Get all data from IDB and format for API Gateway
    if (debug) {
      var transaction = db.transaction(["contactsPending", "contactsComplete", "contactsSubmitting"], "readwrite");
    } else {
      var transaction = db.transaction(["contactsPending", "contactsComplete"], "readwrite");
    }
    var data = {};

    busy++;
    transaction.oncomplete = function(event) {
      var completeCountRequest = db.transaction(["contactsComplete"]).objectStore("contactsComplete").count();
      busy++
      completeCountRequest.onsuccess = function () {
        completeObjectStoreLength = completeCountRequest.result;
        busy--;
      };
      busy--;
      //Create xhr to send data to AWS
    }
    transaction.onerror = function(event) {
      //Handle for errors
      console.log('error with transaction')
      var completeCountRequest = db.transaction(["contactsComplete"]).objectStore("contactsComplete").count();
      busy++
      completeCountRequest.onsuccess = function () {
        completeObjectStoreLength = completeCountRequest.result;
        busy--;
      };
      busy--;
    }
    var completeObjectStore = transaction.objectStore("contactsComplete");
    if (debug) var sentObjectStore = transaction.objectStore("contactsSubmitting");
    var getAll = completeObjectStore.getAll();
    getAll.onsuccess = function () {
      if (debug) {
        var saveSubmissionData = sentObjectStore.add({requestPayload: getAll.result})
        saveSubmissionData.onsuccess = function () {
          //Save ID of request IDB record in case of reversion upon API call failure.
          console.log("requestPayloadId: " + saveSubmissionData.result);
          var requestPayloadId = saveSubmissionData.result;
          completeObjectStore.clear();
          var saveResult = saveSubmissionData.result;
          data = getAll.result;
          console.log("Data for submission");
          console.log(getAll.result);

          //Make post request
          var xhr = new XMLHttpRequest();
          xhr.open("POST", apiGatewayEndpoint);
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.send(JSON.stringify({DeliveryStreamName:"CallConnectionFirehose", Record: {Data: btoa(JSON.stringify(data).slice(1,-1)+'\n')}}));
          xhr.requestId = requestPayloadId;
          xhr.onreadystatechange = function() {
              postMessage(xhr.responseText);
              if (xhr.status = 200) {
                // If successful, remove from browser memory
                postMessage({type: 'contactSubmitted', contacts: data.map(a => a.contactId)});
                console.log('xhr success: ');
                console.log(xhr.requestId);
              } else {
                console.log('xhr failure: ');
                console.log(xhr.requestId);
                transaction.abort();
              }
              
          };
          xhr.onerror = function () {
            console.log('xhr error: ');
            console.log(xhr.requestId);
          };

        }
      } else {
        completeObjectStore.clear();
        data = getAll.result;
        console.log("Data for submission");
        console.log(getAll.result);

        //Make post request
        var xhr = new XMLHttpRequest();
        xhr.open("POST", apiGatewayEndpoint);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.send(JSON.stringify({DeliveryStreamName:"CallConnectionFirehose", Record: {Data: btoa(JSON.stringify(data).slice(1,-1)+'\n')}}));
        xhr.onreadystatechange = function() {
            postMessage(xhr.responseText);
            if (xhr.status = 200) {
              postMessage({type: 'contactSubmitted', contacts: data.map(a => a.contactId)});
              console.log('xhr success, request id:' + xhr.requestId);
            } else {
              console.log('xhr failure, request id:' + xhr.requestId);
              transaction.abort();
            }
            
        };
        xhr.onerror = function () {
          transaction.abort();
        };
      }
    }
  } else if (!apiGatewayEndpoint) {
    console.log('API Endpoint is not set.');
  }
}

//Submit logs to API based on the postIntervalSeconds variable
self.setInterval(function(){
  submitLogs()
}, postIntervalSeconds*1000);

self.onmessage = function(e) {
  // console.log("worker received event");
  // console.log(e.data);
  if (e.data.type == 'putContact' && e.data.contact.contactId) {
   storeContactTraceStream(e.data.contact, e.data.event);
  }
  if (e.data.type == 'updateApiEndpoint' && e.data.apiUrl) {
    apiGatewayEndpoint = e.data.apiUrl;
    console.log('Api endpoint set: ' + e.data.apiUrl);
  }
  

}