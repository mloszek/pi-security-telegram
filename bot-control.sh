#!/bin/bash

TOKEN="TOKEN"
CHAT_ID="CHAT_ID"
URL="https://api.telegram.org/bot$TOKEN"
TG="/usr/local/bin/bot-msg-snd.sh"

OFFSET_FILE="./offset.txt"

# Load last offset if exists
if [ -f "$OFFSET_FILE" ]; then
  OFFSET=$(cat "$OFFSET_FILE")
else
  OFFSET=0
  echo "$OFFSET" > "$OFFSET_FILE"
fi

# echo "Bot started. Current offset: $OFFSET"

while true; do

  OFFSET=$(cat "$OFFSET_FILE")
  RESPONSE=$(curl -s "$URL/getUpdates?timeout=30&offset=$OFFSET")

  # Check if response is valid
  if [ -z "$RESPONSE" ]; then
    sleep 1
    continue
  fi

  # Iterate safely over updates
  echo "$RESPONSE" | jq -c '.result[]?' | while read -r update; do

    UPDATE_ID=$(echo "$update" | jq '.update_id')
    MESSAGE=$(echo "$update" | jq -r '.message.text // empty')
    FROM_CHAT=$(echo "$update" | jq -r '.message.chat.id // empty')

    # Skip non-text messages
    if [ -z "$MESSAGE" ] || [ -z "$FROM_CHAT" ]; then
      continue
    fi

	# security filter (VERY IMPORTANT)
    if [ "$FROM_CHAT" != "$CHAT_ID" ]; then
        continue
    fi

    echo "Received: $MESSAGE (chat: $FROM_CHAT)"

	TEXT=""
    case "$MESSAGE" in
      "/start")
        TEXT="Hello 👋 I'm running on Raspberry Pi 🥧"
        ;;
      "/ping")
        TEXT="pong 🏓"
        ;;
      "/ip")
        TEXT=$(hostname -I | awk '{print $1}')
        ;;
      "/uptime")
        TEXT=$(uptime -p)
        ;;
      *)
        TEXT="You said: $MESSAGE"
        ;;
    esac

    "$TG" "$TEXT"

    OFFSET=$((++UPDATE_ID))

    # Persist offset to disk (prevents duplicates after reboot)
    echo "$OFFSET" > "$OFFSET_FILE"

  done

  sleep 1
done
