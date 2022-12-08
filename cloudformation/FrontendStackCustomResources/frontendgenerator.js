// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

const s3 = new (require('aws-sdk')).S3();
const response = require('cfn-response');
const streamsHtmlKey = 'index.html';
const sourceBucket = 'aws-contact-center-blog';
const sourcePrefix = 'usage-analytics';
const sourceObjectArray = ['connect-ccp-metric-worker.js','connect-streams-min.js','main.js','libphonenumber-js.min.js'];
exports.handler = async (event, context) => {
    let HtmlFile = [
        '<!DOCTYPE html>',
        '<meta charset="UTF-8">',
        '<html>',
        '  <head>',
        '    <script type="text/javascript" src="connect-streams-min.js"></script>',
        '    <script type="text/javascript" src="libphonenumber-js.min.js"></script>',
        '  </head>',
        '  <body>',
        '    <div id=containerDiv style="width: 400px;height: 800px;"></div>',
        '  </body>'
    ];
    var result = {responseStatus: 'FAILED', responseData: {Data: 'Never updated'}};
    try {
        console.log(`Received event with type ${event.RequestType}`);
        await checkPreconditions(event, context);   
        if(event.RequestType === 'Create' || event.RequestType === 'Update') {
            var lineToWrite = `<script src='main.js' apiGatewayUrl='${event.ResourceProperties.ApiGatewayUrl}' region='${event.ResourceProperties.Region}' ccpDomElement='containerDiv' ccpUrl='${event.ResourceProperties.CcpUrl}'></script>`
            HtmlFile.push(lineToWrite, '</html>');
            s3Result = await s3.upload({
                Key: streamsHtmlKey,
                Bucket: event.ResourceProperties.WebHostingS3Bucket,
                Body: HtmlFile.join("\n"),
                ContentType: 'text/html'
            }).promise();
            console.log(`Finished uploading HTML with result ${JSON.stringify(s3Result, 0, 4)}`);

            copyResult = await Promise.all(
                sourceObjectArray.map( async (object) => {
                    s3Result = await s3.copyObject({
                        Bucket: event.ResourceProperties.WebHostingS3Bucket,
                        Key: object,
                        CopySource: `${sourceBucket}/${sourcePrefix}/${object}`
                    }).promise();
                    console.log(`Finished uploading File with result ${JSON.stringify(s3Result, 0, 4)}`);
                }),
            );
            
            result.responseStatus = 'SUCCESS';
            result.responseData['Data'] = 'Successfully uploaded files';
        } else if (event.RequestType === 'Delete') {
            var s3Result = await s3.deleteObjects({
                Delete: {
                    Objects:[
                        {
                            Key: 'index.html'
                        }
                    ],
                    Quiet: false
                },
                Bucket: event.ResourceProperties.WebHostingS3Bucket
            }).promise();
            console.log(`Deletion result: ${s3Result}`)
            result.responseStatus = 'SUCCESS',
            result.responseData['Data'] = 'Successfully deleted files';
        }
    } catch (error) {
        console.log(JSON.stringify(error, 0, 4));
        result.responseStatus = 'FAILED';
        result.responseData['Data'] = 'Failed to process event';
    } finally {
        return await responsePromise(event, context, result.responseStatus, result.responseData, `StreamsAPIWebpage`);
    }
};

function responsePromise(event, context, responseStatus, responseData, physicalResourceId) {
    return new Promise(() => response.send(event, context, responseStatus, responseData, physicalResourceId));
}

function checkPreconditions(event) {
    return new Promise( function (resolve, reject) {
        if( (event.ResourceProperties.ApiGatewayUrl && 
        event.ResourceProperties.WebHostingS3Bucket  &&
        event.ResourceProperties.CcpUrl  &&
        event.ResourceProperties.Region )){
            resolve(true);
        } else {
            console.log(`Missing properties on event. ${JSON.stringify(event, 0, 4)}`)
            reject(false);
        }
    });
}