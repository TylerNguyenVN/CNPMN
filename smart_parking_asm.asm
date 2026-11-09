; =====================================================================
; HỆ THỐNG BÃI ĐỖ XE THÔNG MINH - 8051 (AT89C51) VIẾT BẰNG ASSEMBLY
; Học phần: Công nghệ phần mềm nhúng
; Tương thích hoàn toàn với sơ đồ mạch SimulIDE: smart_parking.sim1
; =====================================================================
; SƠ ĐỒ CHÂN KẾT NỐI (PINOUT):
; 1. LCD 16x2 (HD44780):
;    - D0 - D7 : Nối vào Port 2 (P2.0 - P2.7)
;    - RS      : Nối vào P3.5 (0 = Lệnh, 1 = Dữ liệu)
;    - EN      : Nối vào P3.6 (Xung chốt dữ liệu)
;    - RW      : Nối GND (Chỉ ghi dữ liệu)
; 2. Cảm biến / Nút bấm đầu vào:
;    - P3.2 (INT0) : Cảm biến xe vào (IR1 - Nút bấm kéo xuống GND)
;    - P3.3 (INT1) : Cảm biến xe ra  (IR3 - Nút bấm kéo xuống GND)
; 3. Cơ cấu chấp hành & Báo hiệu (Port 1):
;    - P1.0 : LED Xanh (Báo còn chỗ / Cổng đang mở)
;    - P1.1 : LED Đỏ   (Báo bãi xe đã đầy - FULL)
;    - P1.2 : Còi Buzzer (Cảnh báo khi bãi đầy cố tình vào)
;    - P1.3 : Động cơ Barie vào (1 = Mở cần gạt, 0 = Đóng)
;    - P1.4 : Động cơ Barie ra  (1 = Mở cổng ra, 0 = Đóng)
; 4. Truyền thông UART (9600 Baud, 8-N-1):
;    - P3.1 : TXD (Truyền thông tin vé xe, số slot lên máy tính)
;    - P3.0 : RXD (Nhận lệnh điều khiển từ máy tính / Web)
; =====================================================================

    ORG 0000H
    LJMP MAIN_START

; --- ĐỊNH NGHĨA CÁC CHÂN BIT ---
LCD_RS          BIT P3.5
LCD_EN          BIT P3.6

SENSOR_IN       BIT P3.2    ; Cảm biến vào (0 = phát hiện xe)
SENSOR_OUT      BIT P3.3    ; Cảm biến ra  (0 = phát hiện xe)

LED_GREEN       BIT P1.0    ; Đèn xanh
LED_RED         BIT P1.1    ; Đèn đỏ
BUZZER          BIT P1.2    ; Còi cảnh báo
BARRIER_IN      BIT P1.3    ; Cần Barie cổng vào
BARRIER_OUT     BIT P1.4    ; Cần Barie cổng ra

; --- ĐỊNH NGHĨA Ô NHỚ RAM DỮ LIỆU ---
COUNT_CARS      EQU 30H     ; Số xe hiện có trong bãi (0 -> 10)
SLOTS_FREE      EQU 31H     ; Số chỗ trống còn lại (10 -> 0)
TICKET_LO       EQU 32H     ; Byte thấp mã vé xe (Ví dụ: 01H)
TICKET_HI       EQU 33H     ; Byte cao mã vé xe (Ví dụ: 10H -> TK1001)

MAX_CAPACITY    EQU 10      ; Sức chứa tối đa của bãi là 10 xe

; =====================================================================
; CHƯƠNG TRÌNH CHÍNH
; =====================================================================
    ORG 0040H

MAIN_START:
    ; 1. Khởi tạo giá trị ban đầu cho các Port
    MOV P1, #00H            ; Tắt toàn bộ LED, Còi, Động cơ Barie
    SETB SENSOR_IN          ; Thiết lập P3.2 làm đầu vào
    SETB SENSOR_OUT         ; Thiết lập P3.3 làm đầu vào
    MOV P2, #00H            ; Chuẩn bị Bus dữ liệu LCD

    ; 2. Khởi tạo biến hệ thống
    MOV COUNT_CARS, #0      ; Ban đầu bãi xe hoàn toàn trống (0 xe)
    MOV SLOTS_FREE, #MAX_CAPACITY ; Còn nguyên 10 chỗ trống
    MOV TICKET_HI, #10H     ; Khởi tạo vé đầu tiên #TK1000
    MOV TICKET_LO, #00H

    ; 3. Khởi tạo UART 9600 Baud
    LCALL UART_INIT

    ; 4. Khởi tạo Màn hình LCD 16x2
    LCALL LCD_INIT

    ; 5. Gửi thông báo khởi động lên màn hình và UART
    LCALL UPDATE_STATUS
    MOV DPTR, #STR_INIT_MSG
    LCALL UART_SEND_STRING

; =====================================================================
; VÒNG LẶP QUÉT TÍN HIỆU CHÍNH (MAIN LOOP)
; =====================================================================
MAIN_LOOP:
    ; --- BƯỚC 1: KIỂM TRA LỆNH TỪ UART (NẾU CÓ) ---
    JNB RI, SCAN_SENSOR_IN
    CLR RI
    MOV A, SBUF             ; Đọc ký tự nhận được từ máy tính / Web
    CJNE A, #'I', NOT_CMD_I ; Ký tự 'I' (In): Mở cổng vào từ xa
    LCALL PROCESS_GATE_IN
    SJMP SCAN_SENSOR_IN

NOT_CMD_I:
    CJNE A, #'O', NOT_CMD_O ; Ký tự 'O' (Out): Mở cổng ra từ xa
    LCALL PROCESS_GATE_OUT
    SJMP SCAN_SENSOR_IN

NOT_CMD_O:
    CJNE A, #'R', SCAN_SENSOR_IN ; Ký tự 'R' (Reset): Đặt lại bãi xe về 0
    MOV COUNT_CARS, #0
    LCALL UPDATE_STATUS
    MOV DPTR, #STR_RESET_MSG
    LCALL UART_SEND_STRING

; --- BƯỚC 2: QUÉT CẢM BIẾN CỔNG VÀO (P3.2) ---
SCAN_SENSOR_IN:
    JB SENSOR_IN, SCAN_SENSOR_OUT ; Nếu P3.2 = 1 (chưa có xe) -> quét cổng ra
    LCALL DELAY_20MS              ; Chống rung phím / nhiễu quang
    JB SENSOR_IN, SCAN_SENSOR_OUT ; Đọc lại, nếu vẫn bằng 0 mới xử lý

    ; Xác nhận có xe vào cổng
    LCALL PROCESS_GATE_IN
    JNB SENSOR_IN, $              ; Chờ cho đến khi xe đi qua hẳn (nhả nút)

; --- BƯỚC 3: QUÉT CẢM BIẾN CỔNG RA (P3.3) ---
SCAN_SENSOR_OUT:
    JB SENSOR_OUT, LOOP_CONTINUE  ; Nếu P3.3 = 1 -> lặp lại
    LCALL DELAY_20MS              ; Chống rung phím
    JB SENSOR_OUT, LOOP_CONTINUE

    ; Xác nhận có xe ra cổng
    LCALL PROCESS_GATE_OUT
    JNB SENSOR_OUT, $             ; Chờ cho đến khi xe qua hẳn (nhả nút)

LOOP_CONTINUE:
    SJMP MAIN_LOOP

; =====================================================================
; CHU TRÌNH XỬ LÝ XE VÀO (GATE IN)
; =====================================================================
PROCESS_GATE_IN:
    ; Kiểm tra bãi đầy chưa: so sánh COUNT_CARS với 10
    MOV A, COUNT_CARS
    CJNE A, #MAX_CAPACITY, GATE_IN_ALLOW

    ; --- NẾU BÃI ĐÃ ĐẦY ---
    MOV DPTR, #STR_ALERT_FULL
    LCALL UART_SEND_STRING
    ; Kêu còi cảnh báo 3 tiếng bíp
    MOV R4, #3
BEEP_LOOP:
    SETB BUZZER
    SETB LED_RED
    LCALL DELAY_100MS
    CLR BUZZER
    LCALL DELAY_100MS
    DJNZ R4, BEEP_LOOP
    SETB LED_RED            ; Giữ đèn đỏ bật
    RET

GATE_IN_ALLOW:
    ; Tăng số xe lên 1
    INC COUNT_CARS

    ; Tăng mã vé xe
    INC TICKET_LO
    MOV A, TICKET_LO
    CJNE A, #100, NO_CARRY_TICKET
    MOV TICKET_LO, #0
    INC TICKET_HI
NO_CARRY_TICKET:

    ; Cập nhật LCD và đèn LED
    LCALL UPDATE_STATUS

    ; Gửi thông báo vé xe qua UART
    MOV DPTR, #STR_GATE_IN_OK
    LCALL UART_SEND_STRING
    MOV A, COUNT_CARS
    LCALL UART_SEND_NUM
    MOV DPTR, #STR_NEWLINE
    LCALL UART_SEND_STRING

    ; Mở Barie vào & Bật đèn xanh
    SETB LED_GREEN
    SETB BARRIER_IN
    LCALL DELAY_1500MS      ; Giữ Barie mở 1.5 giây cho xe đi qua

    ; Đóng Barie an toàn
    CLR BARRIER_IN
    CLR LED_GREEN
    MOV DPTR, #STR_GATE_IN_CLOSED
    LCALL UART_SEND_STRING

    ; Gửi báo cáo số slot còn lại
    LCALL UART_SEND_STATUS
    RET

; =====================================================================
; CHU TRÌNH XỬ LÝ XE RA (GATE OUT)
; =====================================================================
PROCESS_GATE_OUT:
    ; Kiểm tra bãi có xe không
    MOV A, COUNT_CARS
    JNZ GATE_OUT_ALLOW
    ; Bãi đang không có xe nào
    MOV DPTR, #STR_EMPTY_ALERT
    LCALL UART_SEND_STRING
    RET

GATE_OUT_ALLOW:
    ; Giảm số lượng xe đi 1
    DEC COUNT_CARS

    ; Cập nhật LCD và đèn
    LCALL UPDATE_STATUS

    ; Gửi thông báo thu phí và mở Barie ra
    MOV DPTR, #STR_GATE_OUT_FEE
    LCALL UART_SEND_STRING

    ; Mở Barie ra & Bật đèn xanh
    SETB LED_GREEN
    SETB BARRIER_OUT
    LCALL DELAY_1500MS      ; Giữ Barie mở 1.5 giây

    ; Đóng Barie ra
    CLR BARRIER_OUT
    CLR LED_GREEN
    MOV DPTR, #STR_GATE_OUT_CLOSED
    LCALL UART_SEND_STRING

    ; Gửi báo cáo số slot
    LCALL UART_SEND_STATUS
    RET

; =====================================================================
; CẬP NHẬT TRẠNG THÁI RA MÀN HÌNH LCD 16X2 & ĐÈN BÁO
; =====================================================================
UPDATE_STATUS:
    ; Tính số chỗ trống: SLOTS_FREE = 10 - COUNT_CARS
    CLR C
    MOV A, #MAX_CAPACITY
    SUBB A, COUNT_CARS
    MOV SLOTS_FREE, A

    ; Dòng 1 LCD: Tiêu đề hệ thống
    MOV A, #80H             ; Đặt con trỏ về đầu dòng 1
    LCALL LCD_CMD
    MOV DPTR, #STR_LCD_LINE1
    LCALL LCD_PRINT_STRING

    ; Dòng 2 LCD: Kiểm tra đầy hay còn chỗ
    MOV A, #0C0H            ; Đặt con trỏ về đầu dòng 2
    LCALL LCD_CMD

    MOV A, COUNT_CARS
    CJNE A, #MAX_CAPACITY, LCD_ST_FREE

    ; Bãi đầy xe (FULL)
    MOV DPTR, #STR_LCD_FULL
    LCALL LCD_PRINT_STRING
    SETB LED_RED            ; Bật đèn đỏ
    RET

LCD_ST_FREE:
    ; Bãi còn chỗ trống
    CLR LED_RED             ; Tắt đèn đỏ
    MOV DPTR, #STR_LCD_SLOTS
    LCALL LCD_PRINT_STRING  ; In chuỗi "SLOTS: "

    ; In 2 chữ số của SLOTS_FREE
    MOV A, SLOTS_FREE
    LCALL LCD_PRINT_2DIGITS

    ; In tiếp "/10 FREE"
    MOV DPTR, #STR_LCD_FREE
    LCALL LCD_PRINT_STRING
    RET

; =====================================================================
; CÁC CHƯƠNG TRÌNH CON ĐIỀU KHIỂN LCD 16X2
; =====================================================================
LCD_INIT:
    LCALL DELAY_50MS
    MOV A, #38H             ; Chế độ 8-bit, 2 dòng hiển thị, font 5x7
    LCALL LCD_CMD
    LCALL DELAY_5MS
    MOV A, #0CH             ; Bật hiển thị, tắt con trỏ nhấp nháy
    LCALL LCD_CMD
    MOV A, #06H             ; Tự động tăng vị trí con trỏ sang phải
    LCALL LCD_CMD
    MOV A, #01H             ; Xóa toàn bộ màn hình
    LCALL LCD_CMD
    LCALL DELAY_5MS
    RET

; Gửi lệnh điều khiển (RS = 0)
LCD_CMD:
    MOV P2, A               ; Đặt dữ liệu lệnh lên Port 2
    CLR LCD_RS              ; RS = 0: Gửi lệnh
    SETB LCD_EN             ; Kéo EN lên 1
    LCALL DELAY_1MS
    CLR LCD_EN              ; Kéo EN xuống 0 tạo sườn âm chốt lệnh
    LCALL DELAY_2MS
    RET

; Gửi ký tự hiển thị (RS = 1)
LCD_DATA_WR:
    MOV P2, A               ; Đặt mã ký tự ASCII lên Port 2
    SETB LCD_RS             ; RS = 1: Gửi ký tự
    SETB LCD_EN             ; Kéo EN lên 1
    LCALL DELAY_1MS
    CLR LCD_EN              ; Kéo EN xuống 0 chốt ký tự
    LCALL DELAY_2MS
    RET

; In chuỗi ký tự kết thúc bằng byte 0 (NULL) từ bộ nhớ Flash ROM
LCD_PRINT_STRING:
    CLR A
    MOVC A, @A+DPTR
    JZ LCD_PRINT_END
    LCALL LCD_DATA_WR
    INC DPTR
    SJMP LCD_PRINT_STRING
LCD_PRINT_END:
    RET

; In một số nguyên từ 0 đến 99 thành 2 chữ số ASCII lên LCD
LCD_PRINT_2DIGITS:
    MOV B, #10
    DIV AB                  ; A = Chữ số hàng chục, B = Chữ số hàng đơn vị
    ADD A, #'0'             ; Chuyển sang mã ASCII
    LCALL LCD_DATA_WR       ; In hàng chục
    MOV A, B
    ADD A, #'0'             ; Chuyển sang mã ASCII
    LCALL LCD_DATA_WR       ; In hàng đơn vị
    RET

; =====================================================================
; CÁC CHƯƠNG TRÌNH CON TRUYỀN NHẬN UART
; =====================================================================
UART_INIT:
    MOV TMOD, #20H          ; Timer 1 chế độ 2 (8-bit tự nạp lại)
    MOV TH1, #0FDH          ; 9600 Baud ứng với thạch anh 11.0592MHz (hoặc xấp xỉ 12MHz)
    MOV TL1, #0FDH
    MOV SCON, #50H          ; Chế độ 1: 8-bit UART, cho phép nhận (REN = 1)
    SETB TR1                ; Khởi động Timer 1
    RET

UART_SEND_CHAR:
    MOV SBUF, A             ; Ghi ký tự vào bộ đệm truyền
    JNB TI, $               ; Chờ truyền xong (cờ TI = 1)
    CLR TI                  ; Xóa cờ TI cho lần truyền sau
    RET

UART_SEND_STRING:
    CLR A
    MOVC A, @A+DPTR
    JZ UART_STR_END
    LCALL UART_SEND_CHAR
    INC DPTR
    SJMP UART_SEND_STRING
UART_STR_END:
    RET

; In số dạng số nguyên 0 -> 99 ra UART
UART_SEND_NUM:
    MOV B, #10
    DIV AB
    JZ UART_SINGLE_DIGIT
    ADD A, #'0'
    LCALL UART_SEND_CHAR
UART_SINGLE_DIGIT:
    MOV A, B
    ADD A, #'0'
    LCALL UART_SEND_CHAR
    RET

; Gửi trạng thái xe và slot hiện tại qua UART
UART_SEND_STATUS:
    MOV DPTR, #STR_STATUS_PREFIX
    LCALL UART_SEND_STRING
    MOV A, COUNT_CARS
    LCALL UART_SEND_NUM
    MOV DPTR, #STR_SLOTS_PREFIX
    LCALL UART_SEND_STRING
    MOV A, SLOTS_FREE
    LCALL UART_SEND_NUM
    MOV DPTR, #STR_NEWLINE
    LCALL UART_SEND_STRING
    RET

; =====================================================================
; CÁC CHƯƠNG TRÌNH CON TẠO THỜI GIAN TRỄ (DELAY)
; =====================================================================
DELAY_1MS:
    MOV R7, #248
    DJNZ R7, $
    RET

DELAY_2MS:
    MOV R6, #2
D_2MS:
    MOV R7, #248
    DJNZ R7, $
    DJNZ R6, D_2MS
    RET

DELAY_5MS:
    MOV R6, #5
D_5MS:
    MOV R7, #248
    DJNZ R7, $
    DJNZ R6, D_5MS
    RET

DELAY_20MS:
    MOV R6, #20
D_20MS:
    MOV R7, #248
    DJNZ R7, $
    DJNZ R6, D_20MS
    RET

DELAY_50MS:
    MOV R6, #50
D_50MS:
    MOV R7, #248
    DJNZ R7, $
    DJNZ R6, D_50MS
    RET

DELAY_100MS:
    MOV R6, #100
D_100MS:
    MOV R7, #248
    DJNZ R7, $
    DJNZ R6, D_100MS
    RET

DELAY_1500MS:
    MOV R5, #15
D_1500MS:
    LCALL DELAY_100MS
    DJNZ R5, D_1500MS
    RET

; =====================================================================
; VÙNG LƯU TRỮ CHUỖI KÝ TỰ HẰNG SỐ (CONST STRINGS IN ROM)
; =====================================================================
STR_LCD_LINE1:      DB 'SMART PARKING 4.0', 0
STR_LCD_FULL:       DB 'STATUS: FULL !!!', 0
STR_LCD_SLOTS:      DB 'SLOTS: ', 0
STR_LCD_FREE:       DB '/10 FREE', 0

STR_INIT_MSG:       DB '[INIT] HE THONG SAN SANG (ASSEMBLY)\r\n', 0
STR_RESET_MSG:      DB '[SYSTEM] DA RESET BAI XE VE 0.\r\n', 0
STR_ALERT_FULL:     DB '[ALERT] BAI DAY! TU CHOI XE VAO.\r\n', 0
STR_GATE_IN_OK:     DB '[GATE-IN] MO BARIE CHO XE #', 0
STR_GATE_IN_CLOSED: DB '[GATE-IN] BARIE DA DONG AN TOAN.\r\n', 0
STR_GATE_OUT_FEE:   DB '[GATE-OUT] THU PHI: 5,000 VND | MO BARIE RA...\r\n', 0
STR_GATE_OUT_CLOSED:DB '[GATE-OUT] BARIE RA DA DONG AN TOAN.\r\n', 0
STR_EMPTY_ALERT:    DB '[GATE-OUT] BAI DANG TRONG, KHONG CO XE RA.\r\n', 0

STR_STATUS_PREFIX:  DB '[STATUS] CARS:', 0
STR_SLOTS_PREFIX:   DB ' SLOTS:', 0
STR_NEWLINE:        DB '\r\n', 0

    END
