; ==============================================================================
; CHUONG TRINH ASSEMBLY: HE THONG BAI DO XE THONG MINH CHUYEN DUNG CHO EDSIM51
; Mon hoc: Cong nghe phan mem nhung
; Mo phong: EdSim51 DI (Chay truc tiep tren ban do phan cung co san cua EdSim51)
; ==============================================================================
; BAN DO PHAN CUNG EDSIM51:
; - P3.2 : Nut nhan XE VAO (Khi nhan = muc 0)
; - P3.3 : Nut nhan XE RA  (Khi nhan = muc 0)
; - P1.0 : LED Xanh (Sang khi cho xe vao) [Muc 0 = Sang tren EdSim51]
; - P1.1 : LED Do   (Sang khi bai day xe) [Muc 0 = Sang tren EdSim51]
; - P1.2 : Chan E  dieu khien LCD trong EdSim51
; - P1.3 : Chan RS dieu khien LCD trong EdSim51
; - Port 2: Duong truyen du lieu 8-bit gui lenh va chu cho LCD
; ==============================================================================

    ORG 0000H
    LJMP START

; Dinh nghia cac chan I/O tren EdSim51
BTN_IN      BIT P3.2    ; Nut nhan xe vao
BTN_OUT     BIT P3.3    ; Nut nhan xe ra
LED_GREEN   BIT P1.0    ; Den xanh bao mo cong
LED_RED     BIT P1.1    ; Den do bao bai day
LCD_E       BIT P1.2    ; Chan Enable LCD
LCD_RS      BIT P1.3    ; Chan Register Select LCD

; Bien luu tru
CAR_COUNT   EQU 30H     ; O nho RAM 30H luu so xe hien tai
MAX_SLOTS   EQU 10      ; Suc chua toi da: 10 xe

START:
    ; 1. Khoi tao cac cong
    MOV P1, #0FFH       ; Tat het den LED tren EdSim51 (Active Low)
    SETB BTN_IN         ; Dat chan lam dau vao
    SETB BTN_OUT        ; Dat chan lam dau vao
    MOV CAR_COUNT, #00H ; Ban dau chua co xe nao

    ; 2. Khoi tao man hinh LCD trong EdSim51
    ACALL LCD_INIT
    ACALL DISPLAY_STATUS

; ==============================================================================
; VONG LAP CHINH QUET CAM BIEN (MAIN LOOP)
; ==============================================================================
MAIN_LOOP:
    ; --- KIEM TRA XE VAO ---
    JB BTN_IN, CHECK_EXIT
    ACALL DELAY_DEBOUNCE
    JB BTN_IN, CHECK_EXIT

    ; Co xe vao: Kiem tra bãi đầy chưa
    MOV A, CAR_COUNT
    CJNE A, #MAX_SLOTS, CHO_XE_VAO
    
    ; Neu da day 10 xe: Bat den Do canh bao
    CLR LED_RED
    SJMP CHO_NHA_NUT_IN

CHO_XE_VAO:
    INC CAR_COUNT       ; Tang so xe
    CLR LED_GREEN       ; Bat den Xanh mo cong
    ACALL DISPLAY_STATUS
    ACALL DELAY_LONG    ; Giu cong mo mot luc
    SETB LED_GREEN      ; Dong cong, tat den xanh

CHO_NHA_NUT_IN:
    JNB BTN_IN, $       ; Cho nha nut

    ; --- KIEM TRA XE RA ---
CHECK_EXIT:
    JB BTN_OUT, MAIN_LOOP
    ACALL DELAY_DEBOUNCE
    JB BTN_OUT, MAIN_LOOP

    ; Co xe ra: Kiem tra count > 0
    MOV A, CAR_COUNT
    JZ CHO_NHA_NUT_OUT

    DEC CAR_COUNT       ; Giam so xe
    SETB LED_RED        ; Tat den do (neu truoc do dang day)
    CLR LED_GREEN       ; Mo cong cho xe ra
    ACALL DISPLAY_STATUS
    ACALL DELAY_LONG
    SETB LED_GREEN

CHO_NHA_NUT_OUT:
    JNB BTN_OUT, $      ; Cho nha nut
    SJMP MAIN_LOOP

; ==============================================================================
; CAC CHUONG TRINH CON DIEU KHIEN LCD TRONG EDSIM51
; ==============================================================================
LCD_INIT:
    CLR LCD_RS
    MOV P2, #38H        ; Chế độ 8-bit, 2 dòng
    ACALL LCD_PULSE
    MOV P2, #0CH        ; Bật hiển thị, tắt con trỏ
    ACALL LCD_PULSE
    MOV P2, #01H        ; Xóa màn hình
    ACALL LCD_PULSE
    MOV P2, #06H        ; Tự động tăng con trỏ
    ACALL LCD_PULSE
    RET

LCD_PULSE:
    SETB LCD_E
    ACALL DELAY_SHORT
    CLR LCD_E
    ACALL DELAY_SHORT
    RET

LCD_WRITE_CHAR:
    SETB LCD_RS         ; RS = 1: Ghi du lieu
    MOV P2, A
    ACALL LCD_PULSE
    RET

; Hien thi thong bao len 2 dong LCD
DISPLAY_STATUS:
    ; Dong 1: "PARKING LOT:"
    CLR LCD_RS
    MOV P2, #80H        ; Ve dau dong 1
    ACALL LCD_PULSE

    MOV DPTR, #TXT_TITLE
    ACALL PRINT_STRING

    ; Dong 2: So luong xe
    CLR LCD_RS
    MOV P2, #0C0H       ; Ve dau dong 2
    ACALL LCD_PULSE

    MOV A, CAR_COUNT
    CJNE A, #MAX_SLOTS, HIEN_SO_XE
    
    ; Neu day xe
    MOV DPTR, #TXT_FULL
    ACALL PRINT_STRING
    CLR LED_RED         ; Bat den do
    RET

HIEN_SO_XE:
    SETB LED_RED        ; Tat den do
    MOV DPTR, #TXT_SLOT
    ACALL PRINT_STRING

    ; Chuyen doi so xe tu Hex sang ma ASCII de in len LCD
    MOV A, CAR_COUNT
    MOV B, #10
    DIV AB
    ADD A, #'0'         ; Chu so hang chuc
    ACALL LCD_WRITE_CHAR
    MOV A, B
    ADD A, #'0'         ; Chu so hang don vi
    ACALL LCD_WRITE_CHAR
    RET

PRINT_STRING:
    CLR A
    MOVC A, @A+DPTR
    JZ END_STRING
    ACALL LCD_WRITE_CHAR
    INC DPTR
    SJMP PRINT_STRING
END_STRING:
    RET

; Chuoi ky tu hien thi
TXT_TITLE:  DB 'SMART PARKING', 0
TXT_SLOT:   DB 'CARS IN: ', 0
TXT_FULL:   DB 'STATUS: FULL !!!', 0

; Cac chuong trinh tre (Delay)
DELAY_SHORT:
    MOV R7, #50
    DJNZ R7, $
    RET

DELAY_DEBOUNCE:
    MOV R6, #100
L1: MOV R7, #100
    DJNZ R7, $
    DJNZ R6, L1
    RET

DELAY_LONG:
    MOV R5, #10
L2: ACALL DELAY_DEBOUNCE
    DJNZ R5, L2
    RET

    END
