# -*- coding: utf-8 -*-
"""
=============================================================================
DỰ ÁN: PHẦN MỀM MÁY TÍNH QUẢN LÝ BÃI ĐỖ XE THÔNG MINH (DESKTOP POS APP - PP3)
Học phần: Công nghệ phần mềm nhúng
Kết nối: Giao tiếp trực tiếp với vi điều khiển AT89C51 trong Proteus qua cổng COM ảo
=============================================================================
"""

import tkinter as tk
from tkinter import ttk, messagebox
import time
import threading

# Thử import pyserial, nếu chưa cài thì chạy chế độ mô phỏng ảo
try:
    import serial
    import serial.tools.list_ports
    HAS_SERIAL = True
except ImportError:
    HAS_SERIAL = False

class SmartParkingApp:
    def __init__(self, root):
        self.root = root
        self.root.title("HỆ THỐNG TRẠM THU PHÍ & QUẢN LÝ BÃI XE 8051 (DESKTOP POS)")
        self.root.geometry("1100x700")
        self.root.configure(bg="#0b0f19")

        # Biến quản lý bãi xe
        self.max_slots = 10
        self.ticket_seq = 1000
        self.parked_vehicles = []
        self.serial_conn = None
        self.is_connected = False
        self.is_running = True

        self.setup_ui()
        self.refresh_slots()

    def setup_ui(self):
        # 1. Thanh Header điều khiển Cổng COM
        header_frame = tk.Frame(self.root, bg="#111827", padx=15, pady=10)
        header_frame.pack(fill=tk.X, side=tk.TOP)

        title_lbl = tk.Label(header_frame, text="🅿️ TRẠM THU PHÍ BÃI XE THÔNG MINH 8051", 
                             font=("Segoe UI", 14, "bold"), fg="#ffffff", bg="#111827")
        title_lbl.pack(side=tk.LEFT)

        # Cụm kết nối COM
        conn_frame = tk.Frame(header_frame, bg="#111827")
        conn_frame.pack(side=tk.RIGHT)

        tk.Label(conn_frame, text="Cổng COM:", font=("Segoe UI", 10), fg="#9ca3af", bg="#111827").pack(side=tk.LEFT, padx=5)
        
        self.combo_ports = ttk.Combobox(conn_frame, width=10, values=self.get_available_ports())
        self.combo_ports.pack(side=tk.LEFT, padx=5)
        if self.combo_ports["values"]:
            self.combo_ports.current(0)
        else:
            self.combo_ports.set("COM2")

        self.btn_connect = tk.Button(conn_frame, text="🔌 Kết Nối Proteus", font=("Segoe UI", 9, "bold"),
                                     bg="#2563eb", fg="#ffffff", command=self.toggle_serial, relief=tk.FLAT, padx=10)
        self.btn_connect.pack(side=tk.LEFT, padx=5)

        self.lbl_status = tk.Label(conn_frame, text="● Chưa kết nối", font=("Segoe UI", 9, "bold"), fg="#ef4444", bg="#111827")
        self.lbl_status.pack(side=tk.LEFT, padx=10)

        # 2. Khung Thao tác Cổng Vào & Cổng Ra
        main_content = tk.Frame(self.root, bg="#0b0f19", padx=15, pady=10)
        main_content.pack(fill=tk.BOTH, expand=True)

        # Cột Trái: Cổng Vào & Cổng Ra
        gates_frame = tk.Frame(main_content, bg="#0b0f19")
        gates_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))

        # Khung Cổng Vào
        in_box = tk.LabelFrame(gates_frame, text=" 🚗 CỔNG VÀO (GATE IN) ", font=("Segoe UI", 11, "bold"), 
                               fg="#10b981", bg="#1f2937", padx=12, pady=10)
        in_box.pack(fill=tk.X, pady=(0, 10))

        tk.Label(in_box, text="Nhập hoặc chọn Biển số xe vào:", font=("Segoe UI", 9), fg="#d1d5db", bg="#1f2937").pack(anchor=tk.W)
        self.entry_plate_in = tk.Entry(in_box, font=("Consolas", 13, "bold"), bg="#111827", fg="#facc15", insertbackground="white")
        self.entry_plate_in.insert(0, "88A-012.34")
        self.entry_plate_in.pack(fill=tk.X, pady=5)

        btn_in = tk.Button(in_box, text="📷 CHỤP BIỂN SỐ & MỞ BARIE VÀO (Gửi lệnh 'I')", font=("Segoe UI", 10, "bold"),
                           bg="#059669", fg="#ffffff", relief=tk.FLAT, pady=7, command=self.action_car_in)
        btn_in.pack(fill=tk.X, pady=5)

        # Khung Cổng Ra
        out_box = tk.LabelFrame(gates_frame, text=" 🚙 CỔNG RA (GATE OUT) ", font=("Segoe UI", 11, "bold"), 
                                fg="#38bdf8", bg="#1f2937", padx=12, pady=10)
        out_box.pack(fill=tk.X, pady=(0, 10))

        tk.Label(out_box, text="Biển số đối soát xe ra:", font=("Segoe UI", 9), fg="#d1d5db", bg="#1f2937").pack(anchor=tk.W)
        self.entry_plate_out = tk.Entry(out_box, font=("Consolas", 13, "bold"), bg="#111827", fg="#38bdf8", insertbackground="white")
        self.entry_plate_out.insert(0, "88A-012.34")
        self.entry_plate_out.pack(fill=tk.X, pady=5)

        btn_out = tk.Button(out_box, text="🔍 ĐỐI SOÁT & MỞ BARIE RA (Thu 5.000đ - Gửi 'O')", font=("Segoe UI", 10, "bold"),
                            bg="#0284c7", fg="#ffffff", relief=tk.FLAT, pady=7, command=self.action_car_out)
        btn_out.pack(fill=tk.X, pady=5)

        # Sơ đồ 10 vị trí đỗ
        slots_box = tk.LabelFrame(gates_frame, text=" SƠ ĐỒ 10 VỊ TRÍ ĐỖ XE ", font=("Segoe UI", 10, "bold"), 
                                  fg="#e5e7eb", bg="#1f2937", padx=10, pady=10)
        slots_box.pack(fill=tk.BOTH, expand=True)

        self.slots_frame = tk.Frame(slots_box, bg="#1f2937")
        self.slots_frame.pack(fill=tk.BOTH, expand=True)
        self.slot_labels = []
        for i in range(10):
            r = i // 5
            c = i % 5
            lbl = tk.Label(self.slots_frame, text=f"P{i+1}\nTRỐNG", font=("Consolas", 9, "bold"),
                           bg="#064e3b", fg="#6ee7b7", width=10, height=3, relief=tk.RIDGE)
            lbl.grid(row=r, column=c, padx=3, pady=3, sticky="nsew")
            self.slots_frame.grid_columnconfigure(c, weight=1)
            self.slots_frame.grid_rowconfigure(r, weight=1)
            self.slot_labels.append(lbl)

        # Cột Phải: Bảng Database & Nhật ký UART
        right_frame = tk.Frame(main_content, bg="#0b0f19")
        right_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        # Bảng Database
        db_box = tk.LabelFrame(right_frame, text=" 📊 DANH SÁCH PHƯƠNG TIỆN ĐANG ĐỖ ", font=("Segoe UI", 10, "bold"),
                               fg="#f59e0b", bg="#1f2937", padx=8, pady=8)
        db_box.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        cols = ("ticket", "plate", "time", "slot")
        self.tree = ttk.Treeview(db_box, columns=cols, show="headings", height=7)
        self.tree.heading("ticket", text="Mã Vé")
        self.tree.heading("plate", text="Biển Số Xe")
        self.tree.heading("time", text="Giờ Vào")
        self.tree.heading("slot", text="Vị Trí Đỗ")
        self.tree.column("ticket", width=80)
        self.tree.column("plate", width=120)
        self.tree.column("time", width=90)
        self.tree.column("slot", width=80)
        self.tree.pack(fill=tk.BOTH, expand=True)

        # Terminal Log
        log_box = tk.LabelFrame(right_frame, text=" 🖥️ NHẬT KÝ UART SERIAL TRUYỀN THÔNG VỚI 8051 ", font=("Segoe UI", 10, "bold"),
                                fg="#38bdf8", bg="#1f2937", padx=8, pady=8)
        log_box.pack(fill=tk.BOTH, expand=True)

        self.txt_log = tk.Text(log_box, height=8, bg="#050811", fg="#10b981", font=("Consolas", 9), relief=tk.FLAT)
        self.txt_log.pack(fill=tk.BOTH, expand=True)
        self.log("[SYSTEM] Phần mềm quản lý POS sẵn sàng kết nối vi điều khiển 8051...")

    def log(self, msg):
        self.txt_log.insert(tk.END, f"{msg}\n")
        self.txt_log.see(tk.END)

    def get_available_ports(self):
        if HAS_SERIAL:
            ports = [p.device for p in serial.tools.list_ports.comports()]
            return ports if ports else ["COM2"]
        return ["COM2"]

    def toggle_serial(self):
        if not HAS_SERIAL:
            messagebox.showwarning("Cảnh báo", "Chưa cài thư viện pyserial (chạy: pip install pyserial). Hệ thống đang chạy chế độ mô phỏng ảo.")
            return

        if not self.is_connected:
            port = self.combo_ports.get()
            try:
                self.serial_conn = serial.Serial(port, 9600, timeout=0.5)
                self.is_connected = True
                self.lbl_status.config(text=f"● Đã nối {port}", fg="#10b981")
                self.btn_connect.config(text="Ngắt Kết Nối", bg="#ef4444")
                self.log(f">> [UART] Đã kết nối thành công với cổng {port} (Baud 9600).")
                
                # Bắt đầu luồng đọc dữ liệu từ Proteus
                threading.Thread(target=self.serial_reader_thread, daemon=True).start()
            except Exception as e:
                messagebox.showerror("Lỗi Cổng COM", f"Không thể mở cổng {port}: {e}")
        else:
            self.is_connected = False
            if self.serial_conn:
                self.serial_conn.close()
            self.lbl_status.config(text="● Chưa kết nối", fg="#ef4444")
            self.btn_connect.config(text="🔌 Kết Nối Proteus", bg="#2563eb")
            self.log("[UART] Đã ngắt kết nối cổng COM.")

    def serial_reader_thread(self):
        while self.is_connected and self.serial_conn and self.serial_conn.is_open:
            try:
                line = self.serial_conn.readline().decode('utf-8', errors='ignore').strip()
                if line:
                    self.log(f"<< [8051] {line}")
            except:
                break

    def send_cmd(self, char_cmd):
        if self.is_connected and self.serial_conn and self.serial_conn.is_open:
            try:
                self.serial_conn.write(char_cmd.encode('ascii'))
                self.log(f">> [TX -> 8051] Đã gửi lệnh: '{char_cmd}' qua cổng COM ảo.")
            except Exception as e:
                self.log(f"[TX LOI] {e}")
        else:
            self.log(f">> [ẢO] Giả lập gửi lệnh '{char_cmd}' xuống 8051 (Chưa cắm COM thật).")

    def action_car_in(self):
        if len(self.parked_vehicles) >= self.max_slots:
            messagebox.showwarning("BÃI ĐẦY", "Bãi xe đã đủ 10/10 xe! Từ chối tiếp nhận.")
            return

        plate = self.entry_plate_in.get().strip().upper()
        if not plate:
            return

        if any(v['plate'] == plate for v in self.parked_vehicles):
            messagebox.showerror("Trùng xe", f"Xe biển số {plate} đã có trong bãi!")
            return

        # Tìm ô trống
        slot_idx = next(i for i in range(10) if not any(v['slot'] == i for v in self.parked_vehicles))
        self.ticket_seq += 1
        t_now = time.strftime("%H:%M:%S")

        self.parked_vehicles.append({
            "ticket": f"#TK{self.ticket_seq}",
            "plate": plate,
            "time": t_now,
            "slot": slot_idx
        })

        self.send_cmd('I') # Gửi lệnh 'I' cho chip 8051 mở barie
        self.refresh_slots()
        self.log(f">> [GATE-IN] Cấp vé #TK{self.ticket_seq} cho xe {plate} -> Ô P{slot_idx+1}")

    def action_car_out(self):
        if not self.parked_vehicles:
            messagebox.showinfo("Thông báo", "Bãi xe hiện đang trống.")
            return

        plate = self.entry_plate_out.get().strip().upper()
        v_idx = next((i for i, v in enumerate(self.parked_vehicles) if v['plate'] == plate), None)

        if v_idx is None:
            # Lấy xe đầu tiên nếu không gõ biển
            v = self.parked_vehicles.pop(0)
        else:
            v = self.parked_vehicles.pop(v_idx)

        self.send_cmd('O') # Gửi lệnh 'O' cho chip 8051 mở barie ra
        self.refresh_slots()
        self.log(f"<< [GATE-OUT] Xe {v['plate']} ra khỏi bãi. Thu 5.000 VNĐ. Giải phóng ô P{v['slot']+1}")

    def refresh_slots(self):
        # Cập nhật bảng
        for item in self.tree.get_children():
            self.tree.delete(item)

        for v in self.parked_vehicles:
            self.tree.insert("", tk.END, values=(v['ticket'], v['plate'], v['time'], f"Ô P{v['slot']+1}"))

        # Cập nhật ô đỗ
        for i in range(10):
            lbl = self.slot_labels[i]
            v = next((x for x in self.parked_vehicles if x['slot'] == i), None)
            if v:
                lbl.config(text=f"P{i+1}\n{v['plate']}", bg="#991b1b", fg="#fca5a5")
            else:
                lbl.config(text=f"P{i+1}\nTRỐNG", bg="#064e3b", fg="#6ee7b7")

if __name__ == "__main__":
    root = tk.Tk()
    app = SmartParkingApp(root)
    root.mainloop()
