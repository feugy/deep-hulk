'use strict'

define [
  'underscore'
  'app'
], (_, app) ->
  
  # add the i18n filter
  app.filter 'i18n', ['$parse', '$interpolate', (parse, interpolate) -> (input, options) -> 
    sep = ''
    # optionnal field separator
    if options?.sep is true
      sep = parse('labels.fieldSeparator') conf
    try
      value = parse(input) conf
      # performs replacements
      if options?.args?
        value = interpolate(value) options.args
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