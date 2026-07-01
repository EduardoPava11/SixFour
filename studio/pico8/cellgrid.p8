pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- sixfour cell-grid rgb layout tool
-- ------------------------------------------------------------------
-- pico-8 is the LOOK/DEMO sketchpad ONLY. the haskell spec is the
-- source of truth. constants MIRROR:
--   spec/src/SixFour/Spec/Lattice.hs      (grid + rounded corner)
--   spec/src/SixFour/Spec/GridLayout.hs   (capture-scene widgets)
-- on_screen() is a line-for-line port of Lattice.cellOnScreen.
-- studio/pico8/check_sync.py verifies the constants match the spec.
--
-- a rectangle-making tool: make/name/move/resize widgets on the
-- rounded iphone 17 pro cell grid, see coordinates + the layout laws
-- live, then copy the numbers into the spec. LETTERS pick a tool,
-- ARROWS act. press H for the on-screen menu.
-- ------------------------------------------------------------------

-- constants (mirrored from the spec) -------------------------------
gifpx     = 4
scr_w_pt  = 402   -- Lattice.screenWidthPt
scr_h_pt  = 874   -- Lattice.screenHeightPt
cols      = flr(scr_w_pt/gifpx)   -- 100
rows      = flr(scr_h_pt/gifpx)   -- 218
corner_pt = 56    -- Lattice.cornerRadiusPt
corner_r  = flr(corner_pt/gifpx)  -- 14 cells
corner_n  = 2     -- Lattice.cornerExponent (2=circle, 5=squircle)
rad_half  = 2*corner_r            -- 28 (half-cell units)
touch     = 11    -- Lattice.touchFloorCells (44pt)
safe_top_r= flr(62/gifpx)  -- ~15 rows
safe_bot_r= flr(34/gifpx)  -- ~8 rows

-- capture-scene widgets (GridLayout.captureScene) = the seed layout
preview = {col=18, row=22,  w=64, h=64, name="preview", inter=false}
palette = {col=42, row=145, w=16, h=16, name="palette", inter=true}

-- palette indices --------------------------------------------------
c_off  = 0   c_on   = 1   c_safe = 2
c_edge = 6   c_bad  = 14
rcols  = {11,8,12,10,9,3,4,13}  -- per-rectangle colours

-- geometry: PORT of Lattice.cellOnScreen ---------------------------
function ipow(x,n) local v=1 for i=1,n do v=v*x end return v end

function on_screen(c,r)
 if c<0 or c>=cols or r<0 or r>=rows then return false end
 local dc=max(0, rad_half-(2*min(c,cols-1-c)+1))
 local dr=max(0, rad_half-(2*min(r,rows-1-r)+1))
 if dc==0 or dr==0 then return true end
 if corner_n==2 then return dc*dc+dr*dr <= rad_half*rad_half end
 return ipow(dc/rad_half,corner_n)+ipow(dr/rad_half,corner_n) <= 1
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
function clone(w) return {col=w.col,row=w.row,w=w.w,h=w.h,name=w.name,inter=w.inter} end
function yn(b) return b and "y" or "n" end

-- state ------------------------------------------------------------
zoomlvls={} -- filled in _init (fit + integer levels)

function _init()
 poke(0x5f2d,1)                       -- devkit keyboard + mouse
 fit_cpx=128/rows
 zoomlvls={fit_cpx,1,2,3,4,6}
 zi=1
 seed_rects()
 tool="move"
 typing=false
 menu=true                            -- show the instructions on boot
 hold=0 dragging=false
 msg="" msgt=0
 update_view()
end

function seed_rects()
 rects={clone(preview),clone(palette)}
 sel=2
end

-- view transform (zoom, auto-centre on selection) ------------------
function update_view()
 cpx=zoomlvls[zi]
 local visc=128/cpx
 local s=rects[sel]
 local scx=s.col+s.w/2
 local scy=s.row+s.h/2
 vc0=(visc>=cols) and 0 or mid(0,flr(scx-visc/2),cols-visc)
 vr0=(visc>=rows) and 0 or mid(0,flr(scy-visc/2),rows-visc)
 vox=max(0,(128-cols*cpx)/2)
 voy=max(0,(128-rows*cpx)/2)
end
function cell_sx(c) return vox+(c-vc0)*cpx end
function cell_sy(r) return voy+(r-vr0)*cpx end
function screen_to_cell(sx,sy) return vc0+flr((sx-vox)/cpx), vr0+flr((sy-voy)/cpx) end

-- tools ------------------------------------------------------------
function add_rect()
 local visc=128/cpx
 local c=mid(0,flr(vc0+visc/2)-8,cols-16)
 local r=mid(0,flr(vr0+visc/2)-8,rows-16)
 add(rects,{col=c,row=r,w=16,h=16,name="r"..(#rects+1),inter=false})
 sel=#rects tool="move"
end
function del_rect()
 if #rects<=1 then return end
 deli(rects,sel) sel=mid(1,sel,#rects)
end
function copy_layout()
 local s="-- pico8 cellgrid layout ("..#rects.." rects); paste numbers into GridLayout\n"
 for w in all(rects) do
  s=s..w.name.." lrCol="..w.col.." lrRow="..w.row.." lrW="..w.w.." lrH="..w.h
     .." inter="..(w.inter and "true" or "false").."\n"
 end
 printh(s,"@clip") msg="copied "..#rects.." rects to clipboard" msgt=100
end

function _update()
 -- mouse wheel zoom
 local wz=stat(36)
 if wz>0 then zi=min(zi+1,#zoomlvls) elseif wz<0 then zi=max(zi-1,1) end

 local k=stat(31)
 if typing then
  local w=rects[sel]
  if k=="\r" or k=="\n" or btnp(4) or btnp(5) then typing=false
  elseif k=="\b" then w.name=sub(w.name,1,#w.name-1)
  elseif k!="" and #w.name<8 then w.name=w.name..k end
 else
  -- letters pick a tool / action
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
  elseif k=="h" then menu=not menu
  elseif k=="=" or k=="+" then zi=min(zi+1,#zoomlvls)
  elseif k=="-" or k=="_" then zi=max(zi-1,1) end

  -- mouse: click to select, drag to move
  if stat(34)&1==1 then
   local mc,mr=screen_to_cell(stat(32),stat(33))
   if not dragging then
    for i=#rects,1,-1 do
     if in_rect(mc,mr,rects[i]) then
      sel=i dragging=true dgx=mc-rects[i].col dgy=mr-rects[i].row break
     end
    end
   end
   if dragging then
    local t=rects[sel]
    t.col=mid(0,mc-dgx,cols-t.w) t.row=mid(0,mr-dgy,rows-t.h)
   end
  else dragging=false end

  -- arrows act per tool (tap = 1, hold = accelerate)
  local dx,dy=0,0
  if btnp(0) then dx-=1 end if btnp(1) then dx+=1 end
  if btnp(2) then dy-=1 end if btnp(3) then dy+=1 end
  if btn(0) or btn(1) or btn(2) or btn(3) then hold+=1 else hold=0 end
  if hold>16 then
   local step=min(flr((hold-16)/3)+1,12)
   if btn(0) then dx-=step end if btn(1) then dx+=step end
   if btn(2) then dy-=step end if btn(3) then dy+=step end
  end
  if tool=="select" then
   if dx<0 then sel=sel-1 if sel<1 then sel=#rects end end
   if dx>0 then sel=sel+1 if sel>#rects then sel=1 end end
  elseif dx!=0 or dy!=0 then
   local w=rects[sel]
   if tool=="resize" then
    w.w=mid(1,w.w+dx,cols-w.col) w.h=mid(1,w.h+dy,rows-w.row)
   else
    w.col=mid(0,w.col+dx,cols-w.w) w.row=mid(0,w.row+dy,rows-w.h)
   end
  end
 end

 update_view()
 if msgt>0 then msgt-=1 end
end

-- drawing ----------------------------------------------------------
function bg_col(c,r)
 if not on_screen(c,r) then return c_off end
 if r<safe_top_r or r>=rows-safe_bot_r then return c_safe end
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
 rect(cell_sx(0)-1,cell_sy(0)-1,cell_sx(cols),cell_sy(rows),c_edge)  -- phone outline
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
  if w.inter then rect(x0,y0,x1,y1,7) end  -- interactive: white edge
  if i==sel then
   rect(x0-1,y0-1,x1+1,y1+1,10)             -- selection outline (yellow)
   pcoord(w.col..","..w.row, x0, y0-6)                       -- top-left
   pcoord((w.col+w.w)..","..(w.row+w.h), x1-15, y1+1)        -- bottom-right
   pcoord(w.w.."x"..w.h, (x0+x1)/2-8, (y0+y1)/2-2)           -- size
  end
 end
end

function scene_status()
 local clears,disjoint,floor_ok=true,true,true
 for w in all(rects) do if not clears_corners(w) then clears=false end end
 for i=1,#rects do for j=i+1,#rects do
  if rects_overlap(rects[i],rects[j]) then disjoint=false end
 end end
 for w in all(rects) do if w.inter and (w.w<touch or w.h<touch) then floor_ok=false end end
 local ok=clears and disjoint and floor_ok
 return ok,"cor:"..yn(clears).." dis:"..yn(disjoint).." fl:"..yn(floor_ok)
end

function draw_hud()
 local w=rects[sel]
 rectfill(0,0,127,6,0)
 print("t:"..tool.." ["..w.name.."] "..sel.."/"..#rects.." z"..zi
   ..(corner_n==2 and " o" or " sq"),1,1,7)
 local ok,fl=scene_status()
 rectfill(0,115,127,127,0)
 print(w.col..","..w.row.." "..w.w.."x"..w.h.." = pt "..(w.col*4)..","..(w.row*4)
   .." "..(w.w*4).."x"..(w.h*4),1,116,6)
 print(fl.."   H:menu",1,122, ok and 11 or c_bad)
 if typing then print("name: "..w.name.."_",1,108,10) end
 if msgt>0 then rectfill(14,60,114,68,0) print(msg,18,61,11) end
end

function draw_menu()
 rectfill(6,10,122,120,1) rect(6,10,122,120,7)
 print("cell-grid rectangle tool",10,13,10)
 print("letters=tool  arrows=act",10,22,6)
 print("m move    r resize   s select",10,31,7)
 print("n new     d delete   e rename",10,39,7)
 print("i interactive  c copy layout",10,47,7)
 print("v revert-to-spec  q circle/sq",10,55,7)
 print("+/- or wheel: zoom",10,63,7)
 print("mouse: click=select drag=move",10,71,6)
 print("s tool: L/R change selection",10,79,6)
 print("coords shown around selection",10,87,6)
 print("copy -> paste into gridlayout",10,95,6)
 print("then cabal test. spec decides.",10,103,13)
 print("H: close menu",10,113,10)
end

function _draw()
 cls(0)
 draw_bg()
 draw_rects()
 draw_hud()
 if menu then draw_menu() end
end
