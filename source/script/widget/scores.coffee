'use strict'

define [
  'app'
  'util/common'
  'text!template/scores.html'
], (app, {getInstanceImage, getPlayerName}, template) ->
  
  app.directive 'scores', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      game: '=?src'
    # controller
    controller: Scores
    
  class Scores
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', '$location']
    
    # Controller scope, injected within constructor
    scope: null
    
    # enriched element for directive root
    element: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param location [Object] Angular service for navigation
    constructor: (@scope, @element, @location) ->
      @scope.getInstanceImage = getInstanceImage
      @scope.getPlayerName = getPlayerName
      @scope.back = =>
        @location.path("#{conf.basePath}home").search {}
      @scope.hasActions = (squad) =>
        console.log "check #{squad.name}, #{squad.activeSquad}, #{@scope.game.singleActive}"
        if @scope.game?.singleActive
          squad.activeSquad is squad.name
        else
          squad.actions > 0