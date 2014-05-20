'use strict'

define [
  'underscore'
  'util/common'
], (_, {getInstanceImage}) ->
  
  # Displays game end summary. Game id as url parameter
  # Navigate to home if game doesn't exists, or to board if game isn't finished
  class EndController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', 'atlas']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Link to Atlas service
    atlas: null
    
    # Link to Angular location service
    location: null
    
    # Angular's filter factory
    filter: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param atlas [Object] Atlas service
    # @param filter [Object] Angular's filter factory
    constructor: (@scope, @location, @atlas, @filter) ->
      @scope._onBackHome = @_onBackHome
      @scope.getInstanceImage = getInstanceImage
      @scope.current = @atlas.player.email
      
      # redirect to home if no id
      gId = @location.search()?.id
      return @location.path("#{conf.basePath}home").search({}) unless gId? 
      
      # search for game details
      @atlas.Item.fetch [gId], (err, [game]) => @scope.$apply =>
        # redirect to home if not found
        err = "game not found: #{gId}" if !err? and !game?
        return @location.path("#{conf.basePath}home").search err: err if err?
        # redirect to board if not finished
        return @location.path "#{conf.basePath}board" unless game.finished
        
        document.title = @filter('i18n') 'titles.app', args: [game.name]
        @scope.game = game
      
    # **private**
    # Handler invoked when a clicking on the back button.
    # Navigate to home page.
    _onBackHome: =>
      # if already confirmed, just quit
      for squad in @scope.game.squads when squad.player is @atlas.player.email
        console.log squad
        return @location.path("#{conf.basePath}home").search {} if squad.finished
  
      # confirm game end
      @atlas.ruleService.execute 'endOfGame', @atlas.player, @scope.game, {}, (err) =>
        # silent error
        console.error err if err?
        @location.path("#{conf.basePath}home").search {}