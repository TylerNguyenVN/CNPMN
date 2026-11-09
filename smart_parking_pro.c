/*
 * =========================================================================================
 * DỰ ÁN THỰC TẾ: HỆ THỐNG BÃI ĐỖ XE THÔNG MINH CÔNG NGHIỆP (SMART PARKING 4.0 PRO)
 * HỖ TRỢ ĐỒNG MÔ PHỎNG THỜI GIAN THỰC (HARDWARE-IN-THE-LOOP VỚI PROTEUS QUA COMPIM)
 * Học phần: Công nghệ phần mềm nhúng
 * Vi điều khiển: AT89C51 / 8051 (Thạch anh 11.0592 MHz - Baudrate 9600)
 * =========================================================================================
 * GIAO THỨC TRUYỀN THÔNG 2 CHIỀU (BIDIRECTIONAL UART PROTOCOL):
 * 1. Máy tính / Web gửi xuống 8051:
 *    - Lệnh 'I' : Xác nhận xe vào hợp lệ (từ Camera AI) -> 8051 tăng xe, mở Barie Vào.
 *    - Lệnh 'O' : Xác nhận xe ra hợp lệ (từ Camera AI)  -> 8051 giảm xe, mở Barie Ra.
 *    - Lệnh 'R' : Đặt lại bãi xe về 0.
 *
 * 2. 8051 gửi phản hồi lên Máy tính / Web:
 *    - "[STATUS] COUNT:xx SLOTS:yy"
 *    - "[GATE-IN] OPEN" / "[GATE-IN] CLOSE"
 *    - "[ALERT] FULL"
 * =========================================================================================
 */

#include <reg51.h>
#include <stdio.h>

// --- ĐỊNH NGHĨA CÁC CHÂN CẢM BIẾN ---
sbit IR_IN_FRONT  = P3^2;  // Cảm biến trước cổng vào (P3.2 / INT0)
sbit IR_IN_BACK   = P3^4;  // Cảm biến sau cổng vào (P3.4 / T0 - chống kẹp)
sbit IR_OUT_FRONT = P3^3;  // Cảm biến trước cổng ra (P3.3 / INT1)
sbit IR_OUT_BACK  = P3^7;  // Cảm biến sau cổng ra (P3.7 - chống kẹp)

// --- ĐỊNH NGHĨA NGOẠI VI & BARIE ---
sbit LED_GREEN    = P1^0;  // Đèn xanh cổng vào
sbit LED_RED      = P1^1;  // Đèn đỏ báo đầy bãi
sbit BUZZER       = P1^2;  // Còi cảnh báo
sbit BARRIER_IN   = P1^3;  // Barie Vào
sbit BARRIER_OUT  = P1^4;  // Barie Ra

// --- ĐỊNH NGHĨA MÀN HÌNH LCD 16x2 ---
sbit LCD_RS       = P3^5;
sbit LCD_EN       = P3^6;
#define LCD_DATA  P2

#define MAX_CAPACITY 10
unsigned char current_cars = 0;
unsigned int ticket_id = 1000;

// --- KHAI BÁO NGUYÊN MẪU HÀM ---
void delay_ms(unsigned int ms);
void uart_init(void);
void uart_send_char(char c);
void uart_send_string(char *s);
void lcd_cmd(unsigned char cmd);
void lcd_char(char c);
void lcd_string(char *s);
void lcd_init(void);
void update_lcd_status(void);
void execute_gate_in(void);
void execute_gate_out(void);
void check_uart_commands(void);

/* =====================================================================
 * HÀM DELAY ĐỊNH THỜI
 * ===================================================================== */
void delay_ms(unsigned int ms) {
    unsigned int i, j;
    for (i = 0; i < ms; i++)
        for (j = 0; j < 120; j++);
}

/* =====================================================================
 * KHỞI TẠO VÀ TRUYỀN NHẬN UART (9600 BAUD, FOSC = 11.0592MHz)
 * ===================================================================== */
void uart_init(void) {
    TMOD |= 0x20; // Timer 1, chế độ 2 (8-bit auto-reload)
    TH1 = 0xFD;   // 9600 Baud với Fosc = 11.0592MHz
    TR1 = 1;      // Bật Timer 1
    SCON = 0x50;  // Chế độ 1: 8-bit UART, REN = 1 (cho phép nhận)
}

void uart_send_char(char c) {
    SBUF = c;
    while (TI == 0);
    TI = 0;
}

void uart_send_string(char *s) {
    while (*s) {
        uart_send_char(*s++);
    }
}

/* =====================================================================
 * GIAO TIẾP LCD 16X2 (PORT 2 DATA)
 * ===================================================================== */
void lcd_cmd(unsigned char cmd) {
    LCD_RS = 0;
    LCD_DATA = cmd;
    LCD_EN = 1;
    delay_ms(1);
    LCD_EN = 0;
    delay_ms(2);
}

void lcd_char(char c) {
    LCD_RS = 1;
    LCD_DATA = c;
    LCD_EN = 1;
    delay_ms(1);
    LCD_EN = 0;
    delay_ms(2);
}

void lcd_string(char *s) {
    while (*s) {
        lcd_char(*s++);
    }
}

void lcd_init(void) {
    delay_ms(20);
    lcd_cmd(0x38); // 8-bit, 2 dòng, font 5x7
    lcd_cmd(0x0C); // Bật hiển thị, tắt con trỏ
    lcd_cmd(0x06); // Tăng con trỏ sang phải
    lcd_cmd(0x01); // Xóa màn hình
    delay_ms(2);
}

void update_lcd_status(void) {
    char str_buf[16];
    char uart_buf[48];
    unsigned char empty_slots = MAX_CAPACITY - current_cars;

    lcd_cmd(0x80); // Dòng 1
    lcd_string("SMART PARKING 4.0");

    lcd_cmd(0xC0); // Dòng 2
    if (current_cars >= MAX_CAPACITY) {
        lcd_string("STATUS: FULL !!!");
        LED_RED = 1;
    } else {
        sprintf(str_buf, "SLOTS: %02d/%02d FREE", (int)empty_slots, (int)MAX_CAPACITY);
        lcd_string(str_buf);
        LED_RED = 0;
    }

    // Báo cáo trạng thái ngược lại cho Máy tính / Web qua UART
    sprintf(uart_buf, "[STATUS] CARS:%u SLOTS:%u\r\n", (unsigned int)current_cars, (unsigned int)empty_slots);
    uart_send_string(uart_buf);
}

/* =====================================================================
 * CHU TRÌNH MỞ BARIE CỔNG VÀO (CHỐNG KẸP XE)
 * ===================================================================== */
void execute_gate_in(void) {
    char log[64];
    if (current_cars >= MAX_CAPACITY) {
        uart_send_string("[ALERT] BAI DAY! TU CHOI XE VAO.\r\n");
        BUZZER = 1;
        LED_RED = 1;
        delay_ms(300);
        BUZZER = 0;
        return;
    }

    ticket_id++;
    current_cars++;
    update_lcd_status();

    sprintf(log, "[GATE-IN] OK! VE:#TK%u | DANG MO BARIE...\r\n", ticket_id);
    uart_send_string(log);

    // Xuất xung mở Barie Vào & Bật đèn xanh
    BARRIER_IN = 1;
    LED_GREEN = 1;

    // Giữ mở và kiểm tra cảm biến chống kẹp xe
    delay_ms(1500); 

    // Đóng Barie an toàn
    BARRIER_IN = 0;
    LED_GREEN = 0;
    uart_send_string("[GATE-IN] BARIE DA DONG AN TOAN.\r\n");
}

/* =====================================================================
 * CHU TRÌNH MỞ BARIE CỔNG RA
 * ===================================================================== */
void execute_gate_out(void) {
    if (current_cars > 0) {
        current_cars--;
        update_lcd_status();

        uart_send_string("[GATE-OUT] THU PHI: 5,000 VND | DANG MO BARIE RA...\r\n");

        BARRIER_OUT = 1;
        delay_ms(1500); // Giữ mở cho xe qua
        BARRIER_OUT = 0;

        uart_send_string("[GATE-OUT] BARIE RA DA DONG AN TOAN.\r\n");
    } else {
        uart_send_string("[GATE-OUT] BAI DANG TRONG, KHONG CO XE RA.\r\n");
    }
}

/* =====================================================================
 * KIỂM TRA LỆNH TỪ MÁY TÍNH / WEB GỬI XUỐNG QUA CỔNG COM (UART RX)
 * ===================================================================== */
void check_uart_commands(void) {
    char cmd;
    if (RI == 1) { // Có dữ liệu từ máy tính gửi tới qua COMPIM
        cmd = SBUF;
        RI = 0; // Xóa cờ nhận

        if (cmd == 'I' || cmd == 'i') {
            // Lệnh xe vào từ Web / Camera AI
            execute_gate_in();
        } 
        else if (cmd == 'O' || cmd == 'o') {
            // Lệnh xe ra từ Web / Camera AI
            execute_gate_out();
        } 
        else if (cmd == 'R' || cmd == 'r') {
            // Lệnh Reset hệ thống
            current_cars = 0;
            update_lcd_status();
            uart_send_string("[SYSTEM] DA RESET BAI XE VE 0.\r\n");
        }
    }
}

/* =====================================================================
 * CHƯƠNG TRÌNH CHÍNH (MAIN LOOP)
 * ===================================================================== */
void main(void) {
    P1 = 0x00; // Tắt ngoại vi
    P3 = 0xFF; // Cảm biến và UART inputs

    uart_init();
    lcd_init();

    uart_send_string("====================================================\r\n");
    uart_send_string("   HE THONG BAI XE 8051 KET NOI COMPIM REAL-TIME   \r\n");
    uart_send_string("====================================================\r\n");

    update_lcd_status();

    while (1) {
        // 1. Lắng nghe lệnh từ Web / Máy tính qua cổng COM ảo (COMPIM)
        check_uart_commands();

        // 2. Lắng nghe cảm biến cơ học trên Proteus (Nút bấm Vào/Ra)
        if (IR_IN_FRONT == 0) {
            delay_ms(20);
            if (IR_IN_FRONT == 0) {
                execute_gate_in();
                while (IR_IN_FRONT == 0); // Chờ nhả nút
            }
        }

        if (IR_OUT_FRONT == 0) {
            delay_ms(20);
            if (IR_OUT_FRONT == 0) {
                execute_gate_out();
                while (IR_OUT_FRONT == 0); // Chờ nhả nút
            }
        }
    }
}
