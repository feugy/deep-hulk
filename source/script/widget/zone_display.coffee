'use strict'

define [
  'jquery'
  'underscore'
  'util/common'
  'app'
], ($, _, {hexToRgb}, app) ->
  
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
    target = renderer.coordToPos target
    {left, top} = renderer.coordToPos start
    
    ctx.beginPath()
    # start at origin bottom
    x1 = left+renderer.tileW*.5
    y1 = top+renderer.tileH
    x2 = target.left+renderer.tileW*.5
    y2 = target.top+renderer.tileH*0.5
    ctx.moveTo x1, y1
    ctx.bezierCurveTo x1, y1-renderer.tileH, x2, y2, x2, y2 
    ctx.strokeStyle = makeLinearGradient ctx, {top: y1, left: x1, color: color}, {top: y2, left: x2, color: color2}
    ctx.lineWidth = 3
    ctx.stroke()
      
  # **private**
  # Evaluate corners of the flamer zone
  # @param tiles [Array] ordered list of flamer covered tiles, first is shooter
  # @param renderer [Object] map used renderer
  # @return an array with the 4 corners positions
  flamerZone = (tiles, renderer) ->
    first = tiles.shift()
    last = tiles.pop() or first
    s1 = renderer.coordToPos first
    s1.top += renderer.tileH
    s2 = _.extend {}, s1
    s3 = renderer.coordToPos last
    s3.top += renderer.tileH
    s4 = _.extend {}, s3
    if first.y is last.y
      # horizontal line
      s2.top -= renderer.tileH
      s4.top -= renderer.tileH
      if first.x < last.x
        s1.left += renderer.tileW
        s2.left += renderer.tileW
        s3.left += renderer.tileW
        s4.left += renderer.tileW
    else if first.x is last.x
      # vertical line
      s2.left += renderer.tileW
      s4.left += renderer.tileW
      if first.y < last.y
        s1.top -= renderer.tileH
        s2.top -= renderer.tileH
        s3.top -= renderer.tileH
        s4.top -= renderer.tileH
    else if (first.x > last.x and first.y > last.y) or
        (first.x < last.x and first.y < last.y)
      # diagonal top right
      s1.top -= renderer.tileH*0.7
      s3.top -= renderer.tileH*0.7
      s2.left += renderer.tileW*0.7
      s4.left += renderer.tileW*0.7
      if first.x < last.x
        s1.top -= renderer.tileH*0.3
        s2.top -= renderer.tileH*0.3
        s3.top -= renderer.tileH*0.3
        s4.top -= renderer.tileH*0.3
        s1.left += renderer.tileW*0.3
        s2.left += renderer.tileW*0.3
        s3.left += renderer.tileW*0.3
        s4.left += renderer.tileW*0.3
    else
      # diagonal top left
      s2.top -= renderer.tileH*0.7
      s4.top -= renderer.tileH*0.7
      s2.left += renderer.tileW*0.7
      s4.left += renderer.tileW*0.7
      if first.x > last.x
        s1.top -= renderer.tileH*0.3
        s2.top -= renderer.tileH*0.3
        s3.top -= renderer.tileH*0.3
        s4.top -= renderer.tileH*0.3
      else
        s1.left += renderer.tileW*0.3
        s2.left += renderer.tileW*0.3
        s3.left += renderer.tileW*0.3
        s4.left += renderer.tileW*0.3
    [s1, s2, s3, s4]
    
  class zoneDisplay
    
    # Controller dependencies
    @$inject: ['$scope', '$element']
          
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    constructor: (@scope, element) ->
      @$el = $(element)                     
      # show menu, highlighted tiles
      @scope.$watch 'src', @_highlight
    
    # **private**
    # Highlight selected tiles
    _highlight: =>
      # clear previous highligts
      @$el[0].width = @$el[0].width
      return unless @scope.src?
      ctx = @$el[0].getContext '2d'
      # get renderer from parent
      renderer = @scope.$parent.renderer
      
      # get color from configuration
      {r, g, b, a} = hexToRgb conf.colors[@scope.src?.kind] or '#FFFF'
      color = "rgba(#{r}, #{g}, #{b}, #{a})"
      
      switch @scope.src?.kind
      
        when 'deploy'
          # for deploy, fill each tiles with same color
          renderer.drawTile ctx, tile, color for tile in @scope.src.tiles
            
        when 'move', 'assault'
          # mive and assault will display a gradient centered on origin (character position)
          grad = makeRadialGradient ctx, @scope.src.origin, renderer, renderer.tileW*1.5, color
          tiles = @scope.src.tiles or []
          tiles.push @scope.src.origin unless @scope.src.origin in tiles
          renderer.drawTile ctx, tile, grad for tile in tiles
            
        when 'shoot'
          # draw line if necessary: not for flamer if it hits
          if @scope.src.weapon isnt 'flamer' or @scope.src.tiles.length is 0
            {r, g, b, a} = hexToRgb conf.colors.visibilityLine or '#FFFF'
            c1 = "rgba(#{r}, #{g}, #{b}, #{a})"
            if @scope.src.obstacle
              end = @scope.src.obstacle
              # use different end color
              {r, g, b, a} = hexToRgb conf.colors.obstacle or '#FFFF'
              c2 = "rgba(#{r}, #{g}, #{b}, #{a})"
            else
              end = @scope.src.target
              # use same color as highlight
              c2 = color
            drawVisibilityLine ctx, @scope.src.origin, end, renderer, c1, c2
          
          switch @scope.src.weapon
            when 'missileLauncher'
              # shoot with missileLauncher affect a circular area: radial gradient
              grad = makeRadialGradient ctx, @scope.src.target, renderer, renderer.tileW*1.5, color
              renderer.drawTile ctx, tile, grad for tile in @scope.src.tiles
            when 'flamer'
              # shoot with flamer affect a line
              if @scope.src.tiles.length > 0
                [s1, s2, s3, s4] = flamerZone @scope.src.tiles, renderer
                # draw a rectangle covering tiles
                ctx.beginPath()
                ctx.moveTo s1.left, s1.top
                ctx.lineTo s2.left, s2.top
                ctx.lineTo s4.left, s4.top
                ctx.lineTo s3.left, s3.top
                ctx.closePath()
                s1.color = color
                s2.color = color
                # use linear gradient orthogonal to tiles
                ctx.fillStyle = makeLinearGradient ctx, s1, s2
                ctx.fill()
            else
              # other only affect a list of tiles
              for tile in @scope.src.tiles
                renderer.drawTile ctx, tile, makeRadialGradient ctx, tile, renderer, renderer.tileW*0.5, color 