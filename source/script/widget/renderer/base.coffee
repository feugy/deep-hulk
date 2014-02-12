'use strict'

define [], ->
  
  # The map renderer is used to render tiles on the map
  # Extending this class allows to have different tiles type: hexagonal, diamond...
  class MapRenderer

    # associated map directive
    map: null

    # map coordinate of the lower-left hidden corner
    origin: {x:0, y:0}

    # Individual tile width, taking zoom into account
    tileW: null

    # Individual tile height, taking zoom into account
    tileH: null
    
    # Lower displayed coord
    lower: x:0, y:0
    
    # Upper displayed coord
    upper: x:0, y:0
    
    # **private**
    # Returns the number of tile within the map total height.
    # Used to reverse the ordinate axis.
    #
    # @return number of tile in total map height
    _verticalTotalNum: () => 
      (-1 + Math.floor @height*3/@tileH)*3
      
    # Allows to apply a z-index modifier regarding the rendered model
    # For example, allows to reorder items sharing the same coordinate regarding their attributes
    #
    # @param model [Object] the rendered model
    # @param pos [Object] position returned by coordToPos() that will be modified
    applyStackRules: (model, pos) =>
      # does nothing

    # Initiate the renderer with map inner state. 
    # Initiate `tileW` and `tileH`.
    #
    # @param map [Object] the associated map widget
    init: (map) => throw new Error 'the `init` method must be implemented'

    # Compute the map coordinates of the other corner of displayed rectangle
    #
    # @param coord [Object] map coordinates of the upper/lower corner used as reference
    # @param upper [Boolean] indicate the the reference coordinate are the upper-right corner. 
    # False to indicate its the bottom-left corner
    # @return map coordinates of the other corner
    nextCorner: (coord, upper=true) => throw new Error 'the `nextCorner` method must be implemented'

    # Translate map coordinates to css position (relative to the map origin)
    #
    # @param coord [Object] object containing x and y coordinates
    # @option coord x [Number] object abscissa
    # @option coord y [Number] object ordinates
    # @return an object containing:
    # @option return left [Number] the object's left offset, relative to the map origin
    # @option return top [Number] the object's top offset, relative to the map origin
    coordToPos: (coord) => throw new Error 'the `coordToPos` method must be implemented'

    # Translate css position (relative to the map origin) to map coordinates to css position
    #
    # @param coord [Object] object containing top and left position relative to the map origin
    # @option coord left [Number] the object's left offset
    # @option coord top [Number] the object's top offset
    # @return an object containing:
    # @option return x [Number] object abscissa
    # @option return y [Number] object ordinates
    # @option return z-index [Number] the object's z-index
    posToCoord: (pos) => throw new Error 'the `posToCoord` method must be implemented'

    # Draws the grid wireframe on a given context.
    #
    # @param ctx [Object] the canvas context on which drawing
    drawGrid: (ctx) => throw new Error 'the `drawGrid` method must be implemented'

    # Draws the markers on a given context.
    #
    # @param ctx [Object] the canvas context on which drawing
    drawMarkers: (ctx) => throw new Error 'the `drawMarkers` method must be implemented'

    # Draw a single selected tile in selection or to highlight hover
    #
    # @param ctx [Canvas] the canvas context.
    # @param pos [Object] coordinate of the drew tile
    # @param color [String] the color used to fill the tile
    drawTile: (ctx, pos, color) => throw new Error 'the `drawTile` method must be implemented'

    # Place the movable layers after a move
    #
    # @param move [Object] map coordinates (x and y) of the movement
    # @return screen offset (left and top) of the movable layers
    replaceMovable: (move) => throw new Error 'the `replaceMovable` method must be implemented'
      
    # Place the container itself after a move.
    #
    # @param pos [Object] current screen position (left and top) of the container
    # @return screen offset (left and top) of the container
    replaceContainer: (pos) => throw new Error 'the `replaceContainer` method must be implemented'
