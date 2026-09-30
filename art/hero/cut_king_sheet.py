# Нарезка листа Короля: python3 cut_king_sheet.py <исходный_лист.webp|png> -> king_sheet.png (16x15 кадров 64x36, фон убран)
from PIL import Image
import numpy as np
from collections import deque
im=np.array(Image.open(__import__('sys').argv[1] if len(__import__('sys').argv) > 1 else 'king_sheet_1.webp').convert('RGB')).astype(np.int32)
H,W,_=im.shape
ROWS,COLS=15,16
CW=W//COLS
ys=[round(r*H/ROWS) for r in range(ROWS+1)]
OUT_W,OUT_H=64,36  # клетка выходного листа
cells=[]
for r in range(ROWS):
    for c in range(COLS):
        y0,y1=ys[r],ys[r+1]
        x0,x1=c*CW,(c+1)*CW
        # отступ 1px от краёв, чтобы не цеплять полосу соседнего ряда
        cell=im[y0+1:y1-1, x0+1:x1-1].copy()
        h,w,_=cell.shape
        border=np.concatenate([cell[0],cell[-1],cell[:,0],cell[:,-1]])
        bg=np.median(border,axis=0)
        dist=np.sqrt(((cell-bg)**2).sum(axis=2))
        gray_bg = (bg.max()-bg.min()) < 15
        if gray_bg:
            sat = cell.max(axis=2)-cell.min(axis=2)
            # серый фон: близко по цвету И почти без насыщенности; тёплые кожа/ткань не трогаем
            val = cell.max(axis=2)
            # фон и светлый нейтральный ореол вокруг фигуры: без насыщенности и не темнее фона
            halo = (sat < 14) & (val >= bg.max() - 14)
            dist = np.where(halo, 0.0, np.where(sat < 10, dist * (70.0/18.0), 999.0))
        # заливка от краёв по пикселям, близким к фону
        bgmask=np.zeros((h,w),bool)
        q=deque()
        for x in range(w):
            for y in (0,h-1):
                if dist[y,x]<70 and not bgmask[y,x]: bgmask[y,x]=True; q.append((y,x))
        for y in range(h):
            for x in (0,w-1):
                if dist[y,x]<70 and not bgmask[y,x]: bgmask[y,x]=True; q.append((y,x))
        while q:
            y,x=q.popleft()
            for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
                ny,nx=y+dy,x+dx
                if 0<=ny<h and 0<=nx<w and not bgmask[ny,nx] and dist[ny,nx]<70:
                    bgmask[ny,nx]=True; q.append((ny,nx))
        alpha=np.where(bgmask,0,255).astype(np.float32)
        # мягкая кромка: пиксели переднего плана у фона получают частичную прозрачность
        fg=~bgmask
        edge=fg & (np.roll(bgmask,1,0)|np.roll(bgmask,-1,0)|np.roll(bgmask,1,1)|np.roll(bgmask,-1,1))
        a_edge=np.clip((dist-40)/80.0,0,1)*255
        alpha[edge]=a_edge[edge]
        # второй слой кромки (соседи краевых пикселей) тоже частично прозрачен, если близок к фону
        edge2=fg & ~edge & (np.roll(edge,1,0)|np.roll(edge,-1,0)|np.roll(edge,1,1)|np.roll(edge,-1,1))
        alpha[edge2]=np.minimum(255, np.clip((dist[edge2]-25)/60.0,0,1)*255 + 40)
        # убрать мелкие отдельные точки (метки сетки) — компоненты меньше 14 пикселей
        lab=np.zeros((h,w),np.int32); n=0; sizes={}
        for y in range(h):
            for x in range(w):
                if alpha[y,x]>0 and lab[y,x]==0:
                    n+=1; stack=[(y,x)]; lab[y,x]=n; cnt=0
                    while stack:
                        cy,cx=stack.pop(); cnt+=1
                        for dy in (-1,0,1):
                            for dx in (-1,0,1):
                                ny,nx=cy+dy,cx+dx
                                if 0<=ny<h and 0<=nx<w and lab[ny,nx]==0 and alpha[ny,nx]>0:
                                    lab[ny,nx]=n; stack.append((ny,nx))
                    sizes[n]=cnt
        for k,sz in sizes.items():
            if sz<14: alpha[lab==k]=0
        # снять зелёный/серый отсвет на кромке
        rgb=cell.astype(np.float32)
        # «вычитаем» фон из полупрозрачных пикселей кромки: c = (c - (1-a)*bg) / a
        af=(alpha/255.0)[...,None]
        semi=(alpha>0)&(alpha<255)
        un=(rgb-(1.0-af)*bg[None,None,:])/np.maximum(af,0.15)
        rgb=np.where(semi[...,None], np.clip(un,0,255), rgb)
        if bg[1]>bg[0]+30:  # зелёный фон
            m=edge
            mx=np.maximum(rgb[...,0],rgb[...,2])
            rgb[...,1]=np.where(m, np.minimum(rgb[...,1], mx+10), rgb[...,1])
        alpha[:2,:]=0; alpha[-2:,:]=0; alpha[:,:2]=0; alpha[:,-2:]=0
        rgba=np.dstack([rgb,alpha]).clip(0,255).astype(np.uint8)
        img=Image.fromarray(rgba,'RGBA')
        # премультипликация перед уменьшением, чтобы не было тёмного ореола
        img=img.resize((OUT_W,OUT_H),Image.LANCZOS)
        cells.append(img)
sheet=Image.new('RGBA',(OUT_W*COLS,OUT_H*ROWS),(0,0,0,0))
for i,cimg in enumerate(cells):
    r,c=divmod(i,COLS)
    sheet.paste(cimg,(c*OUT_W,r*OUT_H))
sheet.save('king_sheet.png')
# превью на шахматке
prev=Image.new('RGBA',sheet.size,(255,0,255,255))
prev.alpha_composite(sheet)
prev.convert('RGB').resize((sheet.width*2,sheet.height*2),Image.NEAREST).save('king_preview.png')
print(sheet.size)
