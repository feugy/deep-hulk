'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/cursor.html'
], ($, _, app, template) ->
  
  # The map directive displays map with fields and items
  app.directive 'cursor', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # Currently selected squad members
      selected: '=?'
      # Map renderer used to compute positions
      renderer: '=?'
      # current map zoom
      zoom: '=?'
      # active rule selection handler
      selectActiveRule: '=?'
      # ask rule execution
      askToExecuteRule: '=?'
      # method to get widget corresponding to selected Item
      getSelectedWidget: '=?'
          
    # controller
    controller: CursorController
      
  # Base widget for interactive cursor.
  class CursorController
              
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
        
    # Link to Atlas service
    atlas: null
    
    # JQuery enriched element for directive root
    $el: null

    # rear part of the cursor, in a separate element to have different z-orders
    _rear: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    # @param rootScope [Object] Angular root scope
    constructor: (@scope, element, @atlas, rootScope) ->
      @$el = $(element)
      @scope.activeRule = null
      @scope.canOpenDoor = false
      @scope.canShoot = false
      @scope.canFight = false
      @scope._onActivate = @_onActivate
      @scope._onOpen = @_onOpen
      @scope.isBlip = false
      @scope.rcNum = []
      
      @_rear = $('<div class="cursor rear"/>')
            
      # update on replay quit/enter
      rootScope.$on 'replay', (ev, details) => @_render true
      
      # redraw content when map or its dimension changes
      @scope.$watch 'selected', (value, old) =>
        return unless value isnt old
        @scope.isBlip = value?.revealed is false
        @scope.canOpenDoor = value?.doorToOpen?
        if @scope.activeWeapon > value?.weapons?.length
          @scope.activeWeapon = 0 
        # evaluate weapons that can have been already used
        @_updateUsed value
        # shoot possible if at least one weapon have range capacity
        @scope.canShoot = value?.revealed isnt false and _.any value?.weapons, (weapon) -> weapon.rc?
        # use first weapon for close combat
        @scope.canAssault = value?.revealed isnt false and value?.weapons[0]?.cc?
        isBig = value?.revealed is true and value?.kind is 'dreadnought'
        @_rear.toggleClass 'is-big', isBig
        @$el.toggleClass 'is-big', isBig
        if @scope.activeRule?
          @scope.activeRule = null
          @scope.selectActiveRule?(null, @scope.activeRule) 
        @_render true
        
      # update openable door when selected model changed
      rootScope.$on 'modelChanged', @_onModelChanged
      @_render()
          
    # **private**
    # If selected character is updated:
    # - update open door action
    # - update position
    # - update move/shoot/assault activation
    #
    # @param event [Event] change event
    # @param operation [String] operation kind: 'creation', 'update', 'deletion'
    # @param model [Model] concerned model
    # @param changes [Array<String>] name of changed property for an update
    _onModelChanged: (ev, operation, model, changes) => 
      switch operation
        when 'update'
          if model?.id is @scope.selected?.id
            @scope.$apply =>
              @scope.isBlip = model?.revealed is false
              @scope.canShoot = model?.revealed isnt false and _.any model?.weapons, (weapon) -> weapon.rc?
              # use first weapon for close combat
              @scope.canAssault = model?.revealed isnt false and model?.weapons[0]?.cc?
              if 'doorToOpen' in changes
                @scope.canOpenDoor = model.doorToOpen?
              if 'revealed' in changes
                isBig = model?.revealed is true and model?.kind is 'dreadnought'
                @_rear.toggleClass 'is-big', isBig
                @$el.toggleClass 'is-big', isBig
              if ('usedWeapons' in changes or 'rcNum' in changes) and model?.usedWeapons?
                @_updateUsed model
              if 'x' in changes or 'y' in changes
                # positionnate
                @$el.addClass 'movable'
                @_rear.addClass 'movable'
                @_render()
                @$el.one 'transitionend', =>
                  @$el.removeClass 'movable'
                  @_rear.removeClass 'movable'
              @_onActivate null, @scope.activeRule, @scope.activeWeapon
        
    # **private**
    # Set given rule as active if allowed
    # 
    # @param evt [Event] click event
    # @param rule [String] expected rule to be active
    # @param weapon [Numer] selected weapon rank (in weapons) to use in case of shoot
    _onActivate: (evt, rule, weapon = 0) =>
      evt?.stopImmediatePropagation()
      old = @scope.activeRule
      oldWeapon = @scope.activeWeapon
      @scope.activeWeapon = weapon
      switch rule
        when 'move' 
          @scope.activeRule = if @scope.selected.moves > 0 then rule else null
          break
        when 'shoot' 
          @scope.activeRule = if @scope.canShoot and @scope.selected.rcNum > 0 then rule else null
          break
        when 'assault' 
          @scope.activeRule = if @scope.canAssault and @scope.selected.ccNum > 0 then rule else null
          break
        else 
          @scope.activeRule = null
      if old isnt @scope.activeRule or oldWeapon isnt @scope.activeWeapon
        @scope.selectActiveRule?(evt, @scope.activeRule, @scope.activeWeapon)
      
    # **private**
    # Ask to opens a door, if is open is available
    _onOpen: (evt) =>
      evt?.stopImmediatePropagation()
      if @scope.canOpenDoor
        @scope.askToExecuteRule?('open')
                
    # **private**
    # Update rcNum array in scope, that contains number of shoot per weapon 
    # (same order that weapons array)
    #
    # @param model [Model] displayed item
    _updateUsed: (model) =>
      if model?.usedWeapons?
        used = JSON.parse model.usedWeapons
        @scope.rcNum = []
        for weapon, i in model.weapons
          @scope.rcNum[i] = model.rcNum
          if i in used
            @scope.rcNum[i]-- 
            if @scope.activeWeapon is i
              # current weapon is used: disabled current rule
              @scope.activeWeapon = 0
              @scope.activeRule = null
    
    # **private**
    # Re-builds rendering, with optional animation
    # @param animate [Boolean] true to animate disapearance and appearance
    _render: (animate = false)=>
      next = =>
        wasHidden = not @$el.is ':visible'
        # hide if no selected
        unless @scope.selected? and not @atlas.replayPos?
          @_rear.hide().appendTo @$el
          return @$el.hide()
          
        # positionnate front and rear part
        pos = @scope.renderer.coordToPos @scope.selected
        pos.transform = "scale(#{@scope.zoom})"
        pos['-webkit-transform'] = pos.transform
        
        @$el.css(pos).show()
        @_rear.css(pos).show()
        addClasses = =>
          @$el.addClass 'animated'
          @_rear.addClass 'animated'
          
        if wasHidden and animate
          _.delay addClasses, 100
        else
          addClasses()
          
      @scope.getSelectedWidget()?.$el.before @_rear
      # removes with animation if necessary
      wasAnimated = @$el.hasClass 'animated'
      if wasAnimated and animate
        @$el.removeClass 'animated'
        @_rear.removeClass 'animated'
        @$el.one 'transitionend', next
      else
        next()