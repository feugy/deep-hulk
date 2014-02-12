'use strict'

define [
  'app'
  'text!template/log.html'
], (app, template) ->
  
  app.directive 'log', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      log: '=?src'
      open: '@?'
    # controller
    controller: Log
    
  class Log
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', '$attrs', '$animate']
    
    # Controller scope, injected within constructor
    scope: null
    
    # enriched element for directive root
    element: null
    
    # **private**
    # To avoid opening on log initialization
    _initialized: false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    constructor: (@scope, @element, attrs, @animate) ->
      @_initialized = false
      @scope.toggle = @_toggle
      
      # parse into boolean
      attrs.$observe 'open', (val) => 
        @scope.open = 'true' is val?.toLowerCase()?.trim()
        
      @scope.$watch 'open', =>
        @animate[if @scope.open then 'addClass' else 'removeClass'] @element, 'ng-show'
      
      # on src change, force opening, but not immediately on directive creation
      @scope.$watchCollection 'log', => 
        return @_initialized = true unless @_initialized
        @_toggle true
  
    # **private**
    # Opens or closes log widget, depending on the current state
    #
    # @param isOpen [Boolean] true or false to force opening/closing. Anything else will invert current state
    _toggle: (isOpen) =>
      unless isOpen in [true, false]
        isOpen = not @scope.open
      @scope.open = isOpen