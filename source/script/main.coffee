'use strict'

# browser detection: show disclaimer and quit
showDisclaimer = ->
  document.getElementById('disclaimer').style.display=""
  document.getElementById('view').remove()

for prop in ["audio", "canvas", "canvastext", "history", "hsla", "inlinesvg", 
    "localstorage", "multiplebgs", "postmessage", "rgba", "svg", "svgclippaths", 
    "textshadow", "video", "webworkers"] when not Modernizr[prop]
  return showDisclaimer()
  
# configure requireJS
requirejs.config  

 # paths to vendor libs
  paths:
    'angular': 'vendor/angular-1.2.7'
    'angular-animate': 'vendor/angular-animate-1.2.7-min'
    'angular-mousewheel': 'vendor/angular-mousewheel-1.0.4'
    'angular-route': 'vendor/angular-route-1.2.7-min'
    'angular-sanitize': 'vendor/angular-sanitize-1.2.7-min'
    'angular-ui-select': 'vendor/angular-ui-select2-0.5.0'
    'atlas': 'vendor/atlas'
    'async': 'vendor/async-0.2.7-min'
    'hamster': 'vendor/hamster-1.0.4'
    'jquery': 'vendor/jquery-2.0.0-min'
    'jquery-ui': 'vendor/jquery-ui-1.10.3-min'
    'socket.io': 'vendor/socket.io-1.0.0-pre'
    'text': 'vendor/require-text-2.0.10'
    'template': '../template'
    'underscore': 'vendor/underscore-1.4.4-min'
    'underscore.string': 'vendor/underscore.string-2.3.0-min'
    
  # vendor libs dependencies and exported variable
  shim:
    'angular':
      deps: ['jquery']
      exports: 'angular'
    'angular-animate': deps: ['angular']
    'angular-mousewheel': deps: ['angular', 'hamster']
    'angular-route': deps: ['angular']
    'angular-sanitize': deps: ['angular']
    'angular-ui-select': deps: ['angular']
    'async': exports: 'async'
    'atlas':
      deps: ['jquery', 'underscore']
      exports: 'factory'
    'jquery': exports: '$'
    'jquery-ui': deps: ['jquery']
    'socket.io': exports: 'io'
    'underscore': exports: '_'
    'underscore.string': deps: ['underscore']

require [
  'jquery'
  'async'
  'angular'
  'socket.io'
  # unwired dependencies
  './app'
  './service/atlas'
  './service/dialog'
  './filter/utils'
  './widget/alert'
  './widget/character_details'
  './widget/configure_dreadnought'
  './widget/configure_marine'
  './widget/cursor'
  './widget/deployable_blips' 
  './widget/help'
  './widget/log'
  './widget/map'
  './widget/notify'
  './widget/rule_params'
  './widget/select'
  './widget/scores' 
  './widget/short_game' 
  './widget/zone_display' 
], ($, async, angular, io) ->
  # removes disclaimer
  $('#disclaimer').remove()
  
  # make them available for Atlas library.
  window.async = async
  window.io = io
  
  # starts the application !
  angular.bootstrap $('body'), ['app']