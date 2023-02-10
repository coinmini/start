#!/bin/sh
git fetch
LOCAL=$(git log -1 --pretty=format:"%H")
REMOTE=$(git log remotes/origin/main -1 --pretty=format:"%H")

if [ $LOCAL = $REMOTE ]; then
    echo "Up-to-date"
else
    echo "Need update"
    git pull
    /bin/cp -rf /root/start/start.sh /root/saturn/
    chmod +x /root/saturn/start.sh
fi
