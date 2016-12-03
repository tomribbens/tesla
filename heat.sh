#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

JQ=/usr/bin/jq

if [ ! -e $DIR/config.sh ]
then
	# Not configured, exiting
	echo "No configuration found";
	exit;
else
	source $DIR/config.sh;
fi

if [ ! -e $JQ ]
then
	echo "jq not found. Please install";
	exit;
fi


if [ ! -e $DIR/.token ]
then
	# No token exists, acquiring
	curl -s --data "grant_type=password&client_id=$TESLA_CLIENT_ID&client_secret=$TESLA_CLIENT_SECRET&email=$USER_ID&password=$PASSWORD" https://owner-api.teslamotors.com/oauth/token > $DIR/.token 
fi

if [ "$($JQ .access_token $DIR/.token)" == "null" ]
then
	echo "Unauthorized. Removing .token file. Please check credentials and try again";
	rm $DIR/.token
	exit 1;
elif [ $(($($JQ .created_at $DIR/.token) + $($JQ .expires_in $DIR/.token))) -lt "$(date +%s)" ]
then
	echo "Token expired";
	rm .token;
	exit 1;
fi

vehicles=$(curl -s -H "Authorization: Bearer $(jq -r .access_token $DIR/.token)" https://owner-api.teslamotors.com/api/1/vehicles)
if [ "$($JQ .count <<< "$vehicles")" -gt 1 ]
then
	echo "Multiple cars not supported at the moment";
	exit 1;
fi

vehicle_id=$($JQ -r '.response | .[].id_s' <<< "$vehicles")

battery_state=$(curl -s  --header "Authorization: Bearer $(jq -r .access_token $DIR/.token)"   https://owner-api.teslamotors.com/api/1/vehicles/$vehicle_id/data_request/charge_state | jq -r .response.battery_level)
if [ "$battery_state" == null ] || [ "$battery_state" -lt "$MIN_BATTERY" ]
then
	echo "Battery not full enough to start charging"
	exit 1
fi

result=$(curl -s --request POST  --header "Authorization: Bearer $(jq -r .access_token $DIR/.token)"   https://owner-api.teslamotors.com/api/1/vehicles/$vehicle_id/command/auto_conditioning_start)
if [ $($JQ .response.result <<< "$result") != "true" ]
then
	echo "API request failed"
	exit 1
fi

