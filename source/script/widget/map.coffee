'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'util/common'
  'widget/renderer/square'
  # unwired dependencies
  'widget/item'
  'widget/cursor'
  'widget/zone_display'
  'jquery-ui'
], ($, _, app, {mixColors, euclidianDistance, parseShortcuts, isShortcuts, computeOrientation}, SquareRenderer) ->
  
  # The map directive displays map with fields and items
  app.directive 'map', -> 
    # directive template
    template: '<div class="map" data-msd-wheel="onZoom($event, $delta)"></div>'
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # current player's squad
      squad: '=?'
      # map displayed
      src: '=?'
      # map fields displayed
      fields: '=?'
      # map item displayed
      items: '=?'
      # Currently selected squad members
      selected: '=?'
      # Items displayed in menu
      menuItems: '=?'
      # Error displayed when having trouble with server
      error: '=?'
      # coordinates of the lower left tile and upper right tile.
      dimensions: '=?'
      # highligted zone. May contains a list of coordinates (property 'tiles'), and a given kind (property 'kind')
      zone: '=?'
      # Flag that indicates wether or not display the tile grid.
      displayGrid: '=?'
      # Flag that indicates wether or not display the tile coordinates (every 5 tiles).
      displayMarkers: '=?'
      # click event handler
      click: '=?'
      # right click event handler
      rightclick: '=?'
      # hover event handler
      hover: '=?'
      # blip deployement handler
      blipDeployed: '=?'
      # currently active rule
      activeRule: '=?'
      # active rule selection handler
      selectActiveRule: '=?'
      # rule execution request handler
      askToExecuteRule: '=?'
      # menu item click event handler
      selectMenuItem: '=?'
      # color used for markers, grid, and so on.
      colors: '@'
      # json configuration for haptic behaviour: animation 'duration' (default to 80ms) and 
      # 'move' (default to 40px) and 'size' percent for detection (default to 0.10) 
      hapticConf: '@'
      # list of indication displayed on map
      # accepts objects with map coordinates (x and y), 'duration' in millis, displayed 'text' and css 'className'
      displayIndications: '=?'
      # if not null, activate the blip deployement by drag'n drop
      deployScope: '=?'
      # display zoom
      zoom: '=?'
      # number of tile displayed in vertical. Depends on the available space
      verticalTileNum: '=?'
      # number of tile displayed in horizontal. Depends on the available space
      horizontalTileNum: '=?'
      # Relay to cursor the fact that current selected weapon needs multiple targets
      needMultipleTargets: '=?'
      # shortcuts used to move selected character
      shortcuts: '@?'
    
    # controller
    controller: MapController
    # link to set default values
    link: (scope, element, attrs) ->
      # set default values
      attrs.$observe 'shortcuts', (val) -> 
        scope.shortcuts  = JSON.parse val or {}
        for direction, value of scope.shortcuts
          scope.shortcuts[direction] = parseShortcuts value
      # set default values
      attrs.$observe 'hapticConf', (val) ->
        scope.hapticConf = JSON.parse val or JSON.stringify 
          duration: 80
          move: 40
          size: 0.10
      attrs.$observe 'displayGrid', (val) -> scope.displayGrid = 'true' is (val or 'true')
      attrs.$observe 'displayMarkers', (val) -> scope.displayMarkers = 'true' is (val or 'true')
      attrs.$observe 'colors', (val) -> scope.colors = JSON.parse val or JSON.stringify 
        markers: 'red'
        grid: '#888'
      scope.zoom = 1
      attrs.$observe 'verticalTileNum', (val) -> scope.verticalTileNum = parseInt(val) or 10
      attrs.$observe 'horizontalTileNum', (val) -> scope.horizontalTileNum = parseInt(val) or 10
      
  # Base widget for maps.
  # It delegates rendering operations to a mapRenderer that you need to manually create and set.
  class MapController
              
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas', '$compile', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Link to Atlas service
    atlas: null
       
    # Angular directive compiler, for item directive addition
    compile : null
        
    # Map loaded width, without zoom taken in account
    width: null

    # Map loaded height, without zoom taken in account
    height: null
    
    # **private**
    # displayed fields. 
    _fields: []
    
    # **private**
    # displayed item widgets. Use model id as key
    _items: {}

    # **private**
    # the layer container
    _container: null

    # **private**
    # canvas layers
    _layers: 
      fields: null
      grid: null
      markers: null
      items: null
      indics: null

    # **private**
    # root element dimensions, for haptic edges
    _dims:
      width: 0
      heigth: 0
      
    # **private**
    # Jumper to avoid refreshing too many times hovered tile.
    _moveJumper: 0

    # **private**
    # last cursor position
    _hoverPos: null 
    
    # **private**
    # node containing hover indicator
    _hoverIndicator: null
    
    # **private**
    # Number of loading images before removing the temporary field layer 
    _pendingImages: 0
    
    # **private**
    # Timeout to next haptic detection
    _hapticDelay: null

    # **private**
    # menu container
    _menu: null
    
    # **private**
    # widget for current cursor 
    _cursorWidget: null
        
    # **private**
    # Currently highlighted zone
    _zone: false
    
    # **private**
    # Flag to avoid removing unexistent droppable, or creating it twice
    _isDroppable: false
    
    # **private**
    # Mousewheel zoom increment.
    _zoomStep: 0.05
        
    # **private**
    # Minimum zoom allowed
    _zoomMin: 0.1
    
    # **private**
    # MAximum zoom allowed
    _zoomMax: 1
    
    # **private**
    # Loading flag to inhibit unitary field/item redraw while loading whole map
    _loading = false
    
    # **private**
    # Flag to inhibit haptic edges while dragging
    _dragging = false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    # @param compile [Object] Angular directive compiler
    # @param rootScope [Object] Angular root scope
    constructor: (@scope, element, @atlas, @compile, rootScope) ->
      @_menuOpened = false
      @$el = $(element)
      @scope.renderer = null
      @scope.fields = [] unless _.isArray @scope.fields
      @scope.items = [] unless _.isArray @scope.items
      # make selected item widget available to exterior 
      @scope.getSelectedWidget = => @_items[@scope.selected?.id]
      @scope.onZoom = (evt, delta) =>
        @scope.zoom += delta*@_zoomStep
        # keep some limits
        @scope.zoom = if @scope.zoom < @_zoomMin then @_zoomMin else @scope.zoom
        @scope.zoom = if @scope.zoom > @_zoomMax then @_zoomMax else @scope.zoom
      
      # bind key listener
      $(window).on 'keydown.map', @_onKey
      @scope.$on '$destroy', => 
        $(window).off 'keydown.map', @_onKey
        
      # recreate and reload content when map or its dimension changes
      @scope.$watch 'src', (value, old) =>
        return unless value? and value isnt old
        @_create()
      # recreate without reload when window size or zoom change
      $(window).on 'resize', _.throttle (value, old) =>
        return unless value? and value isnt old
        @_create false
      , 1000, leading: false
      @scope.$watch 'zoom', _.throttle (value) =>
        @_create false
      , 500, leading: false
      
      # clean and display new items and fields
      redraw = (value, old) =>
        return unless value?
        @_removeData old if old?
        @_addData value
        
      # update displayed items and fields on changes
      @scope.$watch 'items', redraw
      @scope.$watch 'fields', redraw
      rootScope.$on 'modelChanged', (ev, operation, model, changes) =>
        return if @_loading
        if operation is 'creation' or (operation is 'update' and 'map' in changes)
          @_addData [model]
          
        if operation is 'update' and model?.type?.id in ['alien', 'marine'] and 
            (model.id is @scope.selected?.id or @atlas.replayPos?) and
             model.x? and model.y? and not @isVisible model
          # during replay or when moving selected member, be sure to center near action
          @center model
        
      # redraw grid and markers when scope changes
      @scope.$watch 'displayGrid', (value, old) =>
        return unless value? and value isnt old
        @_drawGrid()
      @scope.$watch 'displayMarkers', (value, old) =>
        return unless value? and value isnt old
        @_drawMarkers()
                     
      # show menu, highlighted tiles
      @scope.$watch 'menuItems', (value, old) =>
        return unless value? and value isnt old
        @_showMenu()
        
      # center on selection
      @scope.$watch 'selected', (value, old) =>
        return unless value? and value isnt old
        @center value
        
      @scope.$watch 'deployScope', (value, old) =>
        return unless value isnt old
        @_toggleDeployment()
        
      # shows temporary indications
      @scope.displayIndications = (indications) =>
        return unless indications?
        indications = [indications] unless _.isArray indications
        @_renderIndications indic for indic in indications
              
      # adds a cursor
      @_cursorWidget = $ @compile("""<cursor 
        data-selected="selected" 
        data-renderer="renderer"
        data-zoom="zoom"
        data-get-selected-widget="getSelectedWidget"
        data-select-active-rule="selectActiveRule"
        data-need-multiple-targets="needMultipleTargets"
        data-ask-to-execute-rule="askToExecuteRule"/>""") @scope
                
      # adds a menu
      @_menu = $ @compile("""<ul class="menu">
          <li ng-repeat="item in menuItems" data-value={{item}}>{{'labels.'+item|i18n}}</li>
        </ul>""") @scope
      @_menu.on 'click', @_onMenuItemClick
      
      @$el.on('mousemove', @_onMouseMove).on('mouseleave', (event) => 
        # stop looping on haptic edges
        clearTimeout @_hapticDelay if @_hapticDelay?
        @_hoverPos = null
        @_drawHover()
      )
      # first loading if available
      @_create()

    # Center map on given coordinate 
    #
    # @param coord [Object] object containing x and y coordinates
    # @option coord x [Number] object abscissa
    # @option coord y [Number] object ordinates
    center: (coord) =>
      # center map on position
      pos = @scope.renderer.coordToPos coord
      # do not go beyond left (0) and right (@_dims.width-@width) borders
      rBorder = if @_dims.width > @width then (@_dims.width-@width)/2 else @_dims.width-@width
      lBorder = if @_dims.width > @width then (@_dims.width-@width)/2 else 0
      left = Math.max rBorder, Math.min @_dims.width/2-pos.left, lBorder
      # do not go beyond top (0) and bottom (@_dims.height-@height) borders
      tBorder = if @_dims.height > @height then (@_dims.height-@height)/2 else @_dims.height-@height
      bBorder = if @_dims.height > @height then (@_dims.height-@height)/2 else 0
      top = Math.max tBorder, Math.min @_dims.height/2-pos.top, 0
      @_container.animate {left:left, top:top}, 250
      
    # Indicates wether a coordinate is visible or not inside the map
    # @param coord [Object] map coordinate of the requested point
    # @return true if this coordinate is visible, false otherwise
    isVisible: (coord) =>
      containerPos =  @_container.offset()
      pos = @scope.renderer.coordToPos coord
      # evaluate absolute position of requested coord
      left = pos.left+containerPos.left
      top = pos.top+containerPos.top
      return 0 < left < @_dims.width and 0 < top < @_dims.height
      
    # **private**
    # Re-builds rendering
    #
    # @param reload [Boolean] if true, reloads fields and items
    _create: (reload = true)=>
      # do not re-create if creation in progress
      return if @_progress?
      return unless @scope.dimensions? and @scope.src?
      # renderer depends on the map kind
      switch @scope.src.kind
        when 'square' then @scope.renderer = new SquareRenderer()
        # no kind ? just wait src to be loaded
        else throw new Error "map kind #{@scope.src.kind} not supported"
        
      # Initialize internal state
      @_fields = []
      @_items = {} if reload
      @_container = null
      @_moveJumper = 0
      @_pendingImages = 0
      @_moveJumper = 0
      @_hoverPos = null
      @_hoverIndicator = null
      @_layers = {}
      @_hapticDelay = null
      @_isDroppable = false
      @_loading = false
      @_dragging = false
      
      previous = @scope.selected
      @scope.selected = null
        
      # compute element dimensions and offset
      @_dims =
        width: @$el.width()
        height: @$el.height()
      
      @$el.wrapInner("<div class='temp'></div>")
      @$el.find('.temp').append '<div class="loading"><progress value="0"/></div>'
      @_progress = @$el.find '.loading progress'
      
      # expected map dimension
      mapDim = 
        width: @scope.verticalTileNum*@scope.src.tileDim
        height: @scope.horizontalTileNum*@scope.src.tileDim
      # set zoom to display map on available width (or height)
      @scope.zoom = Math.max @_dims.width/mapDim.width, @_dims.height/mapDim.height if reload
      
      # once zoom is set, init renderer
      @scope.renderer.init @
      
      # canvas dimensions (add 1 to take in account stroke width, and with zoom)
      @height = 1+(@scope.renderer.upper.y-@scope.renderer.lower.y+1)*@scope.renderer.tileH
      @width = 1+(@scope.renderer.upper.x-@scope.renderer.lower.x+1)*@scope.renderer.tileW

      # containment bounds for drag'n drop TODO: get padding from rendering
      axis = {}
      containment = [0, 0, 30, 30]
      if @_dims.width < @width 
        containment[0] = @_dims.width-@width
      else
        axis.y = true
      if @_dims.height < @height 
        containment[1] = @_dims.height-@height
      else
        axis.x = true
        
      # creates the layer container
      # center it if dimension is smaller than viewport
      @_container = $('<div class="map-container"></div>').css(
        height: @height
        width: @width
        left: (@_dims.width-@width)/2
        top: (@_dims.height-@height)/2
      ).draggable(
        containment: containment
        axis: if 'x' of axis then 'x' else if 'y' of axis then 'y' else false
        disabled: axis.x and axis.y
        # return null to avoid cancelling stuff
        start: => @_dragging = true; null
        stop: => @_dragging = false; null
      ).appendTo @$el

      # creates the layer canvas
      @_layers.fields = $("""<canvas class="fields"></canvas>""").appendTo @_container
      @_layers.grid = $("<canvas class='grid'></canvas>").appendTo @_container
      @_layers.markers = $("<canvas class='markers'></canvas>").appendTo @_container

      # adds the item layer and indication layers
      @_layers.items = $("<div class='items'></div>").appendTo(@_container).on 'click contextmenu', @_onMapClick
      @_layers.indics = $("<div class='indications'></div>").appendTo @_container
      
      @_container.find('> canvas, > div').css
        width: @width
        height: @height
      @_container.find('> canvas').attr
        width: @width
        height: @height
      
      @_drawGrid()
      @_drawMarkers()
      @_toggleDeployment()
            
      # adds high light zone, just above fields
      @_zone = $ @compile("""<zone-display
        data-src="zone"
        height="#{@height}"
        width="#{@width}"
      />""") @scope
      @_layers.items.after @_zone
      
      @_container.append @_cursorWidget
      @_container.append @_menu
      
      # gets data
      if reload
        @_loading = true
        console.log "new displayed coord: ", @scope.renderer.lower, ' to: ', @scope.renderer.upper
        @scope.src.consult @scope.renderer.lower, @scope.renderer.upper, (err, fields, items) => @scope.$apply =>
          return @scope.error = err.message if err?
          @scope.fields = fields
          @scope.items = items
          @_loading = false
      else
        # redraw existing fields
        @_addData @scope.fields
        # append existing widget and positionnate
        @_layers.items.append widget.redraw() for id, widget of @_items
          
      # reselect previously selected
      if previous?
        _.defer => @scope.$apply => @scope.selected = previous

    # **private**
    # When deploy drag'n drop scope is toggle, create or removes droppable on items
    _toggleDeployment: =>
      if @scope.deployScope?
        unless @_isDroppable
          @_layers.items.droppable
            scope: @scope.deployScope
            drop: @_onDropBlip
          @_isDroppable = true
      else if @_isDroppable
        @_isDroppable = false
        @_layers.items.droppable 'destroy'
        
    # **private**
    # Adds fieldand items to map. Will be effective only if the added object belongs to map and is inside loaded bounds.
    #
    # @param added [Array<Field|Item>] added data
    _addData: (added) =>
      return unless @scope.renderer?
      for data in added
        continue unless (@scope?.src?.id is data?.mapId or @scope?.src?.id is data?.map?.id) and
          data?.x? and data?.y? and @scope.renderer.upper.x >= data.x >= @scope.renderer.lower.x and 
          @scope.renderer.upper.y >= data.y >= @scope.renderer.lower.y
          
        switch data?.constructor._className
          when 'Field'
            @_fields.push data
            @_pendingImages++
            @_progress?.attr 'max', @_pendingImages
            
            # load image, and use a closure to keep added field
            @atlas.imageService.load "#{conf.imagesUrl}#{data.typeId}-#{data.num}.png", ((field) => (err, img, imgData) =>
              @_updateProgress()
              return if err?
          
              # write on field layer with delay to let progress update
              _.defer =>
                ctx = @_layers.fields[0].getContext '2d'
                {left, top} = @scope.renderer.coordToPos field
                ctx.drawImage imgData, left, top, @scope.renderer.tileW+1, @scope.renderer.tileH+1
            ) data
          when 'Item'
            continue if @_items[data.id]?
            @scope.items.push data unless data in @scope.items
            @_pendingImages++
            @_progress?.attr 'max', @_pendingImages
            
            # defer to let progress be updated
            _.defer (data) =>
              @_updateProgress()
              widget = @compile("""<item 
                  data-squad='squad'
                  data-model-id='#{data.id}' 
                  data-selected='selected' 
                  data-deploy-scope='deployScope'
                  data-display-indications='displayIndications'>
                </item>""") @scope
              @_items[data.id] = widget.data().$itemController
              @_layers.items.append widget
            , data
        
    # **private**
    # Removes field from map. Will be effective only if the field was displayed.
    #
    # @param removed [Array<Field>] removed data. 
    _removeData: (removed) =>
      return unless @scope.renderer?
      ctx = @_layers.fields[0].getContext '2d'
      for data in removed 
        switch data.constructor._className
          when 'Field'
            continue unless @scope?.src?.id is data.mapId
            # removes from local cache
            for field, i in @_fields when field.id is data.id
              @_fields.splice i, 1
              # draw white tile at removed field coordinate
              @scope.renderer.drawTile ctx, data, 'rgba(255, 255, 255, 0.5)'
              break
          when 'Item'
            continue unless @_items[data.id]?
            # remove rendering and cahced widget
            @_items[data.id].$el.remove()
            @_items[data.id].scope.$destroy()
            delete @_items[data.id]
      
    # **private**
    # Decrease pending and remove loading if no more pending.
    # Alsot upade progress indicator
    _updateProgress: =>
      @_pendingImages--
      @_progress?.attr 'value', parseInt(@_progress?.attr('value'))+1
      # end loading
      if @_pendingImages is 0
        _.defer =>
          @$el.find('.loading,.temp').remove()
          @_progress = null
    
    # **private**
    # Redraws the grid wireframe.
    _drawGrid: =>
      return unless @_layers?.grid?
      ctx = @_layers.grid[0].getContext '2d'
      @_layers.grid[0].width = @_layers.grid[0].width
      return unless @scope.displayGrid

      ctx.strokeStyle =  @scope.colors.grid 
      @scope.renderer.drawGrid ctx
      
    # **private**
    # Redraws the grid markers.
    _drawMarkers: =>
      return unless @_layers?.markers?
      ctx = @_layers.markers[0].getContext '2d'
      @_layers.markers[0].width = @_layers.markers[0].width
      return unless  @scope.displayMarkers

      ctx.font = "#{15*@scope.zoom}px sans-serif"
      ctx.fillStyle = @scope.colors.markers
      ctx.textAlign = 'center'
      ctx.textBaseline  = 'middle'
      @scope.renderer.drawMarkers ctx
    
    # **private**
    # Redraws hover indicator on stored position (@_hoverPos)
    _drawHover: =>
      return unless @_layers?.items?
      if @_hoverPos?
        if @_hoverIndicator is null
          # creates cursor
          @_hoverIndicator = $('<div class="hover"></div>').prependTo @_layers.items
        # just change its position and size
        values = @scope.renderer.coordToPos @_hoverPos
        values.width = @scope.renderer.tileW
        values.height = @scope.renderer.tileH
        @_hoverIndicator.css values
      else
        # removes cursor if not needed anymore
        @_hoverIndicator?.remove()
        @_hoverIndicator = null

    # **private**
    # Extracts mouse position from DOM event, regarding the container.
    # @param event [Event] 
    # @return the mouse position
    # @option return left the left offset relative to container
    # @option return top the top offset relative to container
    _mousePos: (event) =>
      return {left:0, top:0} unless @_container?
      offset = @_container.offset()
      {
        left: (event.pageX-offset.left)
        top: (event.pageY-offset.top)
      }
            
    # **private**
    # Get map coordinate, field and items above a given position
    #
    # @param event [Event] a mouse event inside the container. Use unless coord is specified
    # @param coord [Object] map coordinate if already present. Default to null
    # @return an object containing:
    # @option return map [Map] the widget source map
    # @option return x [Integer] the x map coordinate
    # @option return y [Integer] the y map coordinate
    # @option return field [Field] optionnal field above coordinates
    # @option return items [Array<Item>] optionnal items above coordinates
    _getInfos: (event, coord = null) =>
      # get map coordinates
      coord = @scope.renderer.posToCoord @_mousePos event unless coord?
      details = 
        map: @scope.src
        x: coord.x
        y: coord.y
        field: null
      # get field
      for candidate in @_fields when candidate.x is details.x and candidate.y is details.y
        details.field = candidate
        break
      # get items
      details.items = (widget.scope.model for id, widget of @_items when widget.scope?.model?.x is details.x and widget.scope?.model?.y is details.y)
      details
          
    # **private**
    # Positionnate and displays menu when menu content is modified
    _showMenu: =>
      # display menu at last click position
      return unless @scope.menuItems?.length > 0
      @_menuOpened = true
      @_menu.addClass 'open'
      $(document).one 'click contextmenu', => 
        @_menuOpened = false
        @_menu.removeClass 'open'
            
    # **private**
    # Handle clicks on container: propagate coordinate, items and field clicked
    #
    # @param event [Event] click event
    _onMapClick: (event) =>
      # keep event position for further menu displayal
      @_menu.css @_mousePos event
      # at last, trigger click
      details = @_getInfos event 
      switch event.which
        when 3
          @scope.rightclick?(event, details)
          event.preventDefault()
        else
          @scope.click?(event, details)
      
    # **private**
    # Handle clicks inside menu: propagate selected item value
    #
    # @param event [Event] menu click event
    _onMenuItemClick: (event) =>
      item = $(event?.target).closest 'li'
      value = item.data 'value'
      return unless value?
      @scope.selectMenuItem?(event, value)
      
    # **private**
    # Handle mouse move above the container: draw cursor and trigger event.
    #
    # @param event [Event] mouse move event
    _onMouseMove: (event) => 
      return unless @_moveJumper++ % 3 is 0 and not @_menuOpened and @_container?
      # stop looping on haptic edges
      clearTimeout @_hapticDelay if @_hapticDelay?
      
      allowHaptic = false
      # cursor specific case: if hovering cursor widget, always hover the selected tile
      if @scope.selected and $(event.target).closest('.cursor').length isnt 0
        @_hoverPos = x:@scope.selected.x, y:@scope.selected.y
        details = @_getInfos event, @_hoverPos
      else
        details = @_getInfos event
        @_hoverPos = x: details.x, y:details.y
        allowHaptic = @_progress is null
        
      @_drawHover()
      # evaluate haptic edges unless already dragging
      @_onHapticEdge event if allowHaptic and not @_dragging
      # at last, trigger hover
      @scope.hover?(event, details)
      
    # **private**
    # If mouse is near the root element edges, moves the container toward the corresponding direciton.
    # Set the `_hapticDelay` timeout to loop until the mouse is moved
    #
    # @param event [Event] current mouse position
    _onHapticEdge: (event) =>
      duration = @scope.hapticConf.duration
      step = @scope.hapticConf.move
      size = @scope.hapticConf.size
      pos = @$el.offset()
      containerLeft = pos.left
      containerTop = pos.top
      # defer detection a bit to let animation complete and to avoid unecessary detection
      @_hapticDelay = _.delay => 
        mouseLeft = (event.pageX-containerLeft)
        mouseTop = (event.pageY-containerTop)
        {left, top}  = @_container.position()
        newLeft = undefined
        newTop = undefined
        
        direction = null
        # evaluate horizontal edges
        if @_dims.width < @width
          if mouseLeft <= @_dims.width*size
            unless left is 0
              newLeft = if left > -step then 0 else left+step
              direction = "left"
          else if mouseLeft >= @_dims.width*(1-size)
            max = @_dims.width-@width
            if left >= max+0.5
              newLeft = if left < max+step then max else left-step
              direction = "right"
  
        # evaluate vertical edges
        if @_dims.height < @height
          if mouseTop <= @_dims.height*size
            unless top is 0
              newTop = if top > -step then 0 else top+step
              direction = "top"
          else if mouseTop >= @_dims.height*(1-size)
            max = @_dims.height-@height
            if top >= max+0.5
              newTop = if top < max+step then max else top-step
              direction = "bottom"
        
        # move and recurse until mouse leave edges
        if newTop? or newLeft?
          @_container.animate {left:newLeft, top:newTop}, duration
          @_drawHover()
          # loop again, while no other move is detected
          @_onHapticEdge event
          # set cursor
          @_container.addClass "haptic-#{direction}"
        else
          @_container.removeClass "haptic-top haptic-left haptic-bottom haptic-right"
          
      , duration*1.1
      
    # **private**
    # Render indications above items
    _renderIndications: (indic) =>
      if indic.delay
        return _.delay => 
          delete indic.delay
          @_renderIndications indic
        , indic.delay
        
      # add the text into the layer
      rendering = $("<div class='indic #{indic.kind}'>#{if indic.text? then indic.text else ""}</div>").appendTo @_layers.indics
      # positionnate on the relevant tile
      position = @scope.renderer.coordToPos indic.at
      position.left += (@scope.renderer.tileW-rendering.outerWidth())*0.5
      position.top += (@scope.renderer.tileH-rendering.outerHeight())*0.5
      rendering.css position
      
      lifetime = indic.duration or 3000
      # destination
      if indic.dest
        # animate along the path
        lifetime = indic.duration*euclidianDistance indic.at, indic.dest
        # evaluate target position
        target = @scope.renderer.coordToPos indic.dest
        target.left += (@scope.renderer.tileW-rendering.outerWidth())*0.5
        target.top += (@scope.renderer.tileH-rendering.outerHeight())*0.5
        # orient initial shoot which is horizontal left-right toward target
        rendering.css transform: "rotate(#{computeOrientation position, target}rad)"
        # and trigger transition between position and target
        _.defer -> rendering.css _.extend {transition: "all #{lifetime}ms linear"}, target
        
      # removes at end
      _.delay (-> rendering.remove()), lifetime
      # add also animation if rewuired
      if indic.anim
        _.defer -> rendering.css _.extend {animation: "#{indic.anim} #{lifetime}ms"}, position,
      
    # **private**
    # Invoked when dropping blips into the map
    # Get blips coordinates, and trigger scope event
    #
    # @param event [Event] mouse event behind the drop event
    # @param ui [Object] jquery-ui's droppable detailes
    _onDropBlip: (event, ui) =>
      # get the map coordinates
      coord = @scope.renderer.posToCoord @_mousePos event
      @scope?.blipDeployed coord, ui.draggable.data('model') or null
       
    # **private**
    # Key handler, to move selected character
    #
    # @param event [Event] key up event
    _onKey: (event) =>
      # disable if cursor currently in an editable element, or no selection
      return if @scope.selected is null or @scope.activeRule isnt 'move' or event.target.nodeName in ['input', 'textarea', 'select']
      # select current character if shortcut match
      for direction, shortcut of @scope.shortcuts
        if isShortcuts event, shortcut
          # use selected coord
          coord = _.pick @scope.selected, 'x', 'y'
          if direction.indexOf('up') isnt -1
            coord.y++ 
          else if direction.indexOf('down') isnt -1
            coord.y--
          if direction.indexOf('right') isnt -1
            coord.x++ 
          else if direction.indexOf('left') isnt -1
            coord.x--
          @scope.click?(event, @_getInfos event, coord)
          # stop key to avoid browser default behavior
          event.preventDefault()
          event.stopImmediatePropagation()
          return false