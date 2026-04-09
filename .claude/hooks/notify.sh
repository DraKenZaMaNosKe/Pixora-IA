#!/usr/bin/env bash
# Notification hook — ring the terminal bell + print an attention message.
# Keep it simple and cross-platform; users can upgrade to desktop notifications
# in their personal settings.local.json if they want richer feedback.
printf '\a'
echo "🔔 Pixora — Claude needs your attention"
