import os
import json
import boto3
import requests
import urllib.request

def send_signal_to_cfn(event, context, status, reason=""):
    """Send SUCCESS or FAILED signal to CloudFormation"""
    wait_handle_url = event["ResourceProperties"]["WaitHandle"]
    data = json.dumps({
        "Status": status,
        "Reason": reason,
        "UniqueId": "TwilioWebhookSetup",
        "Data": "Twilio webhook setup complete"
    }).encode("utf-8")

    req = urllib.request.Request(wait_handle_url, data=data, method="PUT")
    req.add_header("Content-Type", "application/json")

    try:
        urllib.request.urlopen(req)
        print(f"CloudFormation signal sent: {status}")
    except Exception as e:
        print(f"Failed to send signal: {str(e)}")

def delete_twilio_webhook():
    """Deregister the webhook from Twilio when stack is deleted"""
    twilio_account_sid = os.environ["TWILIO_ACCOUNT_SID"]
    twilio_auth_token = os.environ["TWILIO_AUTH_TOKEN"]
    twilio_phone_number = os.environ["TWILIO_PHONE_NUMBER"]

    url = f"https://api.twilio.com/2010-04-01/Accounts/{twilio_account_sid}/IncomingPhoneNumbers.json"
    auth = (twilio_account_sid, twilio_auth_token)

    try:
        # Get phone number SID
        response = requests.get(url, auth=auth)
        response.raise_for_status()
        phone_numbers = response.json()["incoming_phone_numbers"]

        for number in phone_numbers:
            if number["phone_number"] == twilio_phone_number:
                phone_number_sid = number["sid"]
                delete_url = f"https://api.twilio.com/2010-04-01/Accounts/{twilio_account_sid}/IncomingPhoneNumbers/{phone_number_sid}.json"
                requests.delete(delete_url, auth=auth)
                return True
    except requests.exceptions.RequestException as e:
        print(f"Failed to delete Twilio webhook: {e}")
        return False

def lambda_handler(event, context):
    """Handle CREATE, UPDATE, and DELETE events from CloudFormation"""
    request_type = event.get("RequestType", "Create")

    if request_type == "Delete":
        if delete_twilio_webhook():
            send_signal_to_cfn(event, context, "SUCCESS", "Twilio webhook deleted successfully")
        else:
            send_signal_to_cfn(event, context, "FAILED", "Failed to delete Twilio webhook")
        return

    # If CREATE or UPDATE, continue with normal webhook registration
    try:
        webhook_url = event["ResourceProperties"]["WebSocketPublicIP"]
        twilio_sid = os.environ["TWILIO_ACCOUNT_SID"]
        twilio_token = os.environ["TWILIO_AUTH_TOKEN"]
        twilio_number = os.environ["TWILIO_PHONE_NUMBER"]

        response = requests.post(
            f"https://api.twilio.com/2010-04-01/Accounts/{twilio_sid}/IncomingPhoneNumbers.json",
            data={"PhoneNumber": twilio_number, "VoiceUrl": webhook_url, "VoiceMethod": "POST"},
            auth=(twilio_sid, twilio_token)
        )

        response.raise_for_status()
        send_signal_to_cfn(event, context, "SUCCESS")

    except requests.exceptions.RequestException as e:
        send_signal_to_cfn(event, context, "FAILED", str(e))
