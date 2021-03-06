###

Параметры:

  wall_offset  - отступ от стены [мм]
  board_w      - ширина доски [мм]
  board_h      - высота доски [мм]
  room_polygon - полигон комнаты 
  room_polygon_offset - полигон комнты с отсупом 
  room_bbox    - габариты комнаты
  flooring[]   - массив ламинатин
  
###

# стартовая инициализация после загрузки

# Размеры канваса px
W = 800
H = 800
wall_offset = -10


path2svg = (path)->
    svg = path.map (point, j)->
        pref = if j is 0 then "M" else "L"
        "#{pref}#{point.X},#{point.Y}"
    svg+="Z"

poly2svg = (poly) ->
    svg_path = poly.reduce (svg, path)->
        svg += path2svg path
    , ""

offset = (poly, delta)->
    co = new ClipperLib.ClipperOffset()
    offseted = new ClipperLib.Paths()
    co.AddPaths(poly,  ClipperLib.JoinType.jtMiter, ClipperLib.EndType.etClosedPolygon);
    co.MiterLimit = 10;
    co.ArcTolerance = 0.25;
    co.Execute offseted, delta
    offseted

scale_path = (path, scale)->
    X: p.X*scale, Y: p.Y*scale for p in path
scale_poly = (poly, scale)->
    scale_path path, scale for path in poly

clip = (subj, clip)->
    
    subj = scale_poly subj, 100
    clip = scale_poly clip, 100

    subj = offset subj, -5
    cpr = new ClipperLib.Clipper()
    cpr.AddPaths subj, ClipperLib.PolyType.ptSubject, true
    cpr.AddPaths clip, ClipperLib.PolyType.ptClip, true
    result = new ClipperLib.Paths();
    cpr.Execute(
        ClipperLib.ClipType.ctIntersection, 
        result, 
        ClipperLib.PolyFillType.pftNonZero, 
        ClipperLib.PolyFillType.pftNonZero)
    result = offset result, 4

    result = scale_poly result, 0.01

area = (poly)->
    ClipperLib.JS.AreaOfPolygons poly

path_bbox = (path)->
    min_x = min_y =  Infinity
    max_x = max_y = -Infinity
    # ищем крайние точки
    path.map (p)->
        min_x = p.X if min_x > p.X
        min_y = p.Y if min_y > p.Y
        max_x = p.X if max_x < p.X
        max_y = p.Y if max_y < p.Y

    l: min_x # left
    t: min_y # top 
    r: max_x # right
    b: max_y # bottom

poly_bbox = (poly)->
    bbox = l: Infinity, t: Infinity, r:-Infinity, b:-Infinity
    # расширяем bbox полигона по включенным в него примитивам
    poly.map (path)->
        b = path_bbox path
        bbox.l = b.l if bbox.l > b.l
        bbox.t = b.t if bbox.t > b.t
        bbox.r = b.r if bbox.r < b.r
        bbox.b = b.b if bbox.b < b.b 
    bbox.w = bbox.r-bbox.l # ширина
    bbox.h = bbox.b-bbox.t # высотыа
    return bbox 

point_inside_path = (point, polygon) ->
    x = point.X
    y = point.Y
    inside = false
    i = 0
    j = polygon.length - 1
    while i < polygon.length
        xi = polygon[i].X
        yi = polygon[i].Y
        xj = polygon[j].X
        yj = polygon[j].Y
        intersect =((yi > y) isnt (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
        if intersect
            inside = !inside
        j = i++
    inside

point_inside = (point, poly)->
    for path in poly
        if point_inside_path point, path
            return true
    false

rnd = (r)-> Math.random()*r | 0

# 

class Room
    constructor:(@svg)->
        do @random

    random:=>
        @group = @svg.group()
        @group.attr
            transform: "scale(0.1)"

        # Собираем случайную комнтау из 4'ех случайных прямоугольников
        @poly = for i in [0..4]
            x = (1+rnd(4))*1000
            y = (1+rnd(4))*1000
            w = (2+rnd(4))*1000
            h = (2+rnd(4))*1000
            [{ X:x  , Y:y   }
             { X:x+w, Y:y   }
             { X:x+w, Y:y+h }
             { X:x  , Y:y+h }]
    
        # склеиваем прямоугольники в один контур
        @glued_poly = offset @poly, 0
        # bounding box
        @bbox = poly_bbox @glued_poly
        # Центр
        @cx = @bbox.l+@bbox.w*0.5
        @cy = @bbox.t+@bbox.h*0.5
        # радиус описаной окружности
        @R = Math.sqrt(@bbox.w*@bbox.w + @bbox.h*@bbox.h)*0.5

        glued_path = @svg.path poly2svg @glued_poly
        glued_path.attr
            "vector-effect":"non-scaling-stroke"
            fill: "white"
            stroke: "gray"
            strokeWidth: 4
        @group.add glued_path

        @offseted_poly = offset @glued_poly, wall_offset
        @offseted_path = @svg.path poly2svg @offseted_poly
        @offseted_path.attr
            "vector-effect":"non-scaling-stroke"
            fill: "none"
            stroke: "red"
            strokeWidth: 1

        @group.add @offseted_path
        
class Flooring

    constructor: (@svg, @room, @w=1380.0, @h=190.0, @dir=45, @shift=0.2)->
        
        @debug = false
        @flooring = true

        @update()

    update: =>
        
        if @debug_layer?
            @debug_layer.clear()
        if @boards_layer?
            @boards_layer.clear()
        if @details_layer?
            @details_layer.clear()

        @debug_layer?= @svg.group()
        @debug_layer.attr
            visibility: if @debug then "visible" else "hidden"
            transform: "scale(0.1)"
            fill: "gray"
            fillOpacity: "0.1"
            stroke: "gray"
            strokeWidth: 4
        
        @boards_layer?= @svg.group()
        @boards_layer.attr
            transform: "scale(0.1)"
            visibility: if @flooring then "visible" else "hidden"
        
        @details_layer?= @svg.group()
        
        # увеличиваем радиус и bbox на длинну доски
        xt = @w*0.5
        @R = @room.R+xt
        @bbox =
            l: @room.bbox.l - xt
            r: @room.bbox.r + xt
            t: @room.bbox.t - xt
            b: @room.bbox.b + xt
        @bbox.w = @bbox.r-@bbox.l
        @bbox.h = @bbox.b-@bbox.t

        # ко-во рядов
        lines_cnt = @R*2.0/@h
        @dir_r = @dir/180.0*Math.PI
        # вектор сдвига ряда в направлении @dir
        sn = Math.sin @dir_r
        cs = Math.cos @dir_r       
        # горизонтальный сдвиг доски, перпендикулярно @dir
        h_dx = @w*cs
        h_dy =-@w*sn
        # вертикальный сдвиг ряда в направлении @dir
        v_dx = @h*sn
        v_dy = @h*cs
        # стартовая точка
        sx = @room.cx-@R*sn
        sy = @room.cy-@R*cs

        @draw_boundings()

        board_intersects = (board, bbox)=>
            for p in board
                if bbox.l < p.X < bbox.r and bbox.t < p.Y < bbox.b
                    return true
            false

        # Создаем полигон покрытия если он пересекате полигон комнаты
        create_board = (cx, cy)=>
            # полигон элемента покрытия
            board = [
                { X: cx+(-h_dx-v_dx)*0.5, Y: cy+(-h_dy-v_dy)*0.5 }
                { X: cx+(+h_dx-v_dx)*0.5, Y: cy+(+h_dy-v_dy)*0.5 }
                { X: cx+(+h_dx+v_dx)*0.5, Y: cy+(+h_dy+v_dy)*0.5 }
                { X: cx+(-h_dx+v_dx)*0.5, Y: cy+(-h_dy+v_dy)*0.5 }]
            
            # дополнительные точки проверки, нужны для угловых элементов
            points = [
                board[0], board[1], board[2], board[3]
                { X: cx-v_dx*0.5, Y: cy-v_dy*0.5 } 
                { X: cx+v_dx*0.5, Y: cy+v_dy*0.5 }
                { X: cx+(-h_dx*0.5-v_dx)*0.5, Y: cy+(-h_dy*0.5-v_dy)*0.5 }
                { X: cx+(+h_dx*0.5-v_dx)*0.5, Y: cy+(+h_dy*0.5-v_dy)*0.5 }
                { X: cx+(+h_dx*0.5+v_dx)*0.5, Y: cy+(+h_dy*0.5+v_dy)*0.5 }
                { X: cx+(-h_dx*0.5+v_dx)*0.5, Y: cy+(-h_dy*0.5+v_dy)*0.5 }]

            # проверяем попали ли точки элемента в полигон комнаты
            for point in points
                inside = point_inside(point, @room.glued_poly)
                if inside
                    bp = @svg.path path2svg board
                    @debug_layer.add bp
                    return board
            undefined
        
        # заполяем помещение досками
        # 1) проходим по диаметру описаной окружности
        # 2) строим ряды влево и вправо от центра
        @boards = []
        @counter = 0
        for l in [1...lines_cnt-1]
            
            # высота хорды
            d = @R-@h*l
            # длинна хорды
            h = Math.sqrt(@R*@R-d*d)
            # центр ряда
            cx = sx+v_dx*l # -cs*h*0.5
            cy = sy+v_dy*l # +sn*h*0.5

            # сдвиг рядов отностиельно друг-друга
            switch l%5
                when 1
                    cx+=h_dx*2.0/3.0
                    cy+=h_dy*2.0/3.0
                when 2
                    cx+=h_dx/4.0
                    cy+=h_dy/4.0
                when 3
                    cx+=h_dx*3.0/4.0
                    cy+=h_dy*3.0/4.0
                when 4
                    cx+=h_dx/2.0
                    cy+=h_dy/2.0

            
            # отладочная визуализация
            @debug_layer.add @svg.circle cx, cy, 40
            @debug_layer.add @svg.line cx-cs*h, cy+sn*h, cx+cs*h, cy-sn*h
            boards_cnt = h/@w|0
            
            # добавляем все доски пересекающие полигон помещения
            line = []
            for r in [0..boards_cnt]
                b = create_board cx+h_dx*r, cy+h_dy*r
                if b
                    line.push b 
                    @counter++
            for r in [-1..-boards_cnt]
                b = create_board cx+h_dx*r, cy+h_dy*r
                if b
                    line.push b
                    @counter++ 
            @boards.push line

        # Пробегаемся по рядам и обрезаем доски
        i = 0
        for line in @boards
            clipped_line = clip line, @room.offseted_poly
            for board in clipped_line
                p = @svg.path path2svg board
                p.attr
                    "vector-effect":"non-scaling-stroke"
                    fill: "#A88"
                    fillOpacity: "0.0"
                    stroke: "#422"
                    strokeWidth: "1.0"
                    strokeOpacity: "0.0"
                p.node.element = p
                show = (p)=>
                    p.attr
                        cursor: "pointer"
                        fillOpacity:"1.0" 
                        strokeOpacity: "1.0"
                    p.mouseover @mouseover
                    p.mouseout  @mouseout
                setTimeout show, (i++)*25, p
                @boards_layer.add p
        
        # статистика
        @text.remove() if @text?
        @text = @svg.text 20, 44, "S: #{area(@room.glued_poly)/1e6}м², ~#{Math.ceil(@counter/8)} пачек (#{@counter}шт) "
        @text.attr
            fontSize: 28
        # @boards_layer.add text 
   
    # Визуализация описанной окружности и bbox
    draw_boundings: =>
        rect = @svg.rect @bbox.l, @bbox.t, @bbox.w, @bbox.h
        rect.attr
            "vector-effect":"non-scaling-stroke"
            fill: "none"
            stroke: "gray"
            strokeWidth: "1"
        @debug_layer.add rect
        circle = @svg.circle @room.cx, @room.cy, @R
        circle.attr
            "vector-effect":"non-scaling-stroke"
            fill: "none"
            stroke: "gray"
            strokeWidth: "1"
        @debug_layer.add circle

    # информация по вышанной доске
    details: (path)=>
        d = path.attr "d"
        points = d.replace(/[^,.0-9]/g, '').split(',').map (n)->parseFloat n
        minx = maxx = points[0]
        miny = maxy = points[1]
        
        for i in [2...points.length] by 2
            minx = points[i+0] if minx > points[i+0]
            miny = points[i+1] if miny > points[i+1]
            maxx = points[i+0] if maxx < points[i+0]
            maxy = points[i+1] if maxy < points[i+1]
        cx = (maxx+minx)*0.5
        cy = (maxy+miny)*0.5
        path = for i in [0...points.length] by 2
            X: points[i+0]-cx
            Y: points[i+1]-cy
        
        p = @svg.path path2svg path
        p.attr
            transform:"rotate(#{@dir+90})"
            stroke: "#422"
            strokeWidth: 6
            fill: "#A88"
        bbox = p.getBBox()
        p.attr
            transform: "translate(#{-bbox.x} #{-bbox.y}) rotate(#{@dir+90})"
        
        @details_layer.clear()
        @details_layer.add p
        
        # В середине каждого ребра выводим размер
        for i in [0...path.length]
            j = i+1
            j%= path.length
            dx = path[i].X-path[j].X
            dy = path[i].Y-path[j].Y
            ln = Math.sqrt(dx*dx+dy*dy)
            cx = (path[i].X+path[j].X)*0.5
            cy = (path[i].Y+path[j].Y)*0.5
            angle = Math.atan2(dx,dy)*180.0/Math.PI

            t = @svg.text(cx, cy-10, "#{(ln+1)|0} мм")
            t.attr
               transform: "translate(#{-bbox.x} #{-bbox.y}) rotate(#{@dir+90}) rotate(#{-90-angle} #{cx} #{cy})"
               textAnchor: "middle"
               fontSize: 24
            @details_layer.add t

        @details_layer.attr
            transform: "translate(#{@bbox.r*0.1}, #{@bbox.t*0.1}) scale(0.5) "
    
    mouseover: (e)=>
        el = e.target.element
        el.animate {fillOpacity: "0.75"}, 200
        @details el
        
    mouseout: (e)=>
        el = e.target.element
        el.animate {fillOpacity: "1.0"}, 200
        @details_layer.clear()

    mousedown: ->

$ ->
    svg = Snap "100%", "100%"
    room = new Room svg
    flooring = new Flooring svg, room
    
    gui = new dat.GUI()
    gui.add(flooring, "dir"  ,    0,   360,   15).onFinishChange (v)->flooring.update()
    gui.add(flooring, "shift", 0.01,  0.5, 0.01).onFinishChange (v)->flooring.update()
    gui.add(flooring, "w"    ,  200,  2000,   10).onFinishChange (v)->flooring.update()
    gui.add(flooring, "h"    ,  200,  2000,   10).onFinishChange (v)->flooring.update()
    gui.add(flooring, "debug").onChange (v)->
        visibility = if v then "visible" else "hidden"
        flooring.debug_layer.attr visibility: visibility 
    gui.add(flooring, "flooring").onChange (v)->
        visibility = if v then "visible" else "hidden"
        flooring.boards_layer.attr visibility: visibility 
