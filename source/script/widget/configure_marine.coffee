'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/configure_marine.html'
], ($, _, app, template) ->
  
  # The configureMarine directive allow marine configuration:
  # - weapon choice
  app.directive 'configureMarine', ->
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
      hoverOption: '=?'
    # controller
    controller: Configure
  
  class Configure
                      
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
      # Fill possible weapons
      if @scope.src.isCommander
        @scope.weapons = ['pistolAxe', 'gloveSword', 'heavyBolter']
      else
        @scope.weapons = ['autoCannon', 'missileLauncher', 'flamer', 'bolter']
      # manually update and do not use ngModel because it insert en ampty option
      @$el = $(element)
      @$el.on 'change', '.weapon', (event) => 
        @scope.$apply => @_updateModel event
           
    # **private**
    # Update the model value according to selected weapons
    #
    # @param event [Event] Modification event
    _updateModel: (event) =>
      @scope.target.weapon = $(event.target).val()