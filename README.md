# Pi monitoring and alerting via Telegram bot convo message
## About
This project was created using ChatGPT as a quick and dirty learning material, please be aware that this is not a proper and long term solution for securing your Pi.<br>
For Telegram communication to work you have to first create a bot with BotFather Telegram bot ([instructions](https://www.instructables.com/Set-up-Telegram-Bot-on-Raspberry-Pi/)) and obtain both **token** and **chat id** and then insert them in proper variables in **bot-msg-snd.sh** replacing the current values.

## Scripts
+ bot-msg-snd.sh - main shell script for sending message to conversation with your bot
+ rpi-security-monitor.sh - main logic of monitor, works best if automated

Make sure that scripts are placed in */usr/local/bin/* directory.
## Automation
### Create service
```
sudo nano /etc/systemd/system/rpi-security-monitor.service
```
rpi-security-monitor.service:
```
[Unit]
Description=Raspberry Pi Security Monitor

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rpi-security-monitor.sh
```
### Create timer
```
sudo nano /etc/systemd/system/rpi-security-monitor.timer
```
rpi-security-monitor.timer:
```
[Unit]
Description=Run Raspberry Pi Security Monitor every minute

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Persistent=true

[Install]
WantedBy=timers.target
```
### Enable + start:
```
sudo systemctl daemon-reload
sudo systemctl enable --now rpi-security-monitor.timer
```
### Check
```
systemctl status rpi-security-monitor.timer
```
