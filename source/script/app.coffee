'use strict'

define [
  'angular', 
  'util/common'
  'controller/login'
  'controller/home'
  'controller/board'
  'controller/configure_squad'
  'controller/end'
  'angular-route'
  'angular-sanitize'
  'angular-animate'
], (angular, utils, LoginCtrl, HomeCtrl, BoardCtrl, ConfigureSquadCtrl, EndCtrl) ->
  
  # declare main module that configures routing
  app = angular.module 'app', ['ngRoute', 'ngSanitize', 'ngAnimate']
  
  app.config ['$locationProvider', '$routeProvider', '$sceDelegateProvider', (location, route, sce) ->
    # autorize call to api
    sce.resourceUrlWhitelist ['self', "#{conf.apiBaseUrl}/**"]

    base = /^(.*\/)([^\/]*)\/\.$/g.exec(require.toUrl('.'))?[1] or ''
    
    # use push state
    location.html5Mode true
    # configure routing
    route.when "#{conf.basePath}login", 
      name: 'login'
      templateUrl: "#{base}template/login.html"
      controller: LoginCtrl
      resolve: LoginCtrl.checkRedirect
    route.when "#{conf.basePath}home",
      name: 'home'
      templateUrl: "#{base}template/home.html"
      controller: HomeCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}board",
      name: 'board'
      templateUrl: "#{base}template/board.html"
      controller: BoardCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}configure-squad",
      name: 'configure-squad'
      templateUrl: "#{base}template/configure_squad.html"
      controller: ConfigureSquadCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}end",
      name: 'end'
      templateUrl: "#{base}template/end.html"
      controller: EndCtrl
      resolve: common: utils.enforceConnected
    route.otherwise 
      redirectTo: "#{conf.basePath}login"
  ]
  
    
  # extends Angular's scope to add off() function, needed by Atlas
  app.run ['$rootScope', (scope) ->
    scope.on = scope.$on
    scope.emit = scope.$emit
    scope.off = scope.$off = (name, listener) ->
      # no name: reset all
      return @$$listeners = {} unless name?
      # no listener: reset all name listeners
      return @$$listeners[name] = [] unless listener?
      # otherwise, remove only single listener
      idx = @$$listeners[name].indexOf listener
      @$$listeners[name].splice idx, 1 unless idx is -1
      
    # listen to route change to update current controller
    scope.$on '$routeChangeSuccess', (ev, data) ->  
      scope.routeName = data.$$route.name if data.$$route?.name?
  ]
  
  # for debug purposes
  window.app = app
  
  app