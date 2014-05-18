'use strict'

define [
  'underscore'
], (_) ->
  
  # store previous route globally
  previousRoute = 
    name: 'home'
    params: {}
  
  class RulesController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', '$compile', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param compile [Object] Angular directive compiler
    # @param rootScope [Object] Angular root scope used to get navigation events
    constructor: (@scope, location, compile, rootScope) -> 
      # make a deep copy because we'll modifies images
      @scope.paragraphs = (_.extend {}, p for p in conf.texts.rules)
      # compiles directive in content
      for paragraph in @scope.paragraphs
        paragraph.content = paragraph.content.replace /image\//g, "#{conf.rootPath}image/"
      
      @scope.selected = null
      # defer to allow animation
      _.delay => 
        @scope.$apply =>
          @scope.selected = _.findWhere(@scope.paragraphs, anchor: location.hash()) or @scope.paragraphs[0]
      , 250
      
      if rootScope.previousRoute?.name isnt 'rules'
        previousRoute.name = rootScope.previousRoute?.name or 'home'
        previousRoute.params = rootScope.previousRoute?.params or {}
        @scope.navAnimated = true
      else
        @scope.navAnimated = false
      
      @scope.back = =>
        # go back on game or on home if no game available
        location.path("#{conf.basePath}#{previousRoute.name}").search(previousRoute.params).hash null