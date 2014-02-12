'use strict'

define [
  'underscore'
  'util/common'
], (_, {getInstanceImage, parseError}) ->
  
  class HomeController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', 'atlas', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Link to Atlas service
    atlas: null
    
    # Link to location service
    location: null
    
    # **private**
    # Previous mission selected
    _previousMission: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param atlas [Object] Atlas service
    # @param rootScope [Object] Angular root scope
    constructor: (@scope, @location, @atlas, rootScope) -> 
      @scope.player = atlas.player
      err = @location.search()?.err or null
      @scope.error = null
      @scope.missions = []
      @scope.error = decodeURIComponent err if err?
      @onHideRule()
      # bind methods
      @scope.closeError = @closeError
      @scope.onNewGame = @_onResolveRule
      @scope.onAskJoin = @_onResolveRule
      @scope.onCreateGame = @_onExecuteRule
      @scope.onJoinGame = @_onExecuteRule
      @scope.onHideRule = @onHideRule
      @scope.onMissionSelected = @_onMissionSelected
      # compute squad image
      @scope.getInstanceImage = getInstanceImage
      
      # update openable door when selected model changed
      rootScope.$on 'modelChanged', @_onModelChanged
      
      # fetch player games names
      @atlas.Item.fetch atlas.player.characters, (err, currentGames) => @scope.$apply =>
        return @scope.error = parseError err.message if err?
        @scope.player.characters = currentGames
        @_fetchFreeGames()
       
    # Remove the current error, which hides the alert
    closeError: =>
      @scope.error = null
    
    # Hides creation panel
    onHideRule: =>
      @scope.currentRule = null
      @scope.currentRuleName = null
      @scope.ruleParams = null
      @scope.target = null
      
    # **private**
    # When select a given mission, set the allowed squads in consequence
    _onMissionSelected: =>
      unless @scope.currentRuleName is 'creation' and @scope.ruleParams?.mission? and 
          @scope.ruleParams.mission isnt @_previousMission
        return
      @_previousMission = @scope.ruleParams.mission
      param = _.findWhere @scope.currentRule.params, name:'squad'
      param.within = _.invoke _.findWhere(@scope.missions, id:@_previousMission)?.squads?.split(','), 'trim'
      
    # **private**
    # Fetch free games. Once retrieved, model change is issued to refresh rendering
    _fetchFreeGames: =>
      # search for free games
      @atlas.Item.fetch ['freeGames'], (err, [freeGames]) => 
        err = new Error "free games list not found" if !err? and !freeGames?
        return @scope.$apply (=> @scope.error = parseError err.message) if err?
        @_onModelChanged null, 'update', freeGames, ['games']

    # **private**
    # Resolve a given 'init' rule. may have a optionnal target
    # The applicable rule is stored
    #
    # @param target [Item] optionnal resolution target
    _onResolveRule: (target) =>
      @scope.target = target or null
      end = (err, applicable) => 
        @scope.$apply =>
          return @scope.error = parseError err.message if err?
          @scope.ruleParams = {}
          @scope.currentRuleName = _.keys(applicable)?[0] or null
          @scope.currentRule = applicable?[@scope.currentRuleName]?[0] or null
          
          if @scope.currentRuleName is 'creation'
            # creation specificity: ask for missions
            params = applicable[@scope.currentRuleName][0].params
            @atlas.Item.fetch _.find(params, (p) -> p.name is 'mission').within, (err, missions) => @scope.$apply =>
              err = new Error "mission list not found" if !err? and missions?.length is 0
              return @scope.error = parseError err?.message if err?
              @scope.missions = missions
              
      # resolve rules, and search for 'creation' one
      if @scope.target?
        @atlas.ruleService.resolve @atlas.player, @scope.target, ['init'], end
      else
        @atlas.ruleService.resolve @atlas.player, ['init'], end
              

    # **private**
    # Execute the current rule with current parameters
    _onExecuteRule: =>
      end = (err, result) =>
        @scope.$apply =>
          return @scope.error = parseError err.message if err?
          # extract concerned game id
          gameId = null
          if @scope.currentRuleName is 'join'
            gameId = @scope.target.id
          else if @scope.currentRuleName is 'creation'
            gameId = result
          # reset displayal
          @closeError()
          @onHideRule()
          # navigate to game if possible
          @location.path("#{conf.basePath}board").search id:gameId if gameId?
      # execute rule with appropriate parameters
      if @scope.target?
        @atlas.ruleService.execute @scope.currentRuleName, @atlas.player, @scope.target, @scope.ruleParams, end
      else
        @atlas.ruleService.execute @scope.currentRuleName, @atlas.player, @scope.ruleParams, end
                   
    # **private**
    # Multiple behaviour when model update is received:
    # - update free games list
    #
    # @param event [Event] change event
    # @param operation [String] operation kind: 'creation', 'update', 'deletion'
    # @param model [Model] concerned model
    # @param changes [Array<String>] name of changed property for an update
    _onModelChanged: (ev, operation, model, changes) => 
      switch operation
        when 'update'
          if model?.id is 'freeGames' or model?.id is @scope.player.id and 'characters' in changes
            @atlas.Item.findById 'freeGames', (err, freeGames) =>
              return console.error err if err?
              games = []
              for game in freeGames.games
                if _.isString game
                  # fetch game
                  return @_fetchFreeGames()
                else unless _.find(@scope.player.characters, (squad) -> (squad.game.id or squad.game) is game.id)
                  # do not add game where player already participate
                  games.push game
              @scope.$apply => @scope.freeGames = games
              
            