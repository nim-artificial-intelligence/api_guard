from collections import deque
from flask import Flask, jsonify, request, abort
import time
from threading import Lock
from dotenv import load_dotenv
import os


# Define the path to the .env file
if 'XDG_CONFIG_HOME' in os.environ:
    print('XDG_CONFIG_HOME is', os.environ['XDG_CONFIG_HOME'])
env_path = os.path.join(os.getenv('XDG_CONFIG_HOME', './'), 'api_guard/.env')
print('Trying to load config from:', env_path)
load_dotenv(env_path)

request_limit_per_60_seconds = int(os.getenv('RATE_LIMIT', 500))
request_default_delay = (60 / request_limit_per_60_seconds) * 0.25
slug = os.getenv('SLUG', '')
if slug and not slug.startswith('/'):
    slug = '/' + slug

port_number = int(os.getenv('PORT', 5000))
auth_token = os.getenv('AUTH_TOKEN')

print('Using the following configuration')
print(f'    - slug           : {slug}')
print(f'    - port           : {port_number}')
print(f'    - local base URL : http://127.0.0.1:{port_number}{slug}')
print(f'    - request limit  : {request_limit_per_60_seconds} per minute')
print(f'    - default delay  : {request_default_delay}')
print(f'    - auth token     : {auth_token}')

app = Flask(__name__)
request_timestamps = deque()
timestamps_lock = Lock()


def verify_auth_token():
    token = request.headers.get('Authorization')
    print(f'Token: `{token}`, auth_token: `{auth_token}`')
    if not token or token != auth_token:
        abort(401, description="Unauthorized")


@app.route(f'{slug}/get_rate_limit', methods=['GET'])
def get_rate_limit():
    verify_auth_token()
    return jsonify({"current_rate_limit": request_limit_per_60_seconds, "default_delay": request_default_delay})


@app.route(f'{slug}/set_rate_limit', methods=['POST'])
def set_rate_limit():
    verify_auth_token()
    global request_limit_per_60_seconds
    new_limit = request.args.get('new_limit', None)
    new_delay = request.args.get('new_delay', None)

    ret = {}
    if new_limit and new_limit.isdigit():
        new_limit = int(new_limit)
        if new_limit > 0:
            with timestamps_lock:
                request_limit_per_60_seconds = new_limit
                ret = {"success": True, "new_rate_limit": new_limit}
        else:
            ret = {"success": False, "error": "Rate limit must be positive"}
    else:
        ret = {"success": False, "error": "Invalid rate limit value"}

    if ret["success"] is False:
        return jsonify(ret), 400

    if new_delay and new_delay.isdigit():
        new_delay = int(new_delay)
        if new_delay > 0:
            with timestamps_lock:
                request_limit_per_60_seconds = new_delay
                ret.update({"success": True, "new_rate_limit": new_delay})
        else:
            ret.update({"success": False, "error": "Rate limit must be positive"})
    else:
        ret.update({"success": False, "error": "Invalid rate limit value"})

    if ret["success"] is False:
        return jsonify(ret), 400
    return jsonify(ret)


@app.route(f'{slug}/request_access', methods=['GET'])
def request_access():
    verify_auth_token()
    handle_delay = request.args.get('handle_delay', 'False').lower() == 'true'

    with timestamps_lock:
        current_time = time.time()
        # remove old timestamps
        while request_timestamps and current_time - request_timestamps[0] > 60:
            request_timestamps.popleft()

        if len(request_timestamps) < request_limit_per_60_seconds:
            request_timestamps.append(current_time + request_default_delay / 1000)
            return jsonify({"delay_ms": request_default_delay})
        else:
            oldest_request_time = request_timestamps[0]
            delay_seconds = 60 - (current_time - oldest_request_time)
            delay_ms = delay_seconds * 1000 - request_default_delay
            if delay_ms < 0:
                delay_ms = request_default_delay

            request_timestamps.append(current_time + delay_ms / 1000)
            if handle_delay:
                time.sleep(delay_ms * 1000)
                return jsonify({"delay_ms": 0})
            else:
                return jsonify({"delay_ms": delay_ms})


if __name__ == '__main__':
    app.run(debug=True, port=port_number)
