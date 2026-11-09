/*
 * =====================================================================
 * HỆ THỐNG QUẢN LÝ BÃI ĐỖ XE THÔNG MINH - 8051 (AT89C51)
 * Học phần: Công nghệ phần mềm nhúng
 * =====================================================================
 * SƠ ĐỒ KẾT NỐI CHÂN:
 * 1. Màn hình LCD 16x2:
 *    - Data D0 - D7: Nối vào P2.0 - P2.7 (Port 2)
 *    - Chân RS: Nối vào P3.5
 *    - Chân RW: Nối vào GND
 *    - Chân E : Nối vào P3.6
 *
 * 2. Cảm biến / Nút bấm:
 *    - Nút Xe Vào (SENSOR_IN) : Nối vào P3.2 và một đầu nối GND
 *    - Nút Xe Ra  (SENSOR_OUT): Nối vào P3.3 và một đầu nối GND
 *
 * 3. Thiết bị đầu ra (Đèn, còi, Barie):
 *    - LED Xanh (Cho vào/Mở cổng): P1.0
 *    - LED Đỏ   (Bãi đầy - FULL) : P1.1
 *    - Còi Buzzer                : P1.2
 *    - Động cơ Servo / Barie     : P1.3
 * =====================================================================
 */

#include <reg51.h>
#include <stdio.h>

// Định nghĩa các chân điều khiển ngoại vi
sbit SENSOR_IN  = P3^2;   // Nút bấm mô phỏng xe vào (Ấn = mức 0)
sbit SENSOR_OUT = P3^3;   // Nút bấm mô phỏng xe ra  (Ấn = mức 0)

sbit LED_GREEN  = P1^0;   // Đèn xanh: sáng khi mở cổng
sbit LED_RED    = P1^1;   // Đèn đỏ: sáng khi bãi xe đầy
sbit BUZZER     = P1^2;   // Còi cảnh báo
sbit BARRIER    = P1^3;   // Chân tín hiệu điều khiển Barie

// Định nghĩa các chân giao tiếp LCD 16x2
sbit LCD_RS = P3^5;
sbit LCD_EN = P3^6;
#define LCD_DATA P2       // Dùng Port 2 làm đường truyền dữ liệu LCD (không cần trở kéo)

#define MAX_SLOTS 10      // Sức chứa tối đa của bãi đỗ xe là 10 xe
unsigned char car_count = 0; // Biến đếm số lượng xe hiện tại

/* ----------------- CÁC HÀM XỬ LÝ DELAY ----------------- */
void delay_ms(unsigned int ms) {
    unsigned int i, j;
    for (i = 0; i < ms; i++) {
        for (j = 0; j < 120; j++); // Tương đối chuẩn cho thạch anh 11.0592MHz hoặc 12MHz
    }
}

/* ----------------- CÁC HÀM ĐIỀU KHIỂN LCD ----------------- */
void lcd_cmd(unsigned char cmd) {
    LCD_RS = 0;          // RS = 0: gửi lệnh điều khiển
    LCD_DATA = cmd;
    LCD_EN = 1;
    delay_ms(1);
    LCD_EN = 0;
    delay_ms(2);
}

void lcd_char(char c) {
    LCD_RS = 1;          // RS = 1: gửi ký tự hiển thị
    LCD_DATA = c;
    LCD_EN = 1;
    delay_ms(1);
    LCD_EN = 0;
    delay_ms(2);
}

void lcd_string(char *str) {
    while (*str) {
        lcd_char(*str++);
    }
}

void lcd_init() {
    delay_ms(20);
    lcd_cmd(0x38); // Chế độ 8-bit, 2 dòng, font 5x7
    lcd_cmd(0x0C); // Bật màn hình, tắt con trỏ nhấp nháy
    lcd_cmd(0x06); // Tự động tăng con trỏ sang phải
    lcd_cmd(0x01); // Xóa màn hình
    delay_ms(2);
}

/* ----------------- CẬP NHẬT TRẠNG THÁI RA MÀN HÌNH ----------------- */
void update_display() {
    char buffer[16];
    unsigned char empty_slots;

    // Dòng 1: Tiêu đề bãi xe
    lcd_cmd(0x80); // Đưa con trỏ về đầu dòng 1
    lcd_string("BAI XE TU DONG ");

    // Dòng 2: Trạng thái và số chỗ trống
    lcd_cmd(0xC0); // Đưa con trỏ về đầu dòng 2
    if (car_count >= MAX_SLOTS) {
        lcd_string("FULL! HET CHO   ");
        LED_RED = 1;   // Bật đèn đỏ báo hết chỗ
    } else {
        empty_slots = MAX_SLOTS - car_count;
        sprintf(buffer, "Trong: %02d/%02d xe ", (int)empty_slots, (int)MAX_SLOTS);
        lcd_string(buffer);
        LED_RED = 0;   // Tắt đèn đỏ
    }
}

/* ----------------- CHU TRÌNH MỞ & ĐÓNG BARIE ----------------- */
void open_gate() {
    LED_GREEN = 1;      // Bật đèn xanh (cho phép xe đi)
    BARRIER = 1;        // Mở Barie (Servo quay / Động cơ chạy)
    delay_ms(1500);     // Giữ Barie mở trong 1.5 giây để xe đi qua
    BARRIER = 0;        // Đóng Barie
    LED_GREEN = 0;      // Tắt đèn xanh
}

/* ----------------- CẢNH BÁO KHI BÃI ĐẦY ----------------- */
void warning_full() {
    unsigned char i;
    for (i = 0; i < 3; i++) {
        BUZZER = 1;
        LED_RED = 1;
        delay_ms(150);
        BUZZER = 0;
        LED_RED = 0;
        delay_ms(150);
    }
    LED_RED = 1; // Giữ đèn đỏ bật tiếp vì bãi vẫn đang đầy
}

/* ----------------- CHƯƠNG TRÌNH CHÍNH ----------------- */
void main() {
    // Khởi tạo trạng thái ban đầu cho các chân
    P1 = 0x00;          // Tắt hết LED, còi, barie ban đầu
    SENSOR_IN = 1;      // Cài đặt chân P3.2 làm Input (mức 1)
    SENSOR_OUT = 1;     // Cài đặt chân P3.3 làm Input (mức 1)

    lcd_init();         // Khởi động màn hình LCD
    update_display();   // Hiển thị trạng thái khởi tạo (10/10 chỗ trống)

    while (1) {
        // --- 1. XỬ LÝ KHI CÓ XE VÀO (SENSOR_IN = 0) ---
        if (SENSOR_IN == 0) {
            delay_ms(20); // Chống dội phím (Debounce)
            if (SENSOR_IN == 0) {
                if (car_count < MAX_SLOTS) {
                    car_count++;        // Tăng số xe trong bãi
                    update_display();   // Cập nhật LCD ngay
                    open_gate();        // Mở barie
                } else {
                    // Nếu bãi đã đầy mà xe vẫn bấm vào:
                    warning_full();
                }
                while (SENSOR_IN == 0); // Đợi xe đi qua hẳn (nhả nút)
            }
        }

        // --- 2. XỬ LÝ KHI CÓ XE RA (SENSOR_OUT = 0) ---
        if (SENSOR_OUT == 0) {
            delay_ms(20); // Chống dội phím (Debounce)
            if (SENSOR_OUT == 0) {
                if (car_count > 0) {
                    car_count--;        // Giảm số xe trong bãi
                    update_display();   // Cập nhật LCD
                    open_gate();        // Mở barie cho xe ra
                }
                while (SENSOR_OUT == 0); // Đợi xe đi qua hẳn (nhả nút)
            }
        }
    }
}
