'use strict'

define [
  'angular', 
  'util/common'
  'controller/login'
  'controller/home'
  'controller/board'
  'controller/configure'
  'controller/discover'
  'controller/end'
  'controller/rules'
  'angular-route'
  'angular-sanitize'
  'angular-animate'
  'angular-mousewheel'
], (angular, utils, LoginCtrl, HomeCtrl, BoardCtrl, ConfigureCtrl, DiscoverCtrl, EndCtrl, RulesCtrl) ->
  
  # declare main module that configures routing
  app = angular.module 'app', ['ngRoute', 'ngSanitize', 'ngAnimate', 'monospaced.mousewheel']
  
  app.config ['$locationProvider', '$routeProvider', '$sceDelegateProvider', (location, route, sce) ->
    # autorize call to api
    authorized = ['self']
    apiBaseUrl = "#{conf.apiBaseUrl.replace 'www.', ''}/**"
    if /^https?:\/\/[^:]*:80\//.test apiBaseUrl
      apiBaseUrl = apiBaseUrl.replace ':80', ''
    authorized.push apiBaseUrl, apiBaseUrl.replace ':\/\/', ':\/\/www.'
    sce.resourceUrlWhitelist authorized

    # dynamically set root from which client files (images, stylesheets...) are loaded
    conf.rootPath = /^(.*\/)([^\/]*)\/\.$/g.exec(require.toUrl('.'))?[1] or ''

    # use push state
    location.html5Mode true
    # configure routing
    route.when "#{conf.basePath}login", 
      name: 'login'
      templateUrl: "#{conf.rootPath}template/login.html"
      controller: LoginCtrl
      controllerAs: 'ctrl'
      resolve: LoginCtrl.checkRedirect
    route.when "#{conf.basePath}home",
      name: 'home'
      templateUrl: "#{conf.rootPath}template/home.html"
      controller: HomeCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}board",
      name: 'board'
      templateUrl: "#{conf.rootPath}template/board.html"
      controller: BoardCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}configure",
      name: 'configure'
      templateUrl: "#{conf.rootPath}template/configure.html"
      controller: ConfigureCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}end",
      name: 'end'
      templateUrl: "#{conf.rootPath}template/end.html"
      controller: EndCtrl
      resolve: common: utils.enforceConnected
    route.when "#{conf.basePath}rules",
      name: 'rules'
      templateUrl: "#{conf.rootPath}template/rules.html"
      controller: RulesCtrl
      controllerAs: 'ctrl'
    route.when "#{conf.basePath}discover",
      name: 'discover'
      templateUrl: "#{conf.rootPath}template/discover.html"
      controller: DiscoverCtrl
      controllerAs: 'ctrl'
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
    scope.$on '$routeChangeStart', (event, current, previous) ->
      scope.previousRoute = previous
    scope.$on 'disconnected', ->
      console.log 'user logged-out'
      localStorage.removeItem conf.gameToken
  ]
  
  # for debug purposes
  window.app = app
  
  app