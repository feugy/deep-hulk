'use strict'

define [
  'app'
  'util/common'
  'text!template/help.html'
], (app, {getInstanceImage}, template) ->
  
  app.directive 'help', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      help: '=?src'
    # controller
    controller: Help
    
  class Help
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas']
    
    # Controller scope, injected within constructor
    scope: null
    
    # enriched element for directive root
    element: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    constructor: (@scope, @element, atlas) ->
      # to close, simply clear the help content
      @scope.close = => 
        @_displayNext()
        
      @scope.discard = =>
        atlas.ruleService.execute 'discardHelp', atlas.player, {}, (err, result) => @scope.$apply =>
          console.error err if err?
          @_stack = []
          @_displayNext()
        
      @_stack = []
        
      # at startup, hides help
      @element.hide()
      @scope.$watch "help", (value, old) =>
        return unless value isnt old
        if value?
          value = [value] unless angular.isArray value
          @_stack = @_stack.concat value
        @_displayNext() unless @scope.current?.button?
          
    # **private**
    # Display next help message, or hides if needed.
    _displayNext: =>
      if @_stack.length is 0
        # hide help
        @element.hide()
        @scope.current = null
      else
        # get next message to display
        @scope.current = @_stack.shift()
        # positionnate
        pos = top: '5%', left: '5%', bottom: '', right: ''
        switch @scope.current.vPos
          when 'bottom'
            pos.bottom = "5%"
            pos.top = ''
          when 'center'
            pos.top = '25%'
        switch @scope.current.hPos
          when 'right'
            pos.right = "5%"
            pos.left = ''
          when 'center'
            pos.left = '25%'
        # show help
        @element.css(pos).show()
      null