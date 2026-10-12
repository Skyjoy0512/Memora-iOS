"""Render proposal-only wireframes; never reads or changes the app's records."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/design/project-phase1"
OUT.mkdir(parents=True, exist_ok=True)
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
SCALE = 2


class Phone:
    def __init__(self, dark=False):
        self.bg = "#0B0B0B" if dark else "#FFFFFF"
        self.fg = "#FFFFFF" if dark else "#0B0B0B"
        self.sub = "#A3A3A3" if dark else "#737373"
        self.card = "#202020" if dark else "#F5F5F5"
        self.line = "#353535" if dark else "#E5E5E5"
        self.image = Image.new("RGB", (390*SCALE, 844*SCALE), self.bg)
        self.d = ImageDraw.Draw(self.image)
        self.text(22, 18, "9:41", 15)
        self.rect(139, 10, 251, 38, "#000000", 16)
        self.text(324, 18, "LTE", 12)

    def rect(self, x, y, r, b, fill=None, radius=0, outline=None):
        box = tuple(int(v*SCALE) for v in (x,y,r,b))
        self.d.rounded_rectangle(box, radius=radius*SCALE,
                                 fill=fill, outline=outline, width=SCALE)

    def text(self, x, y, value, size=17, secondary=False):
        self.d.text((x*SCALE,y*SCALE), value,
                    font=ImageFont.truetype(FONT, size*SCALE),
                    fill=self.sub if secondary else self.fg)

    def icon(self, x, y, kind="folder", size=18):
        # Diagram marks only; production uses the existing MemoraIcon catalog.
        if kind == "folder":
            self.rect(x,y+4,x+size,y+size,outline=self.fg,radius=2)
            self.rect(x,y,x+size*.45,y+4,outline=self.fg,radius=1)
        elif kind == "task":
            self.d.ellipse((x*SCALE,y*SCALE,(x+size)*SCALE,(y+size)*SCALE),
                           outline=self.sub, width=SCALE)
        elif kind == "record":
            for n,h in enumerate((6,12,18,10,6)):
                a=(x+n*3)*SCALE; cy=(y+9)*SCALE
                self.d.line((a,cy-h*SCALE/2,a,cy+h*SCALE/2),fill=self.sub,width=2*SCALE)
        elif kind == "document":
            self.rect(x,y,x+size*.8,y+size,outline=self.sub,radius=1)
            for offset in (6,10,14):
                self.d.line(((x+3)*SCALE,(y+offset)*SCALE,(x+size*.65)*SCALE,(y+offset)*SCALE),fill=self.sub,width=SCALE)

    def toolbar(self, detail=False, name="新製品ローンチ", after=False):
        self.rect(16,52,60,96,self.card,22, self.line)
        if detail:
            self.d.line((43*SCALE,63*SCALE,32*SCALE,74*SCALE,43*SCALE,85*SCALE),fill=self.fg,width=2*SCALE)
        else:
            self.text(30,61,"≡",24)
        self.rect(330,52,374,96,self.card,22,self.line)
        self.text(342,61,"…" if detail else "作成",14)
        if not detail:
            self.text(284,64,"検索",13)
            self.text(16,114,"ライブラリ",32)
            self.rect(91,163,299,207,self.card,22,self.line)
            self.text(110,178,"ファイル",13,True)
            self.rect(196,167,295,203,self.line,18)
            self.text(203,178,"プロジェクト",13)
        elif not after:
            self.text(111,66,name,15)
            self.text(292,66,"共有",13)
        else:
            self.text(16,114,name,34)

    def footer(self, scope=False):
        self.rect(0,706,390,844,self.bg)
        self.rect(28,714,362,758,self.card,22,self.line)
        self.text(44,728,"このプロジェクトに質問" if scope else "Memoraに質問",14,True)
        self.text(331,727,"音声",11)
        self.rect(16,774,312,826,self.card,26,self.line)
        self.text(38,793,"ライブラリ   ジャーナル   Ask AI",12)
        self.rect(326,774,378,826,self.card,26,self.line)
        self.text(343,783,"＋",25)
        self.rect(140,834,250,838,self.fg,2)

    def heading(self, y, title, trailing=""):
        self.text(16,y,title,15,True)
        if trailing:
            self.text(268,y,trailing,13,True)

    def row(self,y,title,metadata,kind="folder"):
        self.icon(16,y+18,kind)
        self.text(48,y+10,title,17)
        self.text(48,y+36,metadata,13,True)
        if kind == "folder": self.text(348,y+17,"…",16,True)
        self.d.line((48*SCALE,(y+71)*SCALE,374*SCALE,(y+71)*SCALE),fill=self.line,width=SCALE)


NAMES = ["新製品ローンチ","採用活動","顧客インタビュー","住まいの計画","週次ミーティング",
         "Webサイトの改善","旅の準備","学習ノート","チーム定例","営業資料"]


def list_phone(count, after, dark=False):
    p=Phone(dark); p.toolbar()
    if count == 0:
        p.text(58,300,"プロジェクトはまだありません" if after else "最初のプロジェクトを作成",17)
        p.text(59,338,"右上の「作成」から始められます。" if after else "テーマごとに記録とタスクをまとめる",13,True)
        if not after:
            p.rect(78,382,312,426,p.fg,16)
            # Current empty state duplicates the toolbar creation action.
            p.d.text((95*SCALE,395*SCALE),"プロジェクトを作成",
                     font=ImageFont.truetype(FONT,15*SCALE),fill=p.bg)
    elif after:
        p.heading(224,f"プロジェクト · {count}件","並べ替え")
        for n in range(min(count,7)):
            p.row(255+n*72, NAMES[n] if count<100 else f"プロジェクト {n+1:03d}",
                  "記録 0件" if count==1 else f"記録 {12-n}件 · 最新記録 10/{12-n}")
    else:
        y=224
        if count>3:
            p.heading(y,"最近使用")
            p.rect(16,y+30,201,y+94,p.card,16)
            p.rect(211,y+30,374,y+94,p.card,16)
            p.text(30,y+49,NAMES[0] if count<100 else "プロジェクト 001",15)
            p.text(225,y+49,NAMES[1] if count<100 else "プロジェクト 002",15)
            y+=120
        p.heading(y,"すべてのプロジェクト",f"{count}件")
        for n in range(min(count,5)):
            cy=y+32+n*128
            p.rect(16,cy,374,cy+116,p.card,20)
            p.rect(32,cy+16,76,cy+60,p.line,14); p.icon(44,cy+29)
            p.text(90,cy+20,NAMES[n] if count<100 else f"プロジェクト {n+1:03d}",17)
            if count>1:p.text(90,cy+44,f"最新の記録 10/{12-n}",12,True)
            p.text(340,cy+16,"…",17,True)
            p.text(32,cy+83,"記録 0件 · 未完了タスク 0件" if count==1 else f"記録 {12-n}件 · 未完了タスク {max(0,3-n)}件",14,True)
    p.footer(); return p.image


def detail_phone(state,after,dark=False):
    empty=state=="empty"
    total=0 if empty else (100 if state=="many" else 12)
    tasks=0 if empty else (24 if state=="many" else 5)
    p=Phone(dark); p.toolbar(True,after=after)
    if after:
        p.text(16,162,f"記録 {total}件 · 未完了タスク {tasks}件",13,True)
        if empty:
            p.text(16,246,"最初の記録を追加",20)
            p.text(16,286,"右下の＋から録音・音声取り込み。",14,True)
            p.text(16,312,"保存済みの記録も移動できます。",14,True)
            p.text(16,366,"ライブラリから記録を移動",16)
        else:
            p.heading(209,"次にやること",f"すべて見る {tasks}件")
            for n,title in enumerate(("見積書を確認する","次回の打ち合わせを設定","議事録を共有する")):
                p.icon(16,249+n*58,"task",20)
                p.text(52,247+n*58,title,17)
                if n==0:p.text(52,272+n*58,"期限 10/14",13,True)
            p.heading(445,"最近の記録",f"すべて見る {total}件")
            for n,title in enumerate(("仕様の確認","ローンチ準備ミーティング","初回打ち合わせ")):
                p.row(476+n*72,title,f"10/{12-n} · オンライン会議","record")
            p.heading(720,"関連資料","すべて見る 2件")
            p.row(751,"ローンチ準備メモ","文書 · 更新 10/12","record")
    else:
        p.rect(32,130,84,182,p.card,16);p.icon(48,146, size=20)
        p.text(96,130,"新製品ローンチ",22)
        p.text(96,160,"記録を追加して始めましょう" if empty else "このプロジェクトの記録とタスク",12,True)
        p.text(32,205,f"記録 {total}件 · 未完了タスク {tasks}件",14,True)
        p.rect(32,244,190,295,p.fg,26)
        p.d.text((63*SCALE,262*SCALE),"録音を開始",font=ImageFont.truetype(FONT,15*SCALE),fill=p.bg)
        p.rect(202,244,358,295,p.line,26);p.text(231,262,"インポート",15)
        p.text(32,343,"プロジェクトに質問",17)
        p.text(32,371,"このプロジェクトの記録をもとに回答",12,True)
        p.heading(444,"ファイル",f"{total}件 · 新しい順")
        if empty:
            p.text(32,487,"まだ記録がありません",17)
            p.text(32,522,"録音・インポート、既存の記録を追加。",13,True)
            p.text(32,570,"ライブラリから記録を追加",15)
            p.heading(633,"進行中のタスク · 0件")
            p.text(32,672,"未完了のタスクはありません",14,True)
        else:
            for n,title in enumerate(("仕様の確認","ローンチ準備ミーティング")):
                cy=477+n*184
                p.rect(16,cy,374,cy+168,p.card,20)
                p.text(32,cy+82,title,18)
                p.text(32,cy+120,"10/12 · 30:00",13,True)
    p.footer(True); return p.image


def board(filename,title,left,right,note):
    im=Image.new("RGB",(910*SCALE,970*SCALE),"#F7F7F7")
    d=ImageDraw.Draw(im)
    def txt(x,y,t,size=16):
        d.text((x*SCALE,y*SCALE),t,font=ImageFont.truetype(FONT,size*SCALE),fill="#0B0B0B")
    txt(32,12,title,21);txt(32,46,"Before：現行コードの模式図",13);txt(486,46,"After：承認前の推奨案",13)
    im.paste(left,(32*SCALE,78*SCALE));im.paste(right,(486*SCALE,78*SCALE))
    txt(32,938,note,12)
    im.save(OUT/filename,optimize=True)


for count in (0,1,10,100):
    board(f"list-{count}.png",f"プロジェクト一覧 / {count}件 / Light",
          list_phone(count,False),list_phone(count,True),"架空データのワイヤーフレーム。Glass・実機・画面遷移の検証画像ではありません。")
for state,title in (("empty","空状態"),("normal","通常状態"),("many","100記録・24タスク")):
    board(f"detail-{state}.png",f"プロジェクト詳細 / {title} / Light",
          detail_phone(state,False),detail_phone(state,True),"関連資料は最近の記録の下。全件は同じ画面で展開。表示例は実データではありません。")
board("list-dark.png","プロジェクト一覧 / 10件 / Dark",list_phone(10,False,True),list_phone(10,True,True),"位置を示す模式図です。ネイティブGlassは承認後のSwiftUIで別途確認します。")
board("detail-dark.png","プロジェクト詳細 / 通常状態 / Dark",detail_phone("normal",False,True),detail_phone("normal",True,True),"本文17pt相当・補助13pt相当。文字を小さくして密度を上げる案ではありません。")

# A separate scrolled state makes document access reviewable without shrinking rows.
before=Phone();before.toolbar(True)
before.heading(132,"進行中のタスク · 5件")
for n,title in enumerate(("見積書を確認する","次回の打ち合わせを設定","議事録を共有する","担当範囲を確認する","日程を確定する")):
    before.row(164+n*72,title,"期限 10/14","task")
before.text(16,589,"資料はサイドメニューから閲覧",14,True);before.footer(True)
after=Phone();after.toolbar(True);after.rect(274,52,328,96,after.bg);after.heading(132,"最近の記録","すべて見る 12件")
for n,title in enumerate(("仕様の確認","ローンチ準備ミーティング","初回打ち合わせ")):
    after.row(164+n*72,title,f"10/{12-n} · オンライン会議","record")
after.heading(421,"関連資料","すべて見る 2件")
after.row(453,"ローンチ準備メモ","文書 · 更新 10/12","document")
after.row(525,"提案資料","スライド · 更新 10/10","document")
after.text(16,626,"AI質問は録音・タスクが対象です。",13,True);after.footer(True)
board("detail-documents.png","詳細のスクロール後 / 関連資料の導線",before.image,after.image,"資料の表示は任意の承認対象。本文検索・新規RAG・資料スコープは追加しません。")
print(f"Rendered 10 comparison boards to {OUT}")
