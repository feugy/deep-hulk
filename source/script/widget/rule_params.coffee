'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/rule_params.html'
  'widget/param'
], ($, _, app, template) ->
    
  app.directive 'ruleParams', -> new RuleParams()
  
  class RuleParams
    
    # directive template
    template: template
    
    # will remplace hosting element
    replace: true
    
    # applicable as element and attribute
    restrict: 'EA'
    
    # parent scope binding.
    scope: 
      # applicable rule target, as returned by atlas.ruleService.resolve() in the target array
      rule: '='
      # result parameters values: expect an object to be filled with parameters values
      values: '='
      
    # rendering linking function
    #
    # @param scope [Object] directive own scope
    # @param element [DOM] rendering root element
    link: (scope, element) =>
      scope.$watch 'rule', -> 
        # initialize values
        scope.values = {} unless _.isObject scope.values