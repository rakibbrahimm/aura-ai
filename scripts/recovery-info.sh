#!/data/data/com.termux/files/usr/bin/bash
echo "AURA recovery backups:"
find "$HOME/AURA-AI/backups" -maxdepth 1 -type d 2>/dev/null | sort
