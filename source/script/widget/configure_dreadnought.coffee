'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/configure_dreadnought.html'
  'widget/configure_marine'
], ($, _, app, template, Configure) ->
  
  # The configureDreadnought directive allow dreadnought configuration:
  # - first weapon choice
  # - second weapon choice
  app.directive 'configureDreadnought', ->
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
    controller: ConfigureDreadnought
  
  class ConfigureDreadnought extends Configure
  
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    constructor: (scope, element) ->
      super scope, element
      @scope.nbWeapons = (i for i in [1...@scope.src.life])
      @scope.weapons = ['autoCannon', 'missileLauncher', 'flamer']
       
    # **private**
    # Update the model value according to selected weapons
    #
    # @param event [Event] Modification event
    _updateModel: (event) =>
      values = @$el.find 'select'
      @scope.target.weapons = ($(value).val() for value in values)