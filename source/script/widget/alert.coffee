'use strict'

define [
  'app'
  'text!template/alert.html'
], (app, template) ->
      
  app.directive 'alert', -> 
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
      type: '='  
      close: '&'
    # controller
    controller: Alert
  
  class Alert 
    # Controller dependencies
    @$inject: ['$scope', '$attrs']

    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param attrs [Object] root element's HTML attributes (hashmap)
    constructor: (scope, attrs) ->
      scope.closeable = 'close' of attrs