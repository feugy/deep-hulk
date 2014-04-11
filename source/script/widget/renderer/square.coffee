'use strict'

define [
  'widget/renderer/base'
], (MapRenderer) ->
  
  # Number of items sharing the same position
  numberPerStack = 20
  
  # Square renderer creates classic checkerboard maps
  class SquareRenderer extends MapRenderer

    # Initiate the renderer with map inner state.
    #
    # @param map [Object] the associated map widget
    init: (map) =>
      @map = map  
      # parse dimensions from incoming
      dims = @map.scope.dimensions.match /^(.*):(.*) (.*):(.*)$/
      @lower = 
        x: parseInt dims[1]
        y: parseInt dims[2]
      @upper = 
        x: parseInt dims[3]
        y: parseInt dims[4]
        
      # dimensions of the square.
      @tileH = @map.scope.src.tileDim*@map.scope.zoom
      @tileW = @map.scope.src.tileDim*@map.scope.zoom
            
    # Allows to apply a z-index modifier regarding the rendered model
    # Walls and doors will be below or above other items, regarding their image number
    #
    # @param model [Object] the rendered model
    # @param pos [Object] position returned by coordToPos() that will be modified
    applyStackRules: (model, pos) =>
      switch model.type?.id
        when 'wall'
          switch model.imageNum
            # those walls needs to be above anything
            when 2, 6, 7 then pos.zIndex += numberPerStack-1 
        when 'door'
          # those doors needs to be above anything
          unless 7 < model.imageNum < 12
            pos.zIndex += numberPerStack-1 
        when 'alien', 'marine'
          # alien and marines are immediately above some walls
          pos.zIndex += 1
      
    # Translate map coordinates to css position (relative to the map origin)
    #
    # @param coord [Object] object containing x and y coordinates
    # @option coord x [Number] object abscissa
    # @option coord y [Number] object ordinates
    # @return an object containing:
    # @option return left [Number] the object's left offset, relative to the map origin
    # @option return top [Number] the object's top offset, relative to the map origin
    # @option return z-index [Number] the object's z-index
    coordToPos: (obj) =>
      {
        left: (obj.x - @lower.x)*@tileW
        top: @map.height-(obj.y + 1 - @lower.y)*@tileH
        # for z-index, order by rows (inverted), and allow multiple items inside the same row position
        # then order from left (below) to right (above)
        zIndex: (Math.round(@map.height/@tileH-1)-obj.y+@origin.y)*numberPerStack + (obj.x-@origin.x)
      }
      
    # Translate css position (relative to the map origin) to map coordinates to css position
    #
    # @param coord [Object] object containing top and left position relative to the map origin
    # @option coord left [Number] the object's left offset
    # @option coord top [Number] the object's top offset
    # @return an object containing:
    # @option return x [Number] object abscissa
    # @option return y [Number] object ordinates
    posToCoord: (pos) =>
      {
        y: @lower.y + Math.floor (@map.height-pos.top)/@tileH
        x: @lower.x + Math.floor pos.left/@tileW
      }
      
    # Draws the grid wireframe on a given context.
    #
    # @param ctx [Object] the canvas context on which drawing
    drawGrid: (ctx) =>
      i = 0
      # draws horizontal lines starting from bottom
      for y in [@map.height-1..0] by -@tileH
        ctx.moveTo 0, y
        ctx.lineTo @map.width, y

      # draws vertical lines
      for x in [1..@map.width] by @tileW
        ctx.moveTo x, 0
        ctx.lineTo x, @map.height
      ctx.stroke()
      
    # Draws the markers on a given context.
    #
    # @param ctx [Object] the canvas context on which drawing
    drawMarkers: (ctx) =>
      row = 0
      for y in [@map.height-1..0] by -@tileH
        gameY = @lower.y + row++
        if gameY % 5 is 0
          col = 0
          for x in [1..@map.width] by @tileW    
            gameX = @lower.x + col++
            if gameX % 5 is 0
              ctx.fillText "#{gameX}:#{gameY}", x+@tileW*0.5, y-@tileH*0.5
    
    # Draw a single selected tile in selection or to highlight hover
    #
    # @param ctx [Canvas] the canvas context.
    # @param pos [Object] coordinate of the drew tile
    # @param color [String] the color used to fill the tile
    drawTile: (ctx, coord, color) =>
      {left, top} = @coordToPos coord
      ctx.fillStyle = color
      ctx.fillRect left, top, @tileW, @tileH