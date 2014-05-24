'use strict'

define [
  'app'
  'widget/short_game'
  'text!template/scores.html'
], (app, ShortGame, template) ->
  
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
    controllerAs: 'ctrl'
    
  class Scores extends ShortGame
                  
    # Controller dependencies
    @$inject: ['$scope', '$filter', 'players', 'atlas', '$location']
    
    # Angular service for navigation
    location: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive outer scope
    # @param filter [Function] Angular's filter factory
    # @param players [Object] Players service
    # @param atlas [Object] Atlas service
    # @param location [Object] Angular service for navigation
    constructor: (scope, filter, players, atlas, @location) ->
      super(scope, filter, players, atlas)
        
    # Navigate back to home screen
    back: =>
      @location.path("#{conf.basePath}home").search {}