#!/bin/bash
grim -g "$(slurp)" /tmp/ocr.png && tesseract /tmp/ocr.png - -l eng 2>/dev/null | wl-copy && notify-send "OCR Result" "$(wl-paste)"
