'use strict'

define [
  'app'
  'util/common'
  'text!template/short_game.html'
], (app, {getInstanceImage}, template) ->
      
  app.directive 'shortGame', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # reuse inner content
    transclude: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      game: '=?src'
    # controller
    controller: ShortGame
    controllerAs: 'ctrl'

  class ShortGame
                  
    # Controller dependencies
    @$inject: ['$scope', '$filter', 'players', 'atlas']
    
    # Players service knowing which are connected.
    players: null
    
    # Link to Atlas service
    atlas: null
    
    # Angular's filter factory
    filter: null
    
    # flag indicating that squad were fetched
    _fetched: false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive outer scope
    # @param filter [Function] Angular's filter factory
    # @param players [Object] Players service
    # @param atlas [Object] Atlas service
    constructor: (scope, @filter, @players, @atlas) ->
      Object.defineProperty @, 'game', enumerable: true, get: -> scope.game,
      @_fetched = false
      
      # resolve game if squads where not yet resolved
      scope.$watch 'game', (value, old) =>
        return unless not @_fetched and @game?.squads?
        @_fetched = true
        # once an unresolved squad is detected, ask fot whole game resolution
        for squad in @game.squads when angular.isString squad
          return @atlas.Item.fetch [@game.id]
        
    # Get image of a given squad
    getImage: getInstanceImage

    # Enrich game's involved players (players that has already join) with full squad model.
    # Allows to display scores and activity.
    #
    # @return an array containing for each involved players squad, squadObj and player.
    getInvolved: =>
      involvedSquads = []
      return involvedSquads unless @_fetched
      for involved in @game.players when involved.squad?
        involved.squadObj = squad for squad in @game.squads when squad.name is involved.squad
        involvedSquads.push involved
      #console.log '>> involved', @game.name, involvedSquads
      involvedSquads
      
    # Return tooltip for a given squad, with squad name, player name and score
    #
    # @param squad [Object] concerned squad model
    # @return tooltip text
    getTip: (squad) =>
      return '' unless squad?.player?
      @filter('i18n') 'labels.scoreAndPlayer', args:
        player: @players.getPlayerName squad.player
        squad: @filter('i18n') "labels.#{squad.name}"
        points: squad.points
    
    # Compute CSS classes that apply to a given squad: 
    # - connected if squad player is currently connected
    # - active if squas has action left or need to play
    #
    # @param [squad] The conxerned squad
    # @return an array of css classes
    getState: (squad) =>
      state = []
      return state unless squad?
      unless squad.deployZone?
        if @game?.singleActive 
          state.push 'active' if squad.activeSquad is squad.name
        else
          state.push 'active' if squad.actions > 0
      else
        state.push 'active' if squad.isAlien
      if @players.isPlayerConnected squad.player
        state.push 'connected'
      if squad.player is @atlas.player.email
        state.push 'me'
      state