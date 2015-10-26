'use strict'

define ['jquery', 'util/common'], ($, {parseError}) ->
  
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
          # look for token into url or into local storage.
          token = location.$$search.token or localStorage.getItem conf.gameToken
          unless token?
            # no token: let user authentcate
            dfd.resolve()
          else
            # server login succeed ! connect atlas.
            atlas.connect token, (err, player) ->
              scope.$apply ->
                if err?
                  localStorage.removeItem conf.gameToken
                  return dfd.resolve err 
                # for reconnection usage
                localStorage.setItem conf.gameToken, player.token
                # goes to home and reset query parameters
                if location.path()is "#{conf.basePath}login"
                  location.path("#{conf.basePath}home").search({}).replace()
            
        dfd.promise
      ]
              
    # Controller dependencies
    @$inject: ['check', '$location', '$filter']
    
    # login urls
    urls: 
      manual: "#{conf.apiBaseUrl}/auth/login"
      twitter: "#{conf.apiBaseUrl}/auth/twitter"
      github: "#{conf.apiBaseUrl}/auth/github"
      google: "#{conf.apiBaseUrl}/auth/google"
    
    # displayed error
    error: null
    
    # Link to angular's location provider
    location: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param err [Error] Controller own resolver result
    # @param location [Object] Angular location provider
    # @param filter [Object] Angular's filter factory
    constructor: (err, @location, filter) -> 
      document.title = filter('i18n') 'titles.login'
      @error = parseError err if err?
      
    # navigate to other page
    # @param path [String] path to navigate to
    # @param params [Object] optionnal path parameters, default to no params
    navTo: (path, params = {}) =>
      @location.path("#{conf.basePath}#{path}").search params
        
    # On form submission, trigger the leave animation on view
    onSubmit: =>
      $('[data-ng-view]').addClass 'ng-leave ng-leave-active'
      null