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
      @scope.weapons = ['autoCannon', 'missileLauncher', 'flamer']