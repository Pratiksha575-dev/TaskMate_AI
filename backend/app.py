import requests
import json
import os
from flask import Flask, request, jsonify
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta
import pytz
import random
from flask_cors import CORS
from dateutil import parser
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
import uuid
from google.cloud.firestore_v1 import FieldFilter

app = Flask(__name__)
CORS(app)

def check_and_send_reminders():
    now = datetime.utcnow()
    print(f"🔍 Checking reminders at {now}")

    # First: Check EVENTS
    events_ref = db.collection('events')
    upcoming_events = events_ref \
    .where('reminderTime', '<=', now) \
    .where('reminderSent', '==', False) \
    .stream()

    for event in upcoming_events:
        data = event.to_dict()
        token = data.get('token')
        title = "⏰ Reminder: " + data.get('title', 'No Title')
        body = "Your event is starting soon!"

        if token:
            send_fcm_notification(token, title, body)
            print(f"✅ Reminder sent for event: {data.get('title')}")
            event.reference.update({'reminderSent': True})
        else:
            print("⚠ No FCM token available for event reminder")


    # Second: Check TASKS (all 4 collections)
    task_collections = ["tasks_self", "tasks_team", "tasks_family", "tasks_self_work"]

    for collection_name in task_collections:
        tasks_ref = db.collection(collection_name)
        upcoming_tasks = tasks_ref \
        .where('reminderTime', '<=', now) \
        .where('reminderSent', '==', False) \
        .stream()\


        for task in upcoming_tasks:
            data = task.to_dict()
            token = data.get('token')
            title = "📝 Task Reminder: " + data.get('title', 'No Title')
            body = "Don't forget your task: " + data.get('title', 'No Title')

            if token:
                send_fcm_notification(token, title, body)
                print(f"✅ Reminder sent for task: {data.get('title')} from {collection_name}")
                task.reference.update({'reminderSent': True})
            else:
                print(f"⚠ No FCM token available for task reminder in {collection_name}")

scheduler = BackgroundScheduler()
scheduler.add_job(func=check_and_send_reminders, trigger="interval", seconds=60)
scheduler.start()


# 🔹 Initialize Firebase
if "GOOGLE_APPLICATION_CREDENTIALS_JSON" in os.environ:
    cred_info = json.loads(os.environ["GOOGLE_APPLICATION_CREDENTIALS_JSON"])
    cred = credentials.Certificate(cred_info)
else:
    cred = credentials.Certificate("dialogflow-key.json")  # fallback for local testing

firebase_admin.initialize_app(cred)
db = firestore.client()

# 🌍 Calendarific API Key (For Major Festivals)
CALENDARIFIC_API_KEY = os.environ.get("CALENDARIFIC_API_KEY")
ASTROLOGY_API_KEY = os.environ.get("ASTROLOGY_API_KEY")

# 🌍 Calendarific API URL
CALENDARIFIC_URL = "https://calendarific.com/api/v2/holidays"

# 🕉 Free Astrology API URL (For Tithi)
ASTROLOGY_URL = "https://json.freeastrologyapi.com/tithi-durations"


@app.route('/')
def home():
    return 'Server is alive!'

@app.route('/schedule_notification', methods=['POST'])
def handle_schedule_notification():
    print('🚀 Received POST /schedule_notification')
    data = request.get_json()
    print(f"📥 Received data: {data}")

    try:
        token = data['token']
        title = data['title']
        body = data['body']
        send_time = parser.isoparse(data['send_time'])

        print(f"📅 Scheduling notification with: token={token}, title={title}, body={body}, send_time={send_time}")

        schedule_notification(token, title, body, send_time)

        print('✅ Notification scheduled successfully.')
        return jsonify({"status": "Scheduled", "send_time": send_time.isoformat()})

    except Exception as e:
        print(f"❌ Error in schedule_notification: {e}")
        return jsonify({"error": str(e)}), 400


# ✅ Function to Fetch Festivals from Both APIs
def get_festivals(date):
    """Fetches holidays for a given date from Calendarific & Free Astrology API."""
    
    if isinstance(date, int):  # ✅ Ensure date is a string
        date = str(date)

    year = date[:4]  # Extract year
    month = date[5:7]  # Extract month
    day = date[8:10]  # Extract day

    holidays = []

    # 🔹 Fetch from Calendarific API
    try:
        calendarific_response = requests.get(f"{CALENDARIFIC_URL}?api_key={CALENDARIFIC_API_KEY}&country=IN&year={year}")
        data = calendarific_response.json()
        print("📢 Calendarific API Response:", json.dumps(data, indent=2))

        if "response" in data and "holidays" in data["response"]:
            holidays += [h['name'] for h in data["response"]["holidays"] if h['date']['iso'] == date]
    except Exception as e:
        print(f"⚠ Error fetching Calendarific holidays: {e}")

    # 🔹 Fetch from Free Astrology API (For Hindu Tithi-based events)
    try:
        headers = {
            "Content-Type": "application/json",
            "x-api-key": ASTROLOGY_API_KEY  # ✅ Free Astrology API Key
        }
        payload = {
            "year": int(year),
            "month": int(month),
            "date": int(day),
            "hours": 12,
            "minutes": 0,
            "seconds": 0,
            "latitude": 19.0760,  # Example: Mumbai
            "longitude": 72.8777,  # Example: Mumbai
            "timezone": 5.5,  # IST
            "config": {
                "observation_point": "topocentric",
                "ayanamsha": "lahiri"
            }
        }
        response = requests.post(ASTROLOGY_URL, headers=headers, json=payload)
        data = response.json()

        print("📢 Free Astrology API Raw Response:", json.dumps(data, indent=2))  # ✅ Debugging

        # ✅ Ensure 'output' exists and is a string
        if "output" in data and isinstance(data["output"], str):
            output_json = json.loads(data["output"])  # ✅ Convert string to JSON

            print("📌 Parsed Output:", json.dumps(output_json, indent=2))  # ✅ Debugging

            tithi_name = output_json.get("name", "Unknown Tithi")  # Extract Tithi name

            if tithi_name != "Unknown Tithi":  # ✅ Only add valid Tithis
                holidays.append(tithi_name)

        else:
            print("⚠ Unexpected Free Astrology API response format!")

    except Exception as e:
        print(f"⚠ Error fetching Free Astrology API data: {e}")

    return holidays  # ✅ Returning a list


# ✅ API Endpoint to Fetch Holidays for a Given Date
@app.route('/holidays', methods=['GET'])
def get_holidays():
    """Returns holidays for the selected date from both APIs."""
    selected_date = request.args.get("date", datetime.today().strftime('%Y-%m-%d'))  # Default to today
    holidays = get_festivals(selected_date)  # ✅ Fetch festivals for the correct date
    return jsonify({"date": selected_date, "holidays": holidays})  # ✅ Fixed .get() issue


# ✅ Webhook for Dialogflow Integration
@app.route('/webhook', methods=['POST'])
def webhook():
    req = request.get_json()
    print("📥 Received full request:",req)  # Debugging

    user_id = req.get("originalDetectIntentRequest", {}).get("payload", {}).get("userId", None)
    print(f"Received user ID: {user_id}")


    # Extract intent name
    intent = req.get("queryResult", {}).get("intent", {}).get("displayName", "")
    parameters = req.get("queryResult", {}).get("parameters", {})
    print(f"🧪 Duration parameter: {parameters.get('duration')}")
    print(f"🧪 Date-time parameter: {parameters.get('date-time')}")  # Debugging
    print(f"👁 Full parameters received: {parameters}")



    print(f"✅ Detected intent: {intent}")
    print(f"🔍 Extracted parameters: {parameters}")

    # 🔹 Handle Default Welcome Intent first
    if intent == "Default Welcome Intent":
        messages = req.get("queryResult", {}).get("fulfillmentMessages", [])

        if messages:
            responses = [msg["text"]["text"][0] for msg in messages if "text" in msg and "text" in msg["text"]]
            return jsonify({"fulfillmentText": " ".join(responses)})
        else:
            return jsonify({"fulfillmentText": "Hello! Welcome to my service! How can I assist you today?"})

    # 🔹 Check Events Intent
    elif intent == "check_events":
        print("📅 Handling check_events with date-time")
        response = fetch_events(parameters)
        return jsonify({"fulfillmentText": response})

    elif intent == "check_events_by_time":
        print("🕒 Handling check_events_by_time with duration")
        response = fetch_events_by_time(parameters)
        return jsonify({"fulfillmentText": response})

    # 🔹 Get Tasks Intent
    elif intent == "get_tasks":
        print("📅 Fetching tasks...")
        response = get_tasks(parameters)
        return jsonify({"fulfillmentText": response})

   
    # 🔹 Get Tasks by Time
    elif intent == "get_tasks_by_time":
        print("📅 Checking tasks due in the specified time range...")
        response = get_tasks_by_time(parameters)
        return jsonify({"fulfillmentText": response})

    # 🔹 Get Holidays Intent
    elif intent == "get_holidays":
        print("🎉 Fetching holiday data...")
        selected_date = datetime.today().strftime('%Y-%m-%d')
        holidays = get_festivals(selected_date)
        return jsonify({"fulfillmentText": f"Today's holidays: {', '.join(holidays) if holidays else 'No holidays today.'}"})

    elif intent == "mundane_intent":
        print("🧘 Mundane/acknowledgment intent detected.")
        response = handle_acknowledgment_response(parameters)
        return jsonify({"fulfillmentText": response})

    # 🔹 Handle Default Fallback Intent
    elif intent == "Default Fallback Intent":
        messages = req.get("queryResult", {}).get("fulfillmentMessages", [])

        if messages:
            responses = [msg["text"]["text"][0] for msg in messages if "text" in msg and "text" in msg["text"]]
            return jsonify({"fulfillmentText": " ".join(responses)})
        else:
            return jsonify({"fulfillmentText": "Sorry, I didn't understand that. Can you rephrase?"})

    # 🔹 Unrecognized Intent (Final Catch-All)
    print("⚠ Intent not recognized.")
    return jsonify({"fulfillmentText": "I'm not sure how to help with that. Can you try rephrasing?"})

def fetch_events(parameters):
    """Handles specific date or time range queries — supports both full-day and time-specific requests."""
    user_id = request.json.get('originalDetectIntentRequest', {}).get('payload', {}).get('userId')  # 👈 ADD THIS
    ist = pytz.timezone("Asia/Kolkata")
    is_range = False
    user_start_ist_str = ""
    user_end_ist_str = ""

    try:
        dt_range = parameters.get("date-time")

        # Normalize structure (list or dict)
        if isinstance(dt_range, list) and len(dt_range) > 0:
            dt_range = dt_range[0]

        if isinstance(dt_range, dict) and "startTime" in dt_range and "endTime" in dt_range:
            # Time range provided by user
            start_time = parser.isoparse(dt_range["startTime"]).astimezone(pytz.utc)
            end_time = parser.isoparse(dt_range["endTime"]).astimezone(pytz.utc)
            is_range = True

            user_start_ist_str = parser.isoparse(dt_range["startTime"]).astimezone(ist).strftime('%I:%M %p')
            user_end_ist_str = parser.isoparse(dt_range["endTime"]).astimezone(ist).strftime('%I:%M %p')

            print(f"⏰ Time range: {start_time} to {end_time}")

        elif isinstance(dt_range, dict) and "startDate" in dt_range and "endDate" in dt_range:
            # Date range provided by user (like "next weekend")
            start_time = parser.isoparse(dt_range["startDate"]).astimezone(pytz.utc)
            end_time = parser.isoparse(dt_range["endDate"]).astimezone(pytz.utc)
            is_range = True

            user_start_ist_str = parser.isoparse(dt_range["startDate"]).astimezone(ist).strftime('%d %b %Y')
            user_end_ist_str = parser.isoparse(dt_range["endDate"]).astimezone(ist).strftime('%d %b %Y')

            print(f"📅 Date range: {start_time} to {end_time}")

        elif isinstance(dt_range, str):
            # Single date without range
            selected_date = parser.parse(dt_range).date()
            start_time = datetime.combine(selected_date, datetime.min.time()).replace(tzinfo=pytz.utc)
            end_time = datetime.combine(selected_date, datetime.max.time()).replace(tzinfo=pytz.utc)
            print(f"📅 Single date query: {start_time} to {end_time}")

        else:
            return "To help you better, please specify a date or time range like 'April 25' or 'from 2pm to 6pm'."

    except Exception as e:
        print(f"❌ Error parsing date-time: {e}")
        return "Sorry, I couldn’t understand the time range. Could you rephrase it?"

    # Firestore query
    events_query = db.collection("events") \
    .where("start", ">=", start_time) \
    .where("start", "<=", end_time) \
    .where("userId", "==", user_id) \
    .stream()
    events = []

    for event in events_query:
        data = event.to_dict()
        event_time = data["start"].astimezone(ist).strftime("%Y-%m-%d %I:%M %p IST")
        events.append(f"📌 {data['title']}\n📅 When: {event_time}\n📍 Location: {data.get('location', 'Not specified')}\n")

    if not events:
        if is_range:
            return f"No events found between {user_start_ist_str} and {user_end_ist_str}. 🎉"
        else:
            return "No events found for that day. 📅"

    summary = (
        f"Here are your events from {user_start_ist_str} to {user_end_ist_str}:\n\n"
        if is_range else
        "Here’s your event list for that day:\n\n"
    )

    return summary + "\n".join(events)



def get_tasks(parameters):
    """Fetches tasks from Firestore based on a time range or a full-day query."""
    from dateutil import parser
    user_id = request.json.get('originalDetectIntentRequest', {}).get('payload', {}).get('userId')  # 👈 ADD THIS
    try:
        # 1. Handle time-range if Dialogflow sends a startTime & endTime
        dt_range = parameters.get("date-time")
        if (
            isinstance(dt_range, list) and len(dt_range) > 0 and
            "startTime" in dt_range[0] and "endTime" in dt_range[0]
        ):
            start_time = parser.isoparse(dt_range[0]["startTime"]).astimezone(pytz.utc)
            end_time = parser.isoparse(dt_range[0]["endTime"]).astimezone(pytz.utc)
            is_range = True
            print(f"⏰ Using custom time window: {start_time} to {end_time}")
        else:
            # 2. Otherwise fallback to full day search
            selected_date = extract_date(parameters)
            start_time = datetime.combine(selected_date, datetime.min.time()).replace(tzinfo=pytz.utc)
            end_time = datetime.combine(selected_date, datetime.max.time()).replace(tzinfo=pytz.utc)
            is_range = False
            print(f"📅 Using full day: {start_time} to {end_time}")
    except Exception as e:
        print(f"❌ Error parsing date/time: {e}")
        return "Sorry, I couldn't understand the time you meant. Could you rephrase?"

    # 🔍 Query tasks from all relevant collections
    task_collections = {
        "tasks_self": "Personal",
        "tasks_team": "Team",
        "tasks_family": "Family",
        "tasks_self_work": "Work"
    }

    task_list = []

    for collection, label in task_collections.items():
        tasks_ref = db.collection(collection)
        tasks_query = db.collection(collection) \
        .where("DueDate", ">=", start_time) \
        .where("DueDate", "<=", end_time) \
        .where("userId", "==", user_id) \
        .stream()

        for task in tasks_query:
            task_data = task.to_dict()
            title = task_data.get("title", "Untitled")
            due = task_data.get("DueDate")
            due_str = due.strftime('%Y-%m-%d %I:%M %p') if due else "Unknown time"

            task_list.append(
                f"📌 {title}\n🕒 Due: {due_str}\n📂 Category: {label}\n"
            )

    # 🧠 Build final response
    if not task_list:
        if is_range:
            return "You're all clear during that time — no tasks found. 😌"
        else:
            return "Looks like you have no tasks scheduled for that day. 📅 Maybe time to chill?"

    # 📝 Summary header
    summary = (
        "Here are your tasks between the selected time range:\n\n"
        if is_range else
        "Here’s your task list for that day:\n\n"
    )

    return summary + "\n".join(task_list)


def fetch_events_by_time(parameters):
    """Handles queries like 'events in the next X hours/days/minutes' using @sys.duration."""
    user_id = request.json.get('originalDetectIntentRequest', {}).get('payload', {}).get('userId')  # 👈 ADD THIS
    ist = pytz.timezone("Asia/Kolkata")
    start_time = datetime.now(pytz.utc)  # Current time in UTC
    duration = parameters.get("duration")
    if not duration or "amount" not in duration or "unit" not in duration:
        return "Please tell me how far ahead to check. For example: 'next 2 hours'."

    amount = duration["amount"]
    unit = duration["unit"].lower()

    # Convert unit to timedelta
    if unit in ["h", "hour", "hours"]:
        delta = timedelta(hours=amount)
    elif unit in ["min", "minute", "minutes"]:
        delta = timedelta(minutes=amount)
    elif unit in ["d", "day", "days"]:
        delta = timedelta(days=amount)
    else:
        return "I didn't understand the time duration you mentioned. Try saying something like '2 hours' or '3 days'."

    now = datetime.now(pytz.utc)
    end_time = now + delta
    print(f"⏱ Fetching events from {now} to {end_time}")

    events_query = db.collection("events") \
    .where("start", ">=", start_time) \
    .where("start", "<=", end_time) \
    .where("userId", "==", user_id) \
    .stream()

    events = []

    for event in events_query:
        data = event.to_dict()
        event_time = data["start"].astimezone(ist).strftime("%Y-%m-%d %I:%M %p IST")
        events.append(f"📌 {data['title']}\n📅 When: {event_time}\n📍 Location: {data.get('location', 'Not specified')}\n")

    if not events:
        return f"You have no events in the next {amount} {unit}. Enjoy your free time! 😊"

    return f"Here’s what’s coming up in the next {amount} {unit}:\n\n" + "\n".join(events)




def get_tasks_by_time(parameters):
    """Fetches tasks happening within the specified duration from Firestore."""
    user_id = request.json.get('originalDetectIntentRequest', {}).get('payload', {}).get('userId')  # 👈 ADD THIS
    start_time = datetime.now(pytz.utc)  # Current time in UTC
    # Extract duration
    duration_data = parameters.get("duration")
    
    if not duration_data:
        return "Please specify a time duration, like '30 minutes' or '2 hours'."

    time_duration = duration_data.get("amount", 0)
    time_unit = duration_data.get("unit", "").lower()

    # Convert duration to timedelta
    time_units_map = {
        "h": "hours", "hour": "hours", "hours": "hours",
        "min": "minutes", "minute": "minutes", "minutes": "minutes"
    }
    
    if time_unit in time_units_map:
        time_arg = {time_units_map[time_unit]: time_duration}
        time_delta = timedelta(**time_arg)
    else:
        return "Oops! I couldn't understand the time duration you provided. Try saying something like '2 hours' or '30 minutes'."

    # Define time range
    now = datetime.now(pytz.utc)
    end_time = now + time_delta

    print(f"🔍 Searching for tasks due between {now} and {end_time}...")

    # Firestore collections to search
    task_collections = {
        "tasks_self": "Personal",
        "tasks_team": "Team",
        "tasks_family": "Family",
        "tasks_self_work": "Work"
    }
    
    task_list = []

    for collection, category_name in task_collections.items():
        tasks_ref = db.collection(collection)
        tasks_query = db.collection(collection) \
        .where("DueDate", ">=", start_time) \
        .where("DueDate", "<=", end_time) \
        .where("userId", "==", user_id) \
        .stream()


        for task in tasks_query:
            task_data = task.to_dict()
            task_due_time = task_data.get('DueDate')

            if task_due_time:
               ist = pytz.timezone("Asia/Kolkata")
               task_due_time = task_due_time.astimezone(ist).strftime('%Y-%m-%d %I:%M %p IST')

            else:
                task_due_time = "No due date specified"

            task_list.append(f"📌 *{task_data.get('title', 'Unnamed Task')}\n📅 *Due: {task_due_time}\n📂 Category: {category_name}\n")

    if not task_list:
        return f"Great news! You have no pending tasks in the next {time_duration} {time_unit}. Enjoy your free time! 😊"

    return f"Here’s what’s due in the next {time_duration} {time_unit}:\n\n" + "\n".join(task_list)

def handle_acknowledgment_response(parameters):
    responses = [
        "You're welcome! 😊",
        "Glad I could help!",
        "Anytime!",
        "Cool cool 😎",
        "No worries!",
        "👍",
        "Gotcha.",
        "Happy to assist!"
    ]
    return random.choice(responses)

from dateutil import parser

def extract_date(parameters):
    """Extracts and returns a date object from Dialogflow parameters."""
    date_str = parameters.get("date-time")

    if isinstance(date_str, list) and len(date_str) > 0:
        date_str = date_str[0]

    if isinstance(date_str, str):
        try:
            return parser.parse(date_str).date()
        except Exception as e:
            print(f"❌ Failed to parse date-time: {e}")

    # Default to today's date if parsing fails
    return datetime.today().date()

def send_fcm_notification(token, title, body):
    print(f"🚀 Sending FCM notification: token={token}, title={title}, body={body}")
    from firebase_admin import messaging

    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token,
        )
        response = messaging.send(message)
        print(f"✅ Notification sent: {response}")
    except Exception as e:
        print(f"❌ Error sending FCM notification: {e}")



@app.errorhandler(404)
def page_not_found(e):
    print(f"❌ 404 Error: {request.path} not found")
    return jsonify(error=str(e)), 404


# ✅ Run Flask API
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)