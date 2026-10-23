"""Rebuild the original, deterministic pixel artwork. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets"
OUT.mkdir(exist_ok=True)
rng = random.Random(72)
im = Image.new("RGB", (544, 368), "#8fae75")
d = ImageDraw.Draw(im)

def rect(box, color): d.rectangle(box, fill=color)
def line(points, color, width=1): d.line(points, fill=color, width=width)

# Grass: little tufts, warm scattered stones, and clover.
for y in range(0, 368, 16):
    for x in range(0, 544, 16):
        rect((x, y, x+15, y+15), rng.choice(["#91ae76", "#95b27a", "#8fac73", "#92af77"]))
for _ in range(2000):
    x, y = rng.randrange(544), rng.randrange(368)
    line([(x, y), (x+1, y-2)], rng.choice(["#a6bf86", "#799e66", "#b0c48a"]))

def path(box):
    rect(box, "#b9a378")
    x0,y0,x1,y1=box
    rect((x0+1,y0+1,x1-1,y1-1), "#d7c399")
    for _ in range(max(1,(x1-x0)*(y1-y0)//45)):
        x,y=rng.randint(x0+2,x1-2),rng.randint(y0+2,y1-2)
        rect((x,y,x+1,y),rng.choice(["#c7b58d","#e4d3af","#cebb92"]))

path((30,128,513,151))
path((37,208,412,230))
path((259,108,282,337))
path((76,111,99,333))
path((422,110,445,278))
path((198,224,217,335))
path((326,224,345,335))
path((34,310,415,333))
path((370,266,448,283))

# Broad central courtyard with paving joints.
rect((244,145,339,202), "#b1ac91")
rect((246,147,337,200), "#c7c2a5")
for y in range(148,201,8): line([(246,y),(337,y)], "#bab69b")
for x in range(248,338,12): line([(x,148),(x,200)], "#bab69b")

def flowerbed(x,y,w=24):
    rect((x,y,x+w,y+9),"#6c8558")
    rect((x+1,y+1,x+w-1,y+7),"#7c694c")
    for xx in range(x+3,x+w-1,5):
        line([(xx,y+6),(xx,y+2)],"#657c4d")
        col=rng.choice(["#e3b893","#f1d39b","#c98e8a","#eee2b2"])
        rect((xx-1,y+1,xx+1,y+3),col)

def bench(x,y):
    rect((x+1,y+7,x+29,y+10),"#739461")
    rect((x+3,y+5,x+4,y+9),"#594e3d")
    rect((x+24,y+5,x+25,y+9),"#594e3d")
    rect((x,y,x+27,y+3),"#695440")
    rect((x+1,y,x+26,y),"#c6a16a")
    rect((x,y+5,x+27,y+6),"#b88c56")
    line([(x+1,y+2),(x+26,y+2)],"#a67c4c")

bench(96,160)
bench(320,160)
bench(388,290)
for x,y,w in [(57,117,33),(157,118,39),(291,118,34),(376,118,23),(111,227,24),(226,273,20),(350,313,24)]: flowerbed(x,y,w)

# The crescent pond, reeds, lily pads and small timber viewing deck.
d.ellipse((445,237,520,322), fill="#6f905e")
d.ellipse((449,240,517,318), fill="#dfc89a")
d.polygon([(461,241),(491,241),(508,252),(516,275),(509,298),(490,313),(465,310),(452,291),(451,266)],fill="#527e80")
d.polygon([(463,245),(490,245),(505,256),(511,275),(504,295),(487,307),(466,304),(457,288),(456,268)],fill="#78a7a1")
for _ in range(42):
    x,y=rng.randint(462,500),rng.randint(253,299)
    line([(x,y),(x+rng.randint(2,6),y)],rng.choice(["#94bdb0","#65938e"]))
for x,y in [(463,275),(493,290),(481,251)]:
    d.ellipse((x,y,x+7,y+3),fill="#547a55")
    rect((x+3,y-1,x+4,y),"#e2b4a1")
rect((431,268,465,281),"#655c46")
for x in range(433,464,4): rect((x,268,x+2,280),"#b49160")
for x in (432,461): rect((x,265,x+2,283),"#796044")

def books(x,y,w):
    rect((x,y,x+w,y+17),"#594b40")
    for yy in (y+2,y+10):
        for xx in range(x+2,x+w-1,3):
            h=rng.randint(4,6)
            rect((xx,yy+6-h,xx+1,yy+6),rng.choice(["#8a9d83","#bc795f","#d8bb7f","#8fabb0","#c1a291"]))
    line([(x,y+8),(x+w,y+8)],"#b48c60")
    line([(x,y+17),(x+w,y+17)],"#c49d6b")

def table(x,y,w=18,h=10):
    rect((x+2,y+3,x+w+2,y+h+3),"#8f785b")
    rect((x,y,x+w,y+h),"#77583f")
    rect((x+1,y+1,x+w-1,y+h-2),"#c69e6d")
    line([(x+2,y+3),(x+w-2,y+3)],"#d7b681")

def chair(x,y):
    rect((x,y,x+6,y+7),"#785d43")
    rect((x+1,y+1,x+5,y+4),"#b88b59")

def plant(x,y):
    rect((x-3,y,x+3,y+5),"#986f53")
    rect((x-4,y-1,x+4,y),"#c29a6c")
    d.ellipse((x-5,y-9,x+2,y-2),fill="#587453")
    d.ellipse((x-1,y-11,x+5,y-3),fill="#789366")
    rect((x,y-7,x+1,y-1),"#95a977")

def house(tx,ty,tw,th,kind):
    x,y,w,h=tx*16,ty*16,tw*16,th*16
    # A low roof at the rear and a cutaway floor reveal life inside.
    rect((x+3,y+6,x+w+4,y+h+4),"#718662")
    rect((x,y,x+w-1,y+h-1),"#675442")
    rect((x+2,y+2,x+w-3,y+h-3),"#e7d5ab")
    rect((x+5,y+22,x+w-6,y+h-6),"#c9ac7b")
    for yy in range(y+24,y+h-5,5):
        line([(x+5,yy),(x+w-6,yy)],"#b99a6c")
        for xx in range(x+9+(yy%3)*7,x+w-6,23): line([(xx,yy-4),(xx,yy)],"#b99a6c")
    rect((x-2,y-3,x+w+1,y+20),"#854e3b")
    for yy in range(y-2,y+19,4):
        line([(x-1,yy),(x+w,yy)],"#b97552")
        for xx in range(x+(yy%3)*3,x+w,9): line([(xx,yy),(xx-2,yy+3)],"#995d44")
    line([(x-1,y-4),(x+w,y-4)],"#d19a6c",2)
    rect((x+6,y+1,x+13,y+12),"#b99c7b")
    rect((x+7,y,x+12,y+2),"#e2ccb0")
    # Front sandstone wall with open entry and blue-green windows.
    rect((x,y+h-12,x+w-1,y+h-1),"#d6c199")
    line([(x,y+h-12),(x+w-1,y+h-12)],"#f1ddb5")
    for xx in range(x+8,x+w-14,22):
        rect((xx,y+h-10,xx+11,y+h-3),"#887c61")
        rect((xx+1,y+h-9,xx+10,y+h-4),"#799894")
        line([(xx+5,y+h-9),(xx+5,y+h-3)],"#d9c9a4")
    door_x=x+(tw//2)*16
    rect((door_x+1,y+h-13,door_x+14,y+h-1),"#6f604b")
    rect((door_x+3,y+h-12,door_x+12,y+h-1),"#ab8258")
    rect((door_x+10,y+h-6,door_x+11,y+h-5),"#ebcd83")
    for sy in range(3): rect((door_x-2-sy,y+h+sy*2,door_x+17+sy,y+h+sy*2+1),["#b5a383","#c9b793","#dfcda5"][sy])
    if kind=="library":
        books(x+8,y+25,w-17)
        books(x+8,y+46,23)
        for xx in [x+43,x+80]:
            table(xx,y+49,23,10);chair(xx-8,y+50);chair(xx+27,y+50)
            rect((xx+6,y+51,xx+15,y+56),"#eee0b8")
            line([(xx+10,y+51),(xx+10,y+56)],"#a9a185")
    elif kind=="cafe":
        rect((x+7,y+26,x+w-9,y+37),"#6e7661")
        rect((x+6,y+25,x+w-8,y+28),"#dfc6a2")
        rect((x+13,y+22,x+27,y+28),"#555e56")
        for xx in [x+17,x+51,x+83]:
            table(xx,y+48,13,10);chair(xx+3,y+39);chair(xx+3,y+61)
            rect((xx+5,y+50,xx+8,y+53),"#eee4cb")
        plant(x+w-14,y+43)
    elif kind=="school":
        rect((x+23,y+24,x+w-18,y+37),"#6f5b45")
        rect((x+25,y+25,x+w-20,y+35),"#455f53")
        for xx in range(x+13,x+w-10,25):
            table(xx,y+46,15,8);chair(xx+4,y+58)
            rect((xx+4,y+47,xx+10,y+50),"#eee1bd")
    else:
        rect((x+8,y+25,x+25,y+45),"#716a5b")
        rect((x+9,y+26,x+24,y+43),"#a5b8a1" if kind=="home" else "#b89889")
        rect((x+10,y+26,x+23,y+31),"#e5dab9")
        books(x+w-29,y+25,20)
        table(x+34,y+38,17,9)
        rect((x+37,y+39,x+47,y+43),"#e6d6ae")
    plant(x+10,y+h-17)

house(3,2,8,5,"library")
house(14,2,7,5,"cafe")
house(24,2,7,5,"school")
house(3,15,5,4,"home")
house(11,15,5,4,"home")
house(19,15,5,4,"studio")

# Fountain is placed exactly on its collision cells.
d.ellipse((270,163,306,193),fill="#a5a184")
d.ellipse((271,160,305,190),fill="#8c8a75")
d.ellipse((273,160,303,186),fill="#ddd2ad")
d.ellipse((276,163,300,183),fill="#729c97")
rect((285,158,289,177),"#b9b394")
d.ellipse((281,154,293,162),fill="#e0d5b5")
line([(287,152),(287,146)],"#bbd4c0")
for x,y in [(278,170),(295,174),(284,180)]: line([(x,y),(x+3,y)],"#b2c8b4")

def tree(cx,cy,small=False):
    x,y=cx*16+8,cy*16+10
    d.ellipse((x-12,y-2,x+16,y+9),fill="#769563")
    rect((x-3,y-10,x+3,y+4),"#70563d")
    rect((x-1,y-10,x+2,y+3),"#a28354")
    # Pixel cluster silhouette, with staggered leafy tiers.
    d.polygon([(x-12,y-12),(x-16,y-18),(x-13,y-25),(x-9,y-28),(x-9,y-34),(x-3,y-37),(x+5,y-36),(x+9,y-31),(x+13,y-28),(x+14,y-21),(x+17,y-17),(x+12,y-10),(x+5,y-7),(x-6,y-8)],fill="#4e7355")
    d.ellipse((x-12,y-31,x+10,y-12),fill="#6d915f")
    d.ellipse((x-8,y-35,x+7,y-19),fill="#8aa571")
    d.ellipse((x-13,y-24,x,y-13),fill="#789c66")
    rect((x-6,y-31,x-1,y-29),"#a5b983")
    rect((x+3,y-22,x+7,y-20),"#93ac76")

trees=[(1,1),(12,2),(22,2),(32,2),(1,5),(32,6),(2,9),(11,9),(22,9),(31,10),(3,12),(11,12),(23,12),(1,16),(9,16),(17,16),(25,20),(2,21),(9,21),(17,21),(23,21),(31,21)]
for x,y in trees: tree(x,y)
# Low border hedges stay entirely on the blocked edge.
for x in range(0,544,12):
    for y in [0,359]:
        rect((x,y,x+11,y+8),"#527553")
        rect((x+1,y,x+9,y+4),"#789461")
for y in range(6,359,12):
    for x in [0,533]:
        rect((x,y,x+10,y+11),"#5b7e56")
        rect((x+1,y,x+7,y+7),"#839f6b")

for x,y in [(36,71),(363,70),(388,211),(35,281),(155,283)]:
    rect((x,y,x+2,y+14),"#6d654b")
    rect((x-2,y-4,x+4,y+1),"#545f4c")
    rect((x-1,y-3,x+3,y),"#f1d89d")

im.save(OUT / "town.png")

def actor(name,hair,shirt,pants,skin):
    sheet=Image.new("RGBA",(48,96),(0,0,0,0))
    for direction in range(4):
        for frame in range(3):
            sprite=Image.new("RGBA",(16,24),(0,0,0,0)); p=ImageDraw.Draw(sprite)
            bob=1 if frame==1 else 0
            def r(box,col):
                x0,y0,x1,y1=box;p.rectangle((x0,y0+bob,x1,y1+bob),fill=col)
            r((5,15,10,20),pants)
            step=-1 if frame==1 else (1 if frame==2 else 0)
            r((4+step,20,6+step,21),"#494b42");r((9-step,20,11-step,21),"#494b42")
            r((4,10,11,16),shirt);r((3,11,3,15),skin);r((12,11,12,15),skin)
            r((5,9,10,10),"#f2d3a2")
            r((4,3,11,9),skin);r((3,4,3,7),hair);r((12,4,12,7),hair)
            r((4,2,11,4),hair);r((5,1,10,2),hair)
            r((4,4,5,5),hair)
            if direction==3:
                r((4,3,11,8),hair);r((5,8,10,9),hair)
            elif direction==0:
                r((6,6,6,6),"#3d423b");r((10,6,10,6),"#3d423b");r((7,9,9,9),"#bf8e76")
            elif direction==1:
                r((4,6,4,6),"#3d423b");r((9,3,11,8),hair)
            else:
                r((11,6,11,6),"#3d423b");r((4,3,6,8),hair)
            sheet.alpha_composite(sprite,(frame*16,direction*24))
    sheet.save(OUT / (name+".png"))

actor("player","#725241","#c5a16b","#5a756c","#ecc8a0")
actor("mia","#754b39","#c5846e","#746b59","#ebc59e")
actor("oliver","#4e5144","#7c9a99","#5f665b","#dbb38c")
actor("leo","#c49a58","#b0b17b","#766c5b","#f0cda6")
print("Generated town.png and four original character sprite sheets.")
