'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/character_details.html'
], ($, _, app, template) ->
  
  # The characterDetails directive displays character state::
  # For marines: name, weapon, currents moves and attacks
  # For aliens, and only if revealed: kind, current moves and attacks
  app.directive 'characterDetails', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # controller
    controller: CharacterDetails
    # parent scope binding.
    scope: 
      # displayed character
      src: '='
      # link to selected character on map
      selected: '=?'
      
  class CharacterDetails
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', '$rootScope', '$filter']
    
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Angular's filter factory
    filter: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param rootScope [Object] application root scope, for event binding
    # @param filter [Object] Angular's filter factory
    constructor: (@scope, element, rootScope, @filter) ->
      @$el = $(element)
      
      @scope.isAlien = @scope.src?.type?.id is 'alien'
      @scope.onSelect = =>
        # toggle selection
        if @scope.selected is @scope.src
          @scope.selected = null
        else
          @scope.selected = @scope.src
      
      # initial hide element unless it's on map
      @$el.toggle @scope.src?.map?
      rootScope.$on 'modelChanged', @_onModelChanged
      
      # init name      
      if @scope.isAlien
        _.defer => @_onModelChanged null, 'update', @scope.src, ['revealed']
      else
        @scope.name = scope.src?.name
      
    # **private**
    # Update displayed name, or toggle widget visibility regarding the map value
    #
    # @param ev [Event] change event
    # @param operation [String] 'creation', 'update' or 'deletion' of the concerned model
    # @param model [Object] the concerned model
    # @param changes [Array<String>] for updates, list of modified property names
    _onModelChanged: (ev, operation, model, changes) => 
      # quit unless a map update of this current character
      return unless operation is 'update' and model?.id is @scope.src?.id
      # no map, or dead: no rendering
      if 'map' in changes
        @$el.toggle @scope.src?.map?
      if 'revealed' in changes
        @scope.$apply => 
          @scope.name = if @scope.src.revealed then @filter('i18n') "labels.#{@scope.src.kind}" else @filter('i18n') 'labels.blip'
