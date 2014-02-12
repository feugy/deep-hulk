'use strict'

# configure requireJS
requirejs.config  

 # paths to vendor libs
  paths:
    'angular': 'vendor/angular-1.2.7'
    'angular-route': 'vendor/angular-route-1.2.7'
    'angular-sanitize': 'vendor/angular-sanitize-1.2.7'
    'angular-animate': 'vendor/angular-animate-1.2.7'
    'atlas': 'vendor/atlas'
    'async': 'vendor/async-0.2.7-min'
    'jquery': 'vendor/jquery-2.0.0-min'
    'jquery-ui': 'vendor/jquery-ui-1.10.3-min'
    'socket.io': 'vendor/socket.io-0.9.10'
    'text': 'vendor/require-text-2.0.10'
    'template': '../template'
    'underscore': 'vendor/underscore-1.4.4-min'
    'underscore.string': 'vendor/underscore.string-2.3.0-min'
    
  # vendor libs dependencies and exported variable
  shim:
    'angular':
      deps: ['jquery']
      exports: 'angular'
    'angular-route': deps: ['angular']
    'angular-sanitize': deps: ['angular']
    'angular-animate': deps: ['angular']
    'async': exports: 'async'
    'atlas':
      deps: ['async', 'jquery', 'socket.io', 'underscore']
      exports: 'factory'
    'jquery': exports: '$'
    'jquery-ui': deps: ['jquery']
    'socket.io': exports: 'io'
    'underscore': exports: '_'
    'underscore.string': deps: ['underscore']
    'ui.bootstrap':deps: ['angular']

require [
  'jquery'
  'async'
  'angular'
  # unwired dependencies
  './app'
  './service/atlas'
  './service/dialog'
  './filter/utils'
  './widget/alert'
  './widget/character_details'
  './widget/configure_marine'
  './widget/cursor'
  './widget/deployable_blips' 
  './widget/log'
  './widget/map'
  './widget/rule_params'
  './widget/zone_display' 
], ($, async, angular) ->
  
  # dunno why, async is not set as dependency for Atlas.
  window.async = async
  
  # starts the application !
  angular.bootstrap $('body'), ['app']