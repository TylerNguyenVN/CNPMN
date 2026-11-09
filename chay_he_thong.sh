#!/bin/bash
# ==============================================================================
# SCRIPT KHỞI ĐỘNG HỆ THỐNG BÃI XE THÔNG MINH 8051 (LOCAL HTTP SERVER & CHROME)
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

PORT=8000
URL="http://localhost:$PORT/mo_phong_bai_xe.html"

echo "======================================================================="
echo "  🚀 KHỞI ĐỘNG HỆ THỐNG BÃI XE THÔNG MINH (KẾT NỐI CAMERA & PROTEUS 8051)"
echo "======================================================================="
echo "📍 Địa chỉ máy chủ: $URL"
echo "💡 Chạy trên Localhost để cấp đủ quyền Camera & Cổng COM WebSerial!"
echo "-----------------------------------------------------------------------"

# Mở Google Chrome (nếu có) hoặc trình duyệt mặc định
if [ -d "/Applications/Google Chrome.app" ]; then
  echo "🌐 Đang mở Google Chrome..."
  open -a "Google Chrome" "$URL"
elif [ -d "/Applications/CocCoc.app" ]; then
  echo "🌐 Đang mở Cốc Cốc..."
  open -a "CocCoc" "$URL"
else
  echo "🌐 Đang mở trình duyệt mặc định..."
  open "$URL"
fi

echo "🟢 Máy chủ HTTP đang lắng nghe tại cổng $PORT. Nhấn Ctrl+C để dừng."
python3 -m http.server $PORT
