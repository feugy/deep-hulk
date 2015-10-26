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
    @$inject: ['$scope', '$location', '$rootScope', '$filter']
        
    # List of paragraph displayed
    paragraphs: null
    
    # Currently displayed paragraph
    selected: null
    
    # Link to Angular's location provider
    location: null
    
    # inhibit nav animation when switching paragraphs
    navAnimated: true
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param rootScope [Object] Angular root scope used to get navigation events
    # @param filter [Object] Angular's filter factory
    constructor: (scope, @location, rootScope, filter) -> 
      document.title = filter('i18n') 'titles.rules'
      # make a deep copy because we'll modifies images
      @paragraphs = (_.extend {}, p for p in conf.texts.rules)
      # compiles directive in content
      for paragraph in @paragraphs
        paragraph.content = paragraph.content.replace /image\//g, "#{conf.rootPath}image/"
      
      @selected = null
      
      if rootScope.previousRoute?.name isnt 'rules'
        previousRoute.name = rootScope.previousRoute?.name or 'home'
        previousRoute.params = rootScope.previousRoute?.params or {}
        @navAnimated = true
      else
        @navAnimated = false
        
      # defer to allow animation
      _.delay => 
        scope.$apply =>
          @selected = _.findWhere(@paragraphs, anchor: @location.hash()) or @paragraphs[0]
      , 250
  
    # return back without full page reload
    back: =>
      # go back on game or on home if no game available
      @location.path("#{conf.basePath}#{previousRoute.name}").search(previousRoute.params).hash null