#!/usr/bin/bash

cat << 'EOF' > /etc/systemd/system/startSH.service
[Unit]
Description=Saturn Start Update

[Service]
WorkingDirectory=/root/start
ExecStart=/bin/bash git_fetch.sh
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/startSH.timer
[Unit]
Description=Run saturn auto update

[Timer]
OnBootSec=15m
OnUnitActiveSec=15m
AccuracySec=5m
Unit=startSH.service

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now startSH.timer
systemctl list-timers startSH.timer.timer
