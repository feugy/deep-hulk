'use strict'

define [
  'app'
  'text!template/notify.html'
], (app, template) ->
      
  app.directive 'notify', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      notifs: '=?src'
    # controller
    controller: Notify
  
  class Notify 
    # Controller dependencies
    @$inject: ['$scope']
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    constructor: (@scope) ->
      @scope.close = @_onClose
      @scope.closeAll = @_onCloseAll
      
    # **private**
    # Empties the notification list, which clean all rendering
    _onCloseAll: =>
      return if 0 is @scope.notifs.length
      @scope.notifs.splice 0, @scope.notifs.length
      
    # **private**
    # Close a given notification, removing it from the list
    #
    # @param notif [Object] the closed notification
    _onClose: (notif) =>
      idx = @scope.notifs.indexOf notif
      return unless 0 <= idx
      @scope.notifs.splice idx, 1
      
      