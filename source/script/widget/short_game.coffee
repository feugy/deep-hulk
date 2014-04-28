'use strict'

define [
  'app'
  'text!template/short_game.html'
], (app, template) ->
      
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
      current: '=?'  
      game: '=?src'
    # controller
    controller: ShortGame
  
  class ShortGame 
    # Controller dependencies
    @$inject: ['$scope', 'players']
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    constructor: (@scope, players) ->
      @_players = {}
      @scope.squadImage = @_squadImage
      @scope.getPlayerName = players.getPlayerName
      @scope.isPlayerConnected = players.isPlayerConnected
      
    # **private**
    # Compute squad image of a given squad
    #
    # @param squad [String] squad name
    _squadImage: (squad, element) =>
      # not very maintainable, but we don't have the squad image
      switch squad
        when 'ultramarine' then num = 1
        when 'imperialfist' then num = 2
        when 'bloodangel' then num = 3
        else num = 0
      "#{conf.imagesUrl}squad-#{num}.png"