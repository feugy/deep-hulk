'use strict'

define [
  'app'
  'text!template/select.html'
], (app, template) ->
  
  app.directive 'ngSelect', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # selected value
      value: '=?'
      # possible choices
      items: '=?'
      # hover callback, invoked with event and hovered item
      onHover: '=?'
      # change callback, invoked with event and selected item
      onChange: '=?'
      # method that takes an item and returns its label
      getText: '=?'
    # controller
    controller: SelectCtrl
    
  class SelectCtrl
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', '$window']
    
    # Controller scope, injected within constructor
    scope: null
    
    # enriched element for directive root
    element: null

    # **private**
    # Reference to the select HTML menu
    _menu: null
    
    # **private**
    # Flag indicating if the menu is currently displayed
    _menuVisible: false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param window [DOM] reference to window
    constructor: (@scope, @element, window) ->
      unless @scope.getText?
        @scope.getText = (v) -> v or '...'
        
      @_menu = @element.find '.menu'
      @_menuVisible = false

      # use keydown, or tab won't be properly captured
      @element.on 'keydown', @_onKey
        
      @scope.select = (event, item, closeMenu=true) =>
        @scope.value = item
        @scope.closeMenu() if closeMenu
        @scope.onChange?(event, item)
        0 # to avoir returning an element

      @scope.closeMenu = =>
        @_menu.hide()
        @_menuVisible = false
        0 # to avoir returning an element
        
      @scope.openMenu = (event) =>
        @_menuVisible = true
        @_menu.show()
        event?.preventDefault()
        event?.stopImmediatePropagation()
        false # do not bubble orit will closes immediately
        
      # close menu on window click
      window = angular.element window
      window.on 'click', @scope.closeMenu
      @scope.$on '$destroy', => 
        window.off 'click', @scope.closeMenu
        
    # **private**
    # Keyboard management: open/close menu, changes selected item
    #
    # @param event [Event] keyboard event
    _onKey: (event) =>
      switch event.keyCode
        when 9
          # tab: close menu
          @scope.closeMenu()
        when 13, 32
          # space, enter: open or cloe
          if @_menuVisible
            @scope.closeMenu()
          else
            @scope.openMenu()
            @_menu.children().focus()
        when 38, 40
          # arrow down, up:  circular selection within possible items
          idx = @scope.items.indexOf @scope.value
          next = if event.keyCode is 40 then idx+1 else idx-1
          next = 0 if next is @scope.items.length
          next = @scope.items.length-1 if next is -1
            
          @scope.$apply => 
            @scope.select event, @scope.items[next], not @_menuVisible
            @scope.onHover? event, @scope.items[next]