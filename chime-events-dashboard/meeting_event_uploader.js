const AWS = require('aws-sdk');
const cloudWatch = new AWS.CloudWatch({ apiVersion: '2010-08-01' });
const cloudWatchLogs = new AWS.CloudWatchLogs({ apiVersion: '2014-03-28' });

exports.handler = async function (event) {
    let meetingEvents, meetingId, attendeeId;

    try {
        meetingEvents = JSON.parse(event.body);

        if (!Array.isArray(meetingEvents)) {
        throw new Error('The POST body does not contain a JSON array of meeting events');
        }

        if (!meetingEvents.length) {
        return createReponse(200);
        }

        meetingId = meetingEvents[0].attributes.meetingId;
        attendeeId = meetingEvents[0].attributes.attendeeId;
        
        if (!meetingId || !attendeeId) {
        throw new Error('The POST body does not have a valid meeting ID and attendee ID');
        }
    } catch (error) {
        console.error(error);
        return createReponse(422, {
        error: 'Invalid input: Ensure that you pass a JSON array of meeting events'
        });
    }

    try {
        await Promise.all([
        publishLogEvents(meetingId, attendeeId, meetingEvents),
        publishMetricData(meetingEvents)
        ]);
    } catch (error) {
        console.error(error);
        return createReponse(500, {
        error: 'Internal server error'
        });
    }

    return createReponse(200);
}

async function publishLogEvents(meetingId, attendeeId, meetingEvents) {
    const logGroupName = process.env.LOG_GROUP_NAME;
    const logStreamName = `/meeting-events/${meetingId}/${attendeeId}/${Date.now()}`;

    await cloudWatchLogs.createLogStream({
        logGroupName,
        logStreamName
    }).promise();

    await cloudWatchLogs.putLogEvents({
        logEvents: meetingEvents.map(meetingEvent => ({
        message: JSON.stringify(meetingEvent),
        timestamp: meetingEvent.attributes.timestampMs
        })),
        logGroupName,
        logStreamName
    }).promise();
}

async function publishMetricData(meetingEvents) {
    const metricData = meetingEvents
        .filter(({ name, attributes }) => (
        name === 'meetingStartSucceeded' &&
        attributes.meetingStartDurationMs > 0
        ))
        .map(({ name, attributes }) => {
        return {
            MetricName: 'meetingStartDurationMs',
            Timestamp: new Date(attributes.timestampMs).toISOString(),
            Unit: 'Milliseconds',
            Value: attributes.meetingStartDurationMs,
            Dimensions: [
            {
                Name: 'sdkName',
                Value: attributes.sdkName
            }
            ]
        };
        });
    if (!metricData.length) {
        return;
    }

    await cloudWatch.putMetricData({
        Namespace: process.env.MEETING_EVENT_METRIC_NAMESPACE,
        MetricData: metricData
    }).promise();
}

// In a production environment, we recommend restricting access to your API using Lambda authorizers,
// Amazon Cognito user pools, or other mechanisms. For more information, see the "Controlling and
// managing access to a REST API in API Gateway" guide:
// https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-to-api.html
function createReponse(statusCode, body = {}) {
    return {
        statusCode,
        body: JSON.stringify(body),
        headers: {
        'Access-Control-Allow-Origin': process.env.ACCESS_CONTROL_ALLOW_ORIGIN,
        'Access-Control-Allow-Methods': 'OPTIONS,POST',
        'Content-Type': 'application/json'
        }
    };
}