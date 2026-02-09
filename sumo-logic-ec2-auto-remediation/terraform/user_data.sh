#!/bin/bash
yum update -y
yum install -y python3 pip

pip3 install flask

cat << 'EOF' > /home/ec2-user/app.py
from flask import Flask, jsonify
import time
import random
import logging
import json

app = Flask(__name__)

class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "endpoint": record.getMessage(),
            "response_time_ms": getattr(record, "response_time_ms", None),
            "timestamp": self.formatTime(record, self.datefmt)
        }
        return json.dumps(log_record)

logger = logging.getLogger()
handler = logging.FileHandler("/var/log/webapp.log")  # Log to file
formatter = JsonFormatter()
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

@app.route("/api/data")
def data():
    delay = random.uniform(1, 5)
    time.sleep(delay)
    response_time_ms = int(delay * 1000)
    logger.info("/api/data", extra={"response_time_ms": response_time_ms})
    return jsonify({"status": "ok", "response_time_ms": response_time_ms})

@app.route("/")
def health():
    return "App is running"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)   # Changed from port 80 to 8080
EOF

# Ensure the log file exists with the right permissions
touch /var/log/webapp.log
chown ec2-user:ec2-user /var/log/webapp.log
chmod 664 /var/log/webapp.log

# Run the app as ec2-user in the background
sudo -u ec2-user nohup python3 /home/ec2-user/app.py > /home/ec2-user/app.log 2>&1 &
