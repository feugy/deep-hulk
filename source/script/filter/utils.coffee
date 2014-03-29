'use strict'

define [
  'app'
], (app) ->
  
  # add the i18n filter
  app.filter 'i18n', ['$parse', (parse) -> (input, options) -> 
    sep = ''
    if options?.sep is true
      sep = parse('labels.fieldSeparator') conf
    try
      value = parse(input) conf
    catch exc
      console.error "Failed to parse i18n key '#{input}':", exc
    "#{if value? then value else input}#{sep}"
  ]
    
  # add the range filter
  app.filter 'range', [ -> (input, length) ->
    input.length = 0
    input.push i for i in [0...parseInt length]
    input
  ]
  
  app.filter 'reverseArray', -> (arr) => arr.slice().reverse()

  # Fix select bug regarding keyboard selection:
  # https://github.com/angular/angular.js/issues/4216
  app.directive 'select', ->
    return {
      restrict: "E"
      require: "?ngModel"
      scope: false
      link: (scope, element, attrs, ngModel) ->
        return unless ngModel?
        element.bind "keyup", -> element.trigger "change"
    }