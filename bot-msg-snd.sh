#!/bin/bash

# This is main script for sending messages to Telegram convo
# Usage:
# bot-msg-snd.sh "message text"

BOT_TOKEN="TOKEN"
CHAT_ID="CHAT_ID"

MSG="$1"

if [ -z "$MSG" ]; then
  exit 1
fi

/usr/bin/curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  --data-urlencode text="${MSG}" \
  -d disable_web_page_preview=true \
  > /dev/null 2>&1

exit 0
