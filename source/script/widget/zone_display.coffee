'use strict'

define [
  'require'
  'jquery'
  'underscore'
  'util/common'
  'app'
], (require, $, _, {hexToRgb, computeOrientation}, app) ->
  
  # The zone directive displays action zone on map
  app.directive 'zoneDisplay', ->
    # directive template
    template: '<canvas class="zone-display"></canvas>'
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # zone specification:
      # - tiles [Array] list of map coordinates of highlighted tiles
      # - kind [String] disctinctive zone kind
      # - origin [Object] map coordinates of the zone origin if any.
      src: '=?'
    
    # controller
    require: 'zoneDisplay'
    controller: zoneDisplay
  
  # **private**
  # Creates a radial gradient for zone displayal
  #
  # @param ctx [Canvas] rendering context
  # @param coord [Object] map coordinate of gradient center
  # @param renderer [Object] map renderer used
  # @param raduis [Number] gradient radius
  # @param color [String] gradient color
  makeRadialGradient = (ctx, coord, renderer, radius, color) ->
    {left, top} = renderer.coordToPos coord
    left += renderer.tileW*0.5
    top += renderer.tileH*0.5
    grad = ctx.createRadialGradient left, top, 0, left, top, radius
    grad.addColorStop 0, color
    grad.addColorStop 0.7, color
    grad.addColorStop 1, 'transparent'
    grad
  
  # **private**
  # Creates a linear refletive gradient for zone displayal
  #
  # @param ctx [Canvas] rendering context
  # @param source [Object] object with 'left', 'top' and 'color' properties
  # @param target [Object] object with 'left', 'top' and 'color' properties
  makeLinearGradient = (ctx, source, target) ->
    grad = ctx.createLinearGradient source.left, source.top, target.left, target.top
    grad.addColorStop 0.15, 'transparent'
    grad.addColorStop 0.35, source.color
    grad.addColorStop 0.65, target.color
    grad.addColorStop 0.85, 'transparent'
    grad
          
  # **private**
  # Draws a bezier line with color gradient to simulate visibility line, 
  # between origin and target coordinates
  #
  # @param ctx [Canvas] rendering context
  # @param start [Object] map coordinate of line start
  # @param target [Object] map coordinate of line end
  # @param renderer [Object] map renderer used
  # @param raduis [Number] gradient radius
  # @param color [String] start color
  # @param color2 [String] end color, default to start color
  drawVisibilityLine = (ctx, start, target, renderer, color, color2) ->
    color2 or= color
    # draw visibility line until target or obstacle
    {left, top} = renderer.coordToPos start
    target = renderer.coordToPos target

    ctx.beginPath()
    # start at origin bottom
    x1 = left+renderer.tileW*.5
    y1 = top+renderer.tileH*0.8
    x2 = target.left+renderer.tileW*0.5
    y2 = target.top+renderer.tileH*0.8
    ctx.moveTo x1, y1
    ctx.lineTo x2, y2
    ctx.lineWidth = 3
    ctx.strokeStyle = makeLinearGradient ctx, {left: x1, top:y1, color: color}, {left: x2, top:y2, color: color2}
    ctx.stroke()
    
  # **private**
  # Draws an image at position, oriented against origin.
  #
  # @param ctx [Canvas] rendering context
  # @param position [Object] map coordinate where image is drawn
  # @param origin [Object] map coordinate against which image is oriented. Null to disabled orientation
  # @param renderer [Object] map renderer used
  # @param img [Object] image data
  drawOrientedImage = (ctx, position, origin, renderer, img, size=null) ->
    position = renderer.coordToPos position
    origin = if origin? then renderer.coordToPos origin else position
    margin = 0
    size = size or {w:renderer.tileW, h:renderer.tileH}
    ctx.save()
    ctx.translate position.left+renderer.tileW/2, position.top+renderer.tileH/2
    ctx.rotate computeOrientation position, origin
    ctx.drawImage img, -margin-size.w/2, -margin-size.h/2, size.w+margin*2, size.h+margin*2
    ctx.restore()
    
  base = require.toUrl('').replace('script/.js', '') or '.'
  
  class zoneDisplay
    
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas']
          
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Link to Atlas service
    atlas: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    constructor: (@scope, element, @atlas) ->
      @$el = $(element)                     
      # show menu, highlighted tiles
      @scope.$watch 'src', @_highlight
      @_highlight @scope.src
    
    # **private**
    # Highlight selected tiles
    _highlight: (value, old) =>
      return if _.isEqual value, old
      # clear previous highligts
      @$el[0].width = @$el[0].width
      ctx = @$el[0].getContext '2d'
      
      return unless value?
      # get renderer from parent
      renderer = @scope.$parent.renderer
      
      # get color from configuration
      {r, g, b, a} = hexToRgb conf.colors[@scope.src?.kind] or '#FFFF'
      color = "rgba(#{r}, #{g}, #{b}, #{a})"
      
      isDreadnought = @scope.src.origin?.kind is 'dreadnought' and @scope.src.origin?.revealed 
      # make a copy to allow drawing manipulations without breacking changes detection
      tiles = @scope.src.tiles?.concat() or []
      switch @scope.src?.kind
      
        when 'deploy'
          # for deploy, fill each tiles with same color
          renderer.drawTile ctx, tile, color for tile in tiles
            
        when 'move', 'assault'
          # move and assault will display a gradient centered on origin (character position)
          coord = _.pick @scope.src.origin, 'x', 'y'
          # removes character pos if not already included
          tiles = _.reject tiles, (t) -> t.x is coord.x and t.y is coord.y
          if isDreadnought
            # removes dreadnought position if included
            tiles = _.reject tiles, (t) -> t.x in [coord.x, coord.x+1] and t.y in [coord.y, coord.y+1]
            # dreadnought specific case: center right ahead current position
            coord.x += 0.5
            coord.y += 0.5
            range = renderer.tileW*2.1
          else
            range = renderer.tileW*1.5
            
          @atlas.imageService.load "#{base}/image/#{@scope.src.kind}.png", (err, key, img) =>
            return if err?
            drawOrientedImage ctx, tile, coord, renderer, img for tile in tiles
            
        when 'shoot'
          weapon = @scope.src.weapon.id or @scope.src.weapon
          # colors for visibility lines
          {r, g, b, a} = hexToRgb conf.colors.visibilityLine or '#FFFF'
          c1 = "rgba(#{r}, #{g}, #{b}, #{a})"
          c2 = color
          
          start = _.pick @scope.src.origin, 'x', 'y'
          if isDreadnought
            # dreadnought specific case: center right ahead current position
            start.x += 0.5
            start.y += 0.5
            
          if @scope.src.obstacle and weapon isnt 'autoCannon'
            # use different end color for obstacle, and quit
            {r, g, b, a} = hexToRgb conf.colors.obstacle or '#FFFF'
            return drawVisibilityLine ctx, start, @scope.src.obstacle, renderer, c1, "rgba(#{r}, #{g}, #{b}, #{a})"
            
          switch weapon
            when 'missileLauncher'
              # shoot with missileLauncher affect a circular area: radial gradient
              target = @scope.src.target
              drawVisibilityLine ctx, start, target, renderer, c1, c2
              tiles = _.reject tiles, (t) -> t.x is target.x and t.y is target.y
              @atlas.imageService.load "#{base}/image/explosion.png", (err, key, center) =>
                return if err?
                drawOrientedImage ctx, target, null, renderer, center
                @atlas.imageService.load "#{base}/image/explosion-side.png", (err, key, side) =>
                  return if err?
                  @atlas.imageService.load "#{base}/image/explosion-corner.png", (err, key, corner) =>
                    return if err?
                    for tile in tiles
                      if tile.x is target.x or tile.y is target.y
                        # same line
                        drawOrientedImage ctx, tile, target, renderer, side
                      else
                        # corners
                        from = x:target.x, y:target.y
                        if tile.y > target.y
                          if tile.x < target.x
                            from.x--
                          else if tile.x > target.x
                            from.y++
                        else if tile.y < target.y
                          if tile.x < target.x
                            from.y--
                          else
                            from.x++
                        drawOrientedImage ctx, tile, from, renderer, corner
                      
            when 'flamer'
              # shoot with flamer affect a line
              @atlas.imageService.load "#{base}/image/flames.png", (err, key, img) =>
                return if err?
                coord = tiles[0]
                #if isDreadnought
                #  tiles = _.reject tiles, (t) -> t.x in [coord.x, coord.x+1] and t.y in [coord.y, coord.y+1]
                #else
                tiles = _.reject tiles, (t) -> t.x is coord.x and t.y is coord.y
                if tiles.length >= 2
                  isDiag = tiles[0].x isnt tiles[1].x and tiles[0].y isnt tiles[1].y
                else
                  isDiag = false
                # on diagonals, specify a larger image
                size= w:renderer.tileW*(if isDiag then 1.42 else 1), h: renderer.tileH               
                drawOrientedImage ctx, tile, coord, renderer, img, size for tile in tiles
            else
              @atlas.imageService.load "#{base}/image/shoot.png", (err, key, img) =>
                return if err?
                # other only affect a list of tiles
                for tile in tiles
                  drawVisibilityLine ctx, start, tile, renderer, c1, c2
                  drawOrientedImage ctx, tile, null, renderer, img 