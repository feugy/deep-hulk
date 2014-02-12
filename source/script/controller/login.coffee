'use strict'

define ['jquery'], ($) ->
  
  class Login
  
    # Controller loading resolver: used to handle server authentification redirection.
    # After its authentication, server will redirect to the login controller with
    # `token` or `error` query parameter. 
    # The token is used to connect with Atlas, while error indicates why the 
    # authentication failed.
    # @return an Error object if authentication failed, or nothing
    @checkRedirect:
      
      # @param q [Object] Angular deffered/promise implementation
      # @param location [Object] Angular location service
      # @param scope [Object] Angular root scope
      # @param atlas [Object] Atlas service
      check: ['$q', '$location', '$rootScope', 'atlas', (q, location, scope, atlas) -> 
        dfd = q.defer()
  
        err = location.$$search.error
        if err?
          dfd.resolve new Error err
        else
          token = location.$$search.token
          unless token?
            dfd.resolve()
          else
            # server login succeed ! connect atlas.
            atlas.connect token, (err, player) ->
              scope.$apply ->
                return dfd.resolve err if err?
                # for reconnection usage
                localStorage.setItem 'game.token', player.token
                # goes to home and reset query parameters
                location.path("#{conf.basePath}home").search({}).replace()
            
        dfd.promise
      ]
              
    # Controller dependencies
    @$inject: ['$scope', 'check', '$animate']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param err [Error] Controller own resolver result
    constructor: (@scope, err) -> 
      @scope.loginUrl = "#{conf.apiBaseUrl}/auth/login"
      @scope.error = err?.message
      @scope.closeError = @closeError
      @scope._onSubmit = @_onSubmit
      
    # Remove the current error, which hides the alert
    closeError: =>
      @scope.error = null
      
    #**private**
    # On form submission, trigger the leave animation on view
    _onSubmit: =>
      $('[data-ng-view]').addClass 'ng-leave ng-leave-active'
      null