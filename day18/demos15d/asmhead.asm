; demos boot asm
; TAB=4

VBEMODE	EQU		0x103		; 800 x 600 x 8bit

BOTPAK	EQU		0x00280000	; bootpackのロード先
DSKCAC	EQU		0x00100000	; ディスクキャッシュの場所
DSKCAC0	EQU		0x00008000	; ディスクキャッシュの場所（リアルモード）

; BOOT_INFO関係
CYLS	EQU		0x0ff0		; ブートセクタが設定する
LEDS	EQU		0x0ff1
VMODE	EQU		0x0ff2		; 色数に関する情報，何ビットカラーか
SCRNX	EQU		0x0ff4		; 解像度のX（screen x）
SCRNY	EQU		0x0ff6		; 解像度のY（screen y）
VRAM	EQU		0x0ff8		; グラフィックバッファの開始番地

		ORG		0xc200		; このプログラムがどこに読み込まれるのか

; VBE存在確認

	MOV		AX,0x9000
	MOV		ES,AX
	MOV		DI,0
	MOV		AX,0x4f00
	INT		0x10
	CMP		AX,0x004f		; VBEが存在したらAXが0x004fになる
	JNE		scan320

; VBEのバージョンチェック(VBEのバージョンは2.0以上)

	MOV		AX,[ES:DI+4]
	CMP		AX,0x0200
	JB		scan320			; if(AX < 0x0200) goto scan320

; 画面モード情報を得る

	MOV		CX,VBEMODE
	MOV		AX,0x4f01
	INT		0x10
	CMP		AX,0x004f
	JNE		scan320

; 画面モード情報の確認

	CMP		BYTE [ES:DI+0x19],8
	JNE		scan320
	CMP		BYTE [ES:DI+0x1b],4
	JNE		scan320
	MOV		AX,[ES:DI+0x00]
	AND		AX,0x0080
	JZ		scan320				; モード属性のbit7が0だったので諦める

; 画面モードの切り替え
	MOV		BX,VBEMODE+0x4000
	MOV		AX,0x4f02
	INT		0x10
	MOV		BYTE	[VMODE],8	; 画面モードをメモする（C言語が参照する）
	MOV		AX,[ES:DI+0x12]
	MOV		[SCRNX],AX
	MOV		AX,[ES:DI+0x14]
	MOV		[SCRNY],AX
	MOV 	EAX,[ES:DI+0x28]
	MOV		[VRAM],EAX
	JMP		keystatus

scan320:
	MOV		AL,0x13				; VGAグラフィックス、320x200x8bitカラー
	MOV		AH,0x00
	INT		0x10
	MOV		BYTE [VMODE],8
	MOV 	WORD [SCRNX],320
	MOV 	WORD [SCRNY],200
	MOV		DWORD [VRAM],0x000a0000

; キーボードのLED状態をBIOSに教えてもある

keystatus:
		MOV		AH,0x02
		INT		0x16		; Keyborad BIOS
		MOV		[LEDS],AL

; PICが一切の割り込みを受け付けないようにする
;	AT互換機の仕様では、PICの初期化をするなら、
;	こいつをCLI前にやっておかないと、たまにハングアップする
;	PICの初期化はあとでやる

		MOV		AL,0xff
		OUT		0x21,AL
		NOP						; OUT命令を連続させるとうまくいかない機種があるらしいので
		OUT		0xa1,AL

		CLI						; さらにCPUレベルでも割り込み禁止

; CPUから1MB以上のメモリにアクセスできるように、A20GATEを設定

		CALL	waitkbdout
		MOV		AL,0xd1
		OUT		0x64,AL
		CALL	waitkbdout
		MOV		AL,0xdf			; enable A20
		OUT		0x60,AL
		CALL	waitkbdout

; プロテクトモード移行

; [INSTRSET "i486p"]				; 486の命令まで使いたいという記述

		LGDT	[GDTR0]			; 暫定GDTを設定
		MOV		EAX,CR0
		AND		EAX,0x7fffffff	; bit31を0にする（ページング禁止のため）
		OR		EAX,0x00000001	; bit0を1にする（プロテクトモード移行のため）
		MOV		CR0,EAX
		JMP		pipelineflush
pipelineflush:
		MOV		AX,1*8			;  読み書き可能セグメント32bit
		MOV		DS,AX
		MOV		ES,AX
		MOV		FS,AX
		MOV		GS,AX
		MOV		SS,AX

; bootpackの転送

		MOV		ESI,bootpack	; 転送元
		MOV		EDI,BOTPAK		; 転送先
		MOV		ECX,512*1024/4
		CALL	memcpy

; ついでにディスクデータも本来の位置へ転送

; まずはブートセクタから

		MOV		ESI,0x7c00		; 転送元
		MOV		EDI,DSKCAC		; 転送先
		MOV		ECX,512/4
		CALL	memcpy

; 残り全部

		MOV		ESI,DSKCAC0+512	; 転送元
		MOV		EDI,DSKCAC+512	; 転送先
		MOV		ECX,0
		MOV		CL,BYTE [CYLS]
		IMUL	ECX,512*18*2/4	; シリンダ数からバイト数/4に変換
		SUB		ECX,512/4		; IPLの分だけ差し引く
		CALL	memcpy

; asmheadでしなければいけないことは全部し終わったので、
;	あとはbootpackに任せる

; bootpackの起動

		MOV		EBX,BOTPAK
		MOV		ECX,[EBX+16]
		ADD		ECX,3			; ECX += 3;
		SHR		ECX,2			; ECX /= 4;
		JZ		skip			; 転送するべきものがない
		MOV		ESI,[EBX+20]	; 転送元
		ADD		ESI,EBX
		MOV		EDI,[EBX+12]	; 転送先
		CALL	memcpy
skip:
		MOV		ESP,[EBX+12]	; スタック初期値
		JMP		DWORD 2*8:0x0000001b

waitkbdout:
		IN		AL,0x64
		AND		AL,0x02
		IN		AL,0x06			; から読み（受信バッファが悪さをしないように）
		JNZ		waitkbdout		; ANDの結果が0でなければwaitkbdoutへ
		RET

memcpy:
		MOV		EAX,[ESI]
		ADD		ESI,4
		MOV		[EDI],EAX
		ADD		EDI,4
		SUB		ECX,1
		JNZ		memcpy			; 引き算した結果が0でなければmemcpyへ
		RET
; memcpyはアドレスサイズプリフィクスを入れ忘れなければ、ストリング命令でも書ける

		ALIGNB	16,	DB 	0
GDT0:
		TIMES	8	DB	0				; ヌルセレクタ
		DW		0xffff,0x0000,0x9200,0x00cf	; 読み書き可能セグメント32bit
		DW		0xffff,0x0000,0x9a28,0x0047	; 実行可能セグメント32bit（bootpack用）

		DW		0
GDTR0:
		DW		8*3-1
		DD		GDT0

		ALIGNB	16,	DB	0
bootpack: