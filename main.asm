; =====================================================================
; CHUONG TRINH ASSEMBLY: HE THONG BAI DO XE THONG MINH - 8051 (AT89C51)
; =====================================================================
    ORG 0000H
    LJMP MAIN

; Dinh nghia cac chan giao tiep
SENSOR_IN   BIT P3.2   ; Cam bien / Nut an xe vao
SENSOR_OUT  BIT P3.3   ; Cam bien / Nut an xe ra
LED_GREEN   BIT P1.0   ; Den xanh bao mo cong
LED_RED     BIT P1.1   ; Den do bao day cho
BUZZER      BIT P1.2   ; Coi chip canh bao
BARRIER     BIT P1.3   ; Tin hieu dieu khien Barie

; O nho RAM luu tru
COUNT_CAR   EQU 30H    ; Bien dem so xe hien co trong bai
MAX_SLOTS   EQU 10     ; Suc chua toi da: 10 xe

MAIN:
    ; Khoi tao cac cong
    MOV P1, #00H       ; Tat cac thiet bi ngoai vi
    SETB SENSOR_IN     ; Dat chan P3.2 lam input
    SETB SENSOR_OUT    ; Dat chan P3.3 lam input
    MOV COUNT_CAR, #0  ; Ban dau chua co xe nao

MAIN_LOOP:
    ; --- 1. KIEM TRA XE VAO ---
    JB SENSOR_IN, CHECK_OUT ; Neu SENSOR_IN = 1 (chua co xe) thi kiem tra xe ra
    ACALL DELAY_20MS        ; Chong doi phim
    JB SENSOR_IN, CHECK_OUT
    
    ; Co xe muon vao: Kiem tra bãi đầy chưa (so sanh voi MAX_SLOTS)
    MOV A, COUNT_CAR
    CJNE A, #MAX_SLOTS, CHO_PHEP_VAO
    
    ; Neu da du 10 xe -> Keu coi canh bao
    ACALL CANH_BAO_COI
    SJMP CHO_NHA_NUT_IN

CHO_PHEP_VAO:
    INC COUNT_CAR           ; Tang so xe len 1
    ACALL MO_DONG_BARIE     ; Mo cong cho xe vao

CHO_NHA_NUT_IN:
    JNB SENSOR_IN, $        ; Doi cho den khi xe qua han (nha nut)

    ; --- 2. KIEM TRA XE RA ---
CHECK_OUT:
    JB SENSOR_OUT, CAP_NHAT_DEN
    ACALL DELAY_20MS
    JB SENSOR_OUT, CAP_NHAT_DEN
    
    ; Co xe ra: Kiem tra xem trong bai co xe nao khong
    MOV A, COUNT_CAR
    JZ CHO_NHA_NUT_OUT      ; Neu Count = 0 thi khong giam
    DEC COUNT_CAR           ; Giam so xe di 1
    ACALL MO_DONG_BARIE     ; Mo cong cho xe ra

CHO_NHA_NUT_OUT:
    JNB SENSOR_OUT, $       ; Doi nha nut xe ra

    ; --- 3. CAP NHAT TRANG THAI DEN BAO ---
CAP_NHAT_DEN:
    MOV A, COUNT_CAR
    CJNE A, #MAX_SLOTS, CHUA_FULL
    SETB LED_RED            ; Bãi đầy: Bat den do
    SJMP MAIN_LOOP

CHUA_FULL:
    CLR LED_RED             ; Chua day: Tat den do
    SJMP MAIN_LOOP

; =====================================================================
; CAC CHUONG TRINH CON (SUBROUTINES)
; =====================================================================

; Chuong trinh con mo va dong Barie
MO_DONG_BARIE:
    SETB LED_GREEN          ; Bat den xanh
    SETB BARRIER            ; Mo Barie
    ACALL DELAY_1S          ; Giu trong 1 giay
    CLR BARRIER             ; Ha Barie
    CLR LED_GREEN           ; Tat den xanh
    RET

; Chuong trinh con canh bao coi bip
CANH_BAO_COI:
    SETB BUZZER
    ACALL DELAY_200MS
    CLR BUZZER
    ACALL DELAY_200MS
    RET

; Cac ham tao do tre (Delay)
DELAY_20MS:
    MOV R6, #40
D1: MOV R7, #250
    DJNZ R7, $
    DJNZ R6, D1
    RET

DELAY_200MS:
    MOV R5, #2
D2: ACALL DELAY_100MS
    DJNZ R5, D2
    RET

DELAY_1S:
    MOV R5, #10
D3: ACALL DELAY_100MS
    DJNZ R5, D3
    RET

DELAY_100MS:
    MOV R6, #200
D4: MOV R7, #250
    DJNZ R7, $
    DJNZ R6, D4
    RET

    END
