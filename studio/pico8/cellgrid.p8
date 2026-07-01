pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- sixfour cell-grid rgb layout tool
-- ------------------------------------------------------------------
-- pico-8 is the LOOK/DEMO sketchpad ONLY. the haskell spec is the
-- source of truth. constants MIRROR:
--   spec/src/SixFour/Spec/Lattice.hs      (grid + rounded corner)
--   spec/src/SixFour/Spec/GridLayout.hs   (capture-scene widgets + laws)
-- on_screen() is a line-for-line port of Lattice.cellOnScreen.
-- studio/pico8/check_sync.py verifies the constants match the spec.
--
-- a rectangle-making tool. LETTERS pick a tool (m/r/s) or fire a
-- command (n/d/e/i/c/v/g/f/q/h/zoom); ARROWS act on the selection.
-- press H for the on-screen menu. green flags mean the layout would
-- pass cabal test (all five gridlayout laws).
-- ------------------------------------------------------------------

-- constants (mirrored from the spec) -------------------------------
gifpx      = 4
scr_w_pt   = 402   -- Lattice.screenWidthPt
scr_h_pt   = 874   -- Lattice.screenHeightPt
cols       = flr(scr_w_pt/gifpx)   -- 100
rows       = flr(scr_h_pt/gifpx)   -- 218
corner_pt  = 56    -- Lattice.cornerRadiusPt
corner_r   = flr(corner_pt/gifpx)  -- 14 cells
corner_n   = 2     -- Lattice.cornerExponent (2=circle exact, 5=squircle approx)
rad_half   = 2*corner_r            -- 28 (half-cell units)
touch      = 11    -- Lattice.touchFloorCells (44pt)
safe_top_pt= 62    -- Lattice.safeTopPt
safe_bot_pt= 34    -- Lattice.safeBottomPt

-- capture-scene widgets (GridLayout.captureScene) = the seed layout
preview = {col=18, row=22,  w=64, h=64, name="preview", inter=false}
palette = {col=42, row=145, w=16, h=16, name="palette", inter=true}

c_off=0 c_on=1 c_safe=2 c_edge=6 c_bad=14
rcols={11,8,12,10,9,3,4,13}

-- geometry: PORT of Lattice.cellOnScreen ---------------------------
function ipow(x,n) local v=1 for i=1,n do v=v*x end return v end
function on_screen(c,r)
 if c<0 or c>=cols or r<0 or r>=rows then return false end
 local dc=max(0,rad_half-(2*min(c,cols-1-c)+1))
 local dr=max(0,rad_half-(2*min(r,rows-1-r)+1))
 if dc==0 or dr==0 then return true end
 if corner_n==2 then return dc*dc+dr*dr<=rad_half*rad_half end  -- exact = spec
 -- n!=2: fixed-point APPROX audition (28^5 overflows the exact form)
 return ipow(dc/rad_half,corner_n)+ipow(dr/rad_half,corner_n)<=1
end
function in_rect(c,r,w) return c>=w.col and c<w.col+w.w and r>=w.row and r<w.row+w.h end
function rects_overlap(a,b)
 return a.col<b.col+b.w and b.col<a.col+a.w and a.row<b.row+b.h and b.row<a.row+a.h
end
function clears_corners(w)
 for r=w.row,w.row+w.h-1 do for c=w.col,w.col+w.w-1 do
  if not on_screen(c,r) then return false end
 end end
 return true
end
function sa_ok(w) return w.row*gifpx>=safe_top_pt and (w.row+w.h)*gifpx<=scr_h_pt-safe_bot_pt end
function clone(w) return {col=w.col,row=w.row,w=w.w,h=w.h,name=w.name,inter=w.inter} end
function yn(b) return b and "y" or "n" end
function snapr(x) if snap>1 then return flr((x+snap/2)/snap)*snap end return x end

-- state ------------------------------------------------------------
function _init()
 poke(0x5f2d,1)   -- REQUIRES devkit keyboard+mouse (edu edition/desktop)
 fit_cpx=128/rows
 zoomlvls={fit_cpx,1,2,3,4,6}
 zi=1 rid=0
 seed_rects()
 tool="move" typing=false menu=true
 hold=0 dragging=false snap=1
 recenter=true bgdirty=true
 lastvc=-1 lastvr=-1 lastzi=-1 lastn=-1
 msg="" msgt=0
 ensure_view()
end
function nextname() rid+=1 return "r"..rid end
function seed_rects()
 rid=0 rects={clone(preview),clone(palette)} sel=2 recenter=true bgdirty=true
end
function add_rect()
 local visc=128/cpx
 local c=mid(0,snapr(flr(vc0+visc/2)-8),cols-16)
 local r=mid(0,snapr(flr(vr0+visc/2)-8),rows-16)
 add(rects,{col=c,row=r,w=16,h=16,name=nextname(),inter=false})
 sel=#rects tool="move" recenter=true
end
function del_rect() if #rects<=1 then return end deli(rects,sel) sel=mid(1,sel,#rects) recenter=true end
function copy_layout()
 local s="-- pico8 cellgrid layout ("..#rects.." rects); paste into GridLayout\n"
 for w in all(rects) do
  s=s..w.name.." lrCol="..w.col.." lrRow="..w.row.." lrW="..w.w.." lrH="..w.h
     .." inter="..(w.inter and "true" or "false").."\n"
 end
 printh(s,"@clip") msg="copied "..#rects.." rects to clipboard" msgt=100
end

-- view transform (zoom; pans only on zoom / reselect / off-view) ----
function ensure_view()
 cpx=zoomlvls[zi]
 local visc=128/cpx
 local s=rects[sel]
 local need=recenter or zi!=lastzi
 if not need then
  if s.col+s.w<=vc0 or s.col>=vc0+visc or s.row+s.h<=vr0 or s.row>=vr0+visc then need=true end
 end
 if need then
  local scx=s.col+s.w/2 local scy=s.row+s.h/2
  vc0=(visc>=cols) and 0 or mid(0,flr(scx-visc/2),cols-visc)
  vr0=(visc>=rows) and 0 or mid(0,flr(scy-visc/2),rows-visc)
  recenter=false
 end
 vox=max(0,(128-cols*cpx)/2)
 voy=max(0,(128-rows*cpx)/2)
 if vc0!=lastvc or vr0!=lastvr or zi!=lastzi or corner_n!=lastn then
  bgdirty=true lastvc=vc0 lastvr=vr0 lastzi=zi lastn=corner_n
 end
end
function cell_sx(c) return vox+(c-vc0)*cpx end
function cell_sy(r) return voy+(r-vr0)*cpx end
function screen_to_cell(sx,sy) return vc0+flr((sx-vox)/cpx), vr0+flr((sy-voy)/cpx) end

function _update()
 local wz=stat(36)
 if wz>0 then zi=min(zi+1,#zoomlvls) elseif wz<0 then zi=max(zi-1,1) end
 local k=stat(31)

 if typing then
  local w=rects[sel]
  if k=="\r" or k=="\n" then if #w.name==0 then w.name="r"..rid end typing=false
  elseif k=="\b" then if #w.name>0 then w.name=sub(w.name,1,#w.name-1) end
  elseif k!="" and #w.name<8 then w.name=w.name..k end
  ensure_view() if msgt>0 then msgt-=1 end
  return
 end

 if     k=="m" then tool="move"
 elseif k=="r" then tool="resize"
 elseif k=="s" then tool="select"
 elseif k=="n" then add_rect()
 elseif k=="d" then del_rect()
 elseif k=="e" then typing=true
 elseif k=="i" then rects[sel].inter=not rects[sel].inter
 elseif k=="c" then copy_layout()
 elseif k=="v" then seed_rects() msg="reset to spec" msgt=60
 elseif k=="q" then corner_n=(corner_n==2) and 5 or 2
 elseif k=="g" then snap=snap==1 and 2 or snap==2 and 4 or snap==4 and 8 or 1
 elseif k=="f" then recenter=true
 elseif k=="h" then menu=not menu
 elseif k=="=" or k=="+" then zi=min(zi+1,#zoomlvls)
 elseif k=="-" or k=="_" then zi=max(zi-1,1) end

 -- mouse: click grabs (widget under cursor, else the selection), drag moves
 if stat(34)&1==1 then
  local mc,mr=screen_to_cell(stat(32),stat(33))
  if not dragging then
   local hit=false
   for i=#rects,1,-1 do
    if in_rect(mc,mr,rects[i]) then sel=i dragging=true hit=true dgx=mc-rects[i].col dgy=mr-rects[i].row break end
   end
   if not hit then local t=rects[sel] dgx=flr(t.w/2) dgy=flr(t.h/2) dragging=true end
  end
  if dragging then
   local t=rects[sel]
   t.col=mid(0,snapr(mc-dgx),cols-t.w) t.row=mid(0,snapr(mr-dgy),rows-t.h)
  end
 else dragging=false end

 -- arrows
 if tool=="select" then
  if btnp(0) then sel=(sel-2)%#rects+1 recenter=true end
  if btnp(1) then sel=sel%#rects+1 recenter=true end
 else
  local dx,dy=0,0
  if btnp(0) then dx-=1 end if btnp(1) then dx+=1 end
  if btnp(2) then dy-=1 end if btnp(3) then dy+=1 end
  if btn(0) or btn(1) or btn(2) or btn(3) then hold+=1 else hold=0 end
  if hold>16 then
   local st=min(flr((hold-16)/3)+1,12)
   if btn(0) then dx-=st end if btn(1) then dx+=st end
   if btn(2) then dy-=st end if btn(3) then dy+=st end
  end
  if dx!=0 or dy!=0 then
   local w=rects[sel] local m=(snap>1) and snap or 1
   if tool=="resize" then
    w.w=mid(1,snapr(w.w)+dx*m,cols-w.col) w.h=mid(1,snapr(w.h)+dy*m,rows-w.row)
   else
    w.col=mid(0,snapr(w.col)+dx*m,cols-w.w) w.row=mid(0,snapr(w.row)+dy*m,rows-w.h)
   end
  end
 end

 ensure_view()
 if msgt>0 then msgt-=1 end
end

-- drawing ----------------------------------------------------------
function bg_col(c,r)
 if not on_screen(c,r) then return c_off end
 if r*gifpx<safe_top_pt or r*gifpx>=scr_h_pt-safe_bot_pt then return c_safe end
 return c_on
end
function draw_bg()
 if cpx<1 then
  for sy=0,127 do for sx=0,127 do
   local c=vc0+flr((sx-vox)/cpx) local r=vr0+flr((sy-voy)/cpx)
   pset(sx,sy,(c>=0 and c<cols and r>=0 and r<rows) and bg_col(c,r) or 0)
  end end
 else
  local n=flr(128/cpx)+1
  for r=vr0,min(vr0+n,rows-1) do for c=vc0,min(vc0+n,cols-1) do
   local x=cell_sx(c) local y=cell_sy(r)
   rectfill(x,y,x+cpx-1,y+cpx-1,bg_col(c,r))
  end end
 end
 rect(cell_sx(0)-1,cell_sy(0)-1,cell_sx(cols),cell_sy(rows),c_edge)
end
function pcoord(t,x,y)
 x=mid(0,x,127-#t*4) y=mid(0,y,121)
 rectfill(x-1,y-1,x+#t*4,y+5,0) print(t,x,y,10)
end
function draw_rects()
 for i=1,#rects do
  local w=rects[i]
  local x0=cell_sx(w.col) local y0=cell_sy(w.row)
  local x1=cell_sx(w.col+w.w)-1 local y1=cell_sy(w.row+w.h)-1
  rectfill(x0,y0,x1,y1,rcols[((i-1)%#rcols)+1])
  if w.inter then rect(x0,y0,x1,y1,7) end
  if i==sel then
   rect(x0-1,y0-1,x1+1,y1+1,10)
   pcoord(w.col..","..w.row,x0,y0-6)
   pcoord((w.col+w.w)..","..(w.row+w.h),x1-15,y1+1)
   pcoord(w.w.."x"..w.h,(x0+x1)/2-8,(y0+y1)/2-2)
  end
 end
end
function draw_cursor()
 local mx,my=stat(32),stat(33)
 line(mx-3,my,mx+3,my,0) line(mx,my-3,mx,my+3,0)
 line(mx-2,my,mx+2,my,7) line(mx,my-2,mx,my+2,7) pset(mx,my,8)
 local c,r=screen_to_cell(mx,my)
 if c>=0 and c<cols and r>=0 and r<rows then
  local t=c..","..r
  print(t,mid(0,mx+3,127-#t*4),mid(0,my-6,121),10)
 end
end
function scene_status()
 local cor,dis,fl,sa=true,true,true,true
 for w in all(rects) do
  if not clears_corners(w) then cor=false end
  if not sa_ok(w) then sa=false end
  if w.inter and (w.w<touch or w.h<touch) then fl=false end
 end
 for i=1,#rects do for j=i+1,#rects do if rects_overlap(rects[i],rects[j]) then dis=false end end end
 local ok=cor and dis and fl and sa
 return ok,"cor:"..yn(cor).." dis:"..yn(dis).." fl:"..yn(fl).." sa:"..yn(sa)
end
function draw_hud()
 local w=rects[sel]
 rectfill(0,0,127,6,0)
 print("t:"..tool.." ["..w.name.."] "..sel.."/"..#rects.." z"..zi.." s"..snap
   ..(corner_n==2 and "" or " sq~"),1,1,7)
 local ok,fl=scene_status()
 rectfill(0,115,127,127,0)
 print(w.col..","..w.row.." "..w.w.."x"..w.h.." pt "..(w.col*gifpx)..","..(w.row*gifpx)
   .." "..(w.w*gifpx).."x"..(w.h*gifpx),1,116,6)
 print(fl.." h:menu",1,122, ok and 11 or c_bad)
 if typing then rectfill(0,106,127,113,0) print("name: "..w.name.."_ (enter=done)",1,107,10) end
 if msgt>0 then rectfill(14,60,114,68,0) print(msg,18,61,11) end
end
function draw_menu()
 rectfill(4,8,124,123,1) rect(4,8,124,123,7)
 print("cell-grid rectangle tool",8,11,10)
 print("tools (arrows act):",8,20,6)
 print(" m move  r resize  s select",8,27,7)
 print("commands:",8,35,6)
 print(" n new  d delete  e rename",8,42,7)
 print(" (rename: type, enter=done)",8,49,13)
 print(" i interact  c copy  v revert",8,56,7)
 print(" g snap  f recenter",8,63,7)
 print(" q circle/squircle (sq~approx)",8,70,7)
 print(" +/- or wheel: zoom",8,77,7)
 print("mouse: click grab, drag move",8,85,6)
 print("select tool: L/R change sel",8,92,6)
 print("green = would pass cabal test",8,101,13)
 print("cor dis fl sa = scene laws",8,108,13)
 print("h: close menu",8,117,10)
end
function _draw()
 if bgdirty then
  cls(0) draw_bg()
  memcpy(0x0000,0x6000,0x2000)  -- cache the (slow) bg into sprite scratch
  bgdirty=false
 else
  memcpy(0x6000,0x0000,0x2000)  -- restore cached bg (fast; keeps drag smooth)
 end
 draw_rects()
 draw_cursor()
 draw_hud()
 if menu then draw_menu() end
end
