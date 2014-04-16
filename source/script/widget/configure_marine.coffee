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
    @$inject: ['$scope', '$filter']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param filter [Object] Angular's filter factory
    constructor: (@scope, filter) ->
      # Fill possible weapons
      if @scope.src.isCommander
        @scope.weapons = ['pistolAxe', 'gloveSword', 'heavyBolter']
      else
        @scope.weapons = ['autoCannon', 'missileLauncher', 'flamer', 'bolter']
      # get label corresponding to weapon
      @scope.getWeaponLabel = (weapon) => filter('i18n') 'labels.'+(weapon || 'chooseWeapon')
        