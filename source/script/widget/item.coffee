'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'widget/param'
  'widget/item_tip'
  'jquery-ui'
], ($, _, app) ->
  
  # List of executing animations
  _anims = {}

  # The unic animation loop
  _loop = (time) ->
    # request another animation frame for next rendering.
    window.requestAnimationFrame _loop 
    if document.hidden
      # if document is in background, animations will stop, so stop animations.
      time = null
    # trigger onFrame for each executing animations
    for id, anim of _anims
      anim._onFrame.call anim, time if anim isnt undefined

  # starts the loop at begining of the game
  _loop new Date().getTime()
  
  # The item directive displays individual items on map
  app.directive 'item', ->
    # directive template
    template: '<div class="item ng-class:{selected:selected === model}"></div>'
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # current player squad
      squad: '=?'
      # displayed item model id
      modelId: '@'
      # currently selected item
      selected: '=?'
      # indications rendered on map. 
      # accepts objects with map coordinates (x and y), 'duration' in millis, displayed 'text' and css 'className'
      displayIndications: '=?'
      # Allows dragging during on the relevant scope. Set to null to disabled dragging
      deployScope: '=?'
    
    # controller
    require: 'item'
    controller: Item
    
  class Item
  
    # delay before opening tooltip
    @tooltipDelay = 1000
    
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas', '$compile', '$rootScope']
          
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Link to atlas service
    atlas: null
    
    # Angular directive compiler, for tip directive addition
    compile : null
    
    # **private**
    # Model images specification
    _imageSpec: null

    # **private**
    # number of image sprites
    _numSprites: 1

    # **private**
    # number of steps of the longuest sprite
    _longestSprite: 0
    
    # **private**
    # Currently displayed sprite: name of one of the _imageSpec sprite
    _sprite: null

    # **private**
    # Current sprite image offset
    _offset: {x:0, y:0}
    
    # **private**
    # Animation start timestamp
    _start:null

    # **private**
    # Stored position applied at the end of the next animation
    _newPos: null
    
    # **private**
    # number of item log, to perform comparisons 
    _logLength: 0
    
    # **private**
    # stores previous logs, to perform backward replay
    _previousLog: null
    
    # **private**
    # flag to indicate wether to reload image after animation
    _reloadAfterAnimation: false
    
    # **private**
    # Flag to avoid removing unexistent draggable, or creating it twice
    _isDraggable: false
    
    # **private**
    # Tooltip delay before displayal
    _tipDelay: null
    
    # **private**
    # Delay before tooltip hideout, to allow user reentering
    _tipHideDelay: null
    
    # **private**
    # inhibit update handling when fetching dirty models
    _wasDirty: false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    # @param rootScope [Object] application root scope, for event binding
    constructor: (@scope, element, @atlas, @compile, rootScope) ->
      @_isDraggable = false
      @$el = $(element)
      @_sprite = null
      @_step = 0
      @_offset = x:0, y:0
      @_start = null
      @_newPos = null
      @_reloadAfterAnimation = false
      @_tipHideDelay = null
      @_tipDelay = null
      
      # get model within map items
      @scope.model = _.find @scope.$parent.items, (item) => item.id is @scope.modelId
      @_wasDirty = false
      @_previousLog = @scope.model.log
      
      if @scope.model?.type?.id in ['alien', 'marine']
        @$el.on('mouseenter', @_onHoverItem).on 'mouseleave', @_onLeaveItem
  
      @$el.addClass @scope.model.type.id
      @$el.attr 'id', @scope.model.id
      
      @_logLength = @scope.model?.log?.length
      @_loadImage()
      @_toggleDraggable()
      @_unbind = rootScope.on 'modelChanged', @_onUpdate

      @scope.$on '$destroy', =>
        @_hideTip()
        @_unbind()
      @scope.$watch 'deployScope', (value, old) =>
        return unless value isnt old
        @_toggleDraggable()
        
    # Redraw current item rendering: update position and size
    # @return the jQuery element for this widget, for chaining purposes
    redraw: =>
      map = @scope.$parent      
      return unless map?.renderer?
      @_hideTip()
      
      @$el.css
        width: if @scope.model.dead then 0 else map.renderer.tileW*@_imageSpec?.width
        height: if @scope.model.dead then 0 else map.renderer.tileH*@_imageSpec?.height
        backgroundSize: "#{100*@_longestSprite}% #{100*@_numSprites}%"

      @_positionnate()
      @$el
      
    # **private**
    # On image spec changes, compute number of sprites and longest sprite
    _setImageSpec:  =>
      @_imageSpec = @scope.model.type.images?[@scope.model.imageNum]
      @_numSprites = 1
      @_longestSprite = 1
      if @_imageSpec?.sprites?
        @_numSprites = _.keys(@_imageSpec.sprites).length
        for name, sprite of @_imageSpec.sprites when sprite.number > @_longestSprite
          @_longestSprite = sprite.number

      value = @_imageSpec?.file or @scope.model.type.descImage

    # **private**
    # Allows blip to be dragged during deployement, only for unrevealed aliens
    _toggleDraggable: =>
      return unless @scope.model?.type?.id is 'alien' and not @scope.model.revealed
      
      if @scope.deployScope? 
        unless @_isDraggable
          # nothing to do now
          @$el.draggable
            scope: @scope.deployScope
            appendTo: $('body')
            helper: =>
              $('<div class="deploying-blip"><div class="handle"></div></div>')
            # do not place draggable under the mouse, because it disabled map hover
            cursorAt:
              left: -5
              top: -5
            start: =>
              # set data to allow redeployement
              @$el.data 'model', @scope.model
          # because of jQueryUI bug http://bugs.jqueryui.com/ticket/9388
          @$el.css 'position', 'absolute'
          @_isDraggable = true
      else if @_isDraggable
        @_isDraggable = false
        @$el.draggable 'destroy'
        
    # **private**
    # Load displayed image for this item
    _loadImage: =>
      # no image num, no rendering.
      if @scope.model.imageNum is null
        return @$el.css background: "none", width: 0, height: 0
        
      @_setImageSpec()
      img = @_imageSpec?.file or @scope.model.type.descImage
      unless img?
        # no image, no rendering
        return @$el.css background: "none", width: 0, height: 0
      
      @atlas.imageService.load conf.imagesUrl + img, (err, key) =>
        unless err?
          # loading success TODO manage errors
          @$el.css 
            background: "url(#{@atlas.imageService.getImageString key})"
        
        # now display correct sprite
        @redraw()
        @_renderSprite()
          
    # **private**
    # Compute and apply the position of the current widget inside its map widget.
    # In case of position deferal, the new position will be slighly applied during next animation
    #
    # @param defer [Boolean] allow to differ the application of new position. false by default
    _positionnate: (defer = false) =>
      map = @scope.$parent
      # only if parent is a map
      return unless map?.renderer?
                  
      # get the widget cell coordinates
      pos = map.renderer.coordToPos x: @scope.model.x, y: @scope.model.y
      
      # center horizontally with tile, and make tile bottom and widget bottom equal
      if @_imageSpec?
        pos.left += map.renderer.tileW*(1-@_imageSpec.width)/2 unless @scope.model.noHCenter
        pos.top += map.renderer.tileH*(1-@_imageSpec.height)
        
      # add z-index specific rules
      map.renderer.applyStackRules @scope.model, pos

      if defer 
        # do not apply immediately the new position
        @_newPos = pos
      else
        @$el.css pos
    
    # **private**
    # Shows relevant sprite image regarding the current model animation and current timing
    #
    # @param reload [Boolean] trigger reload at animation end
    _renderSprite: (reload = false)=>
      return unless @_imageSpec?
      @_reloadAfterAnimation = reload
      
      # do we have a transition ?
      transition = @scope.model.getTransition()
      transition = null unless @_imageSpec.sprites? and transition of @_imageSpec.sprites
      # gets the item sprite's details.
      if transition? and _.isObject @_imageSpec.sprites
        @_sprite = @_imageSpec.sprites[transition]
      else
        @_sprite = null

      @_step = 0
      # set the sprite row
      @_offset.x = 0
      @_offset.y = if @_sprite? then -@_sprite.rank * @_imageSpec.height else 0

      # no: just display the sprite image
      @$el.css backgroundPosition: "#{@_offset.x}% #{@_offset.y}%"
      return @_onLastFrame() unless transition?

      # yes: let's start the animation !
      @_start = new Date().getTime()

      # if we moved, compute the steps
      if @_newPos?
        @_newPos.stepL = (@_newPos.left-parseInt @$el.css 'left')/@_sprite?.number
        @_newPos.stepT = (@_newPos.top-parseInt @$el.css 'top')/@_sprite?.number

      if document.hidden
        # document not visible: drop directly to last frame.
        @_onLastFrame()
      else 
        # adds it to current animations
        _anims[@scope.model.id] = @

    # **private**
    # frame animator: invokated by the animation loop. If it's time to draw another frame, to it.
    # Otherwise, does nothing
    #
    # @param current [Number] the current timestamp. Null to stop current animation.
    _onFrame: (current) =>
      return unless @_imageSpec? and @_sprite?
      # loop until the end of the animation
      if current? and current-@_start < @_sprite.duration
        # only animate at needed frames
        if current-@_start >= (@_step+1)*@_sprite.duration/(@_sprite.number+1)
          # changes frame 
          @_offset.x = @_step%@_sprite.number*-100

          @$el.css backgroundPosition: "#{@_offset.x}% #{@_offset.y}%"
          # Slightly move during animation
          if @_newPos?
            @$el.css 
              left: @_newPos.left-@_newPos.stepL*(@_sprite.number-@_step)
              top: @_newPos.top-@_newPos.stepT*(@_sprite.number-@_step)
              
          @_step++
      else 
        @_onLastFrame()

    # ** private**
    # Apply last frame: display sprite's first position, end movement
    _onLastFrame: =>
      # removes from executing animations first.
      delete _anims[@scope.model.id]
      # if necessary, apply new position
      if @_newPos
        delete @_newPos.stepL
        delete @_newPos.stepT
        @$el.css @_newPos
        @_newPos = null
      
      @_offset.x = 0
      # reloads if necessary
      if @_reloadAfterAnimation
        @_reloadAfterAnimation = false
        @_loadImage() 
      else
        # end of the animation: displays first sprite
        @$el.css backgroundPosition: "#{@_offset.x}% #{@_offset.y}%"

          
    # **private**
    # Updates model inner values: adapt position and image num
    # If a deletion is received, removes the widget
    #
    # @param event [Event] model update event
    # @param kind [String] operation kind: creation, update or deletion
    # @param model [Model] model updated
    # @param changes [Array<String] array of attributes that have been modified
    _onUpdate: (event, kind, model, changes) =>
      # inhibit model update while fetching dirty models
      return unless model?.id is @scope.model?.id and not @_wasDirty
      
      # deletion received: delay removal to let animation be rendered
      if kind is 'deletion'
        @scope.$destroy()
        return @$el.remove()
      
      next = (event, kind, model, changes) =>
        return unless changes?
        # adapt new position if necessary
        @_positionnate('transition' in changes) if 'x' in changes or 'y' in changes
        # console.log "received changes for model #{model.type.id} (#{model.id}): ", changes
        
        if 'log' in changes
          logs = []
          
          if @_logLength < model.log.length
            logs = model.log[@_logLength..]
          else if @atlas.replayPos
            logs = @_previousLog[@_previousLog.length-1..]
          
          # display indications if available
          if logs.length > 0
            indics = []
            for log, i in logs
              # split into two indication: damages and loss
              indics.push 
                kind: 'damages'
                at: log.at
                duration: 3000
                delay: 300
                text: log.damages
              if log.loss > 0
                indics.push
                  kind: 'loss'
                  at: log.at
                  duration: 3000
                  delay: 500
                  text: "-#{log.loss}"
              # display also animation
              if log.kind is 'assault'
                indics.push {at: log.at, duration: 500, kind: log.kind, anim: log.kind}
              else if log.kind is 'shoot'
                indics.push {dest: log.at, at: log.from, duration: 50, kind: log.kind}
            @scope.displayIndications indics
            
          # update inner values
          @_logLength = model.log.length
          @_previousLog = model.log.concat()
          
        needsReload = 'imageNum' in changes or 'dead' in changes
        if 'transition' in changes
          # render new animation if needed
          @_renderSprite needsReload 
        else if 'dead' in changes
          # defer reloading until animation will be triggered
          _.delay @_loadImage, 500
        else if needsReload
          # renderSprite will reload if necessary
          @_loadImage()
          
      # if dirty, resolve model before processing.
      if model.__dirty__ and not @atlas.replayPos
        @_wasDirty = true
        console.log "fetch dirty item #{model.id} (#{model.type.id}) before update", changes
        return model.constructor.fetch [model.id], (err, [model]) =>
          return console.error err if err?
          @_wasDirty = false
          next event, kind, model, changes
      
      next event, kind, model, changes
        
    # **private**
    # On item (or tip) entering, display tip (or cancel its closure)
    _onHoverItem: =>
      if @_tipHideDelay
        # cancel tip closure
        clearTimeout @_tipHideDelay
        @_tipHideDelay = null
      else unless @_tip?
        @_tipDelay = _.delay @_showTip, Item.tooltipDelay
        
    # **private**
    # On item (or tip) leaving, start tip closure (or cancel tip opening)
    _onLeaveItem: =>
      clearTimeout @_tipDelay
      # delay to let mouse reentering
      @_tipHideDelay = _.delay @_hideTip, 200
      
    # **private**
    # Show information tooltip.
    _showTip: =>
      @scope.$apply =>
        @_tip = @compile("<item-tip data-squad='squad' data-src='model'/>") @scope
        pad = 20
        # item position and dimensions
        pos = @$el[0].getBoundingClientRect()
        # screen dimensions
        screen = width: $('body').width(), height: $('body').height()
        # first attempt: tip at left
        result = 
          right: screen.width-pos.right+pos.width+pad
          top: pos.top+pad
        # too close to screen left: goes right
        if pos.left < 200
          delete result.right
          result.left = pos.left+pos.width+pad
        # too close to screen bottom: goes up
        if pos.top > screen.height-500
          delete result.top
          result.bottom = screen.height-pos.bottom+pad
        # positionnate into body
        @_tip.css result
        @_tip.on('mouseenter', @_onHoverItem).on 'mouseleave', @_onLeaveItem
        
        @_tipHideDelay = null
        $('body').append @_tip
      
    # **private**
    # Hide information tooltip.
    _hideTip: =>
      @_tipHideDelay = null
      return unless @_tip?
      @_tip.off()
      @_tip.remove()
      @_tip = null