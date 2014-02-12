'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/param.html'
], ($, _, app, template) ->
  
  app.directive 'param', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      src: '='
      target: '='
      change: '=?'  
    # controller
    controller: Param
    
  class Param
                  
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
      @scope.$watch 'src', @_refresh
      @scope.$watch 'src.within', @_refresh
  
    # **private**
    # Refresh scop values (and rendering) to reflect param source changes
    _refresh: =>
      return unless @scope.src?
      # initialize target value if needed
      @scope.target[@scope.src.name] = null unless @scope.target[@scope.src.name]?
      switch @scope.src.type
        when 'string' 
          @scope.type = if 'within' of @scope.src then 'select-string' else 'string'
        when 'integer', 'float'
          @scope.type = 'number'
        # TODO  text, boolean, date, time, datetime, object