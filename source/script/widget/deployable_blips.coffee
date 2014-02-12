'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/deployable_blips.html'
  'jquery-ui'
], ($, _, app, template) ->
  
  # The DeployableBlips directive displays how manu blips are available, and can be disabled.
  # A blip handle allow to drag'n drop over the map
  app.directive 'deployableBlips', ->
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # controller
    controller: DeployableBlipsController
    # parent scope binding.
    scope: 
      # label displayed
      label: '@'
      # alien squad concerned
      squad: '='
      # added css className
      className: '='
      # if set to null, disable widget. Otherwise, set the scope used for drag'n drop
      deployScope: '=?'
      
  class DeployableBlipsController
                  
    # Controller dependencies
    @$inject: ['$scope', '$element', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # JQuery enriched element for directive root
    $el: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param rootScope [Object] application root scope, for event binding
    constructor: (@scope, element, rootScope) ->
      @$el = $(element)
  
      # nothing to do now
      @$el.draggable
        appendTo: 'body'
        # do not place draggable under the mouse, because it disabled map hover
        cursorAt:
          left: -5
          top: -5
        revert: 'invalid'
        helper: =>
          @$el.find('.handle').clone().wrap('<div class="deploying-blip"/>').parent()
        start: =>
          # cancel unless we still have blips
          return false unless @scope.number > 0
          
      @scope.$watch 'squad', (value, old) =>
        return unless value? and value isnt old
        # get number of available blips
        @scope.number = _.where(@scope.squad?.members, map: null)?.length or 0
        
      @scope.$watch 'deployScope', (value, old) => 
        return unless value? and value isnt old
        @_toggleDeployment()
        
      # updates number of available blips when member map changed
      rootScope.$on 'modelChanged', (ev, operation, model, changes) => 
        return unless operation is 'update' and 'map' in changes and 'alien' is model?.type?.id
        # it's an update on alien map attribute
        return unless _.find(@scope.squad?.members, (member) -> member?.id is model?.id)?
        # it's an update on a member
        @scope.$apply =>
          @scope.number = _.where(@scope.squad?.members, map: null)?.length or 0
    
    # **private**
    # Toggle drag'n drop scope and activation regarding the widget scope values
    _toggleDeployment: ->
      # change draggable value when scope value changed
      @$el.draggable 'option', 'scope', @scope.deployScope
      @$el.draggable 'option', 'disabled', not @scope.deployScope?