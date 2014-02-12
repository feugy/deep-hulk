'use strict'

define [
  'underscore'
  'underscore.string'
], (_) ->
  
  _.mixin _.str.exports()
  
  # getter for document visibility
  prefix = if navigator.userAgent.match(/chrome/i) then 'webkit' else 'moz'

  # define a getter for page visibility
  Object.defineProperty document, 'hidden', 
    get: () ->
      document["#{prefix}Hidden"]
  # unified event name
  $(document).on "#{prefix}visibilitychange", (event) -> $(document).trigger 'visibilitychange', event

  # use same name for animation frames facilities
  window.requestAnimationFrame = window[prefix+'RequestAnimationFrame']
  window.cancelAnimationFrame = window[prefix+'CancelAnimationFrame']
  
  exports = 
    
    # Compute the Euclidian distance between two points (map coordinates)
    #
    # @param posA [Object] first coordinate (x and y)
    # @param posB [Object] second coordinate (x and y)
    # @return the euclidian distance (rounded) between the two coordinates
    euclidianDistance: (posA, posB) ->
      Math.round Math.sqrt Math.pow(posA.x-posB.x, 2) + Math.pow(posA.y-posB.y, 2)
      
    # Compute image source path for a given instance, to be loaded in an img markup
    # @param instance [Object] instance whom image is needed
    # @returns the corresponding image source string
    getInstanceImage: (instance) -> 
      imageSpec = instance?.type?.images[instance.imageNum]?.file
      return conf.imagesUrl + (imageSpec or instance?.type?.descImage or 'null')
    
    # mix two hex colors (3 or 6 length),
    #
    # @param color1 [String] hex color: #FFFF00 or #FF0
    # @param color2 [String] second hex color
    # @param amount [Number] indicate the dominante color. 0.5 (default value) will equally merge
    mixColors: (color1, color2, amount = 0.5) ->
      # convert to hsl to apply subtractive color model instead of additive
      hsl1 = exports.hexToHsl color1
      hsl2 = exports.hexToHsl color2
      exports.hslToHex
        h: amount * hsl1.h + (1 - amount) * hsl2.h
        s: amount * hsl1.s + (1 - amount) * hsl2.s
        l: amount * hsl1.l + (1 - amount) * hsl2.l
    
    # convert an hexadecimal color to rgb values
    # may contains alpha value also, as fourth value
    #
    # @param color [String] rgb hex color: #FFFF00(FF) or #FF0(A)
    # @return an object containing 'r', 'g', 'b' and 'a' properties
    hexToRgb: (color) ->
      isShort = color.length in [4, 5]
      return {
        r: parseInt (if isShort then color[1]+color[1] else color[1..2]), 16
        g: parseInt (if isShort then color[2]+color[2] else color[3..4]), 16
        b: parseInt (if isShort then color[3]+color[3] else color[5..6]), 16
        a: parseInt((if isShort then color[4]+color[4] else color[7..8]) or 'FF', 16)/255
      }
          
    # convert an rgb object to hexadecimal color
    # alpha is ignored unless specified
    #
    # @param color [Object] Rgb color object containing 'r', 'g' and 'b' properties
    # @param withAlpha [Boolean] true to add alpha as fourth part. Default to false
    # @return corresponding color hex color (6-digits with leading diamond)
    rgbToHex: ({r, g, b, a}, withAlpha = false) ->
      color = "#" + _.pad(Math.round(r).toString(16), 2, '0') +
        _.pad(Math.round(g).toString(16), 2, '0') +
        _.pad(Math.round(b).toString(16), 2, '0')
      color += _.pad(Math.round(a*255).toString(16), 2, '0') if withAlpha
      color
      
    # convert an rgb/hex color to hsl
    # Conversion formula adapted from http://en.wikipedia.org/wiki/HSL_color_space.
    #
    # @param color [String] rgb hex color: #FFFF00 or #FF0
    # @return an object containing 'h', 's' and 'l' properties
    hexToHsl: (color) ->
      {r, g, b} = exports.hexToRgb(color)
      r /= 255
      g /= 255
      b /= 255
      max = Math.max r, g, b
      min = Math.min r, g, b
      result = 
      h = (max + min)/2
      s = h
      l = h
      if max is min
        # achromatic
        [h, s] = [0, 0]
      else 
        d = max - min
        s = if l > 0.5 then d / (2-max-min) else d / (max+min)
        switch max
          when r then h = (g-b) / d+(if g < b then 6 else 0)
          when g then h = (b-r) / d+2
          when b then h = (r-g) / d+4
        h /= 6
      return h:h, s:s, l:l
    
    # convert an hsl color to rgb string
    # Conversion formula adapted from http://en.wikipedia.org/wiki/HSL_color_space.
    #
    # @param color [Object] hsl color with 'h', 's' and 'l' properties
    # @return a 6-length rgb color string with '#' prefix
    hslToHex: ({h, s, l}) ->
      [r, g, b] = [0, 0, 0]
      
      if s is 0
        # achromatic
        [r, g, b] = [l, l, l]
      else
        hue2rgb = (p, q, t) ->
          t += 1 if t < 0
          t -= 1 if t > 1
          return p+(q-p)*6*t if t < 1/6
          return q if t < 1/2
          return p+(q-p)*(2/3 - t)*6 if t < 2/3
          return p
          
        q = if l < 0.5 then l*(1+s) else l+s - l*s
        p = 2*l - q
        r = hue2rgb(p, q, h + 1/3)*255
        g = hue2rgb(p, q, h)*255
        b = hue2rgb(p, q, h - 1/3)*255
        
      exports.rgbToHex r:r, g:g, b:b
    
    # This utility provide a promise that enforce the player connection.
    # It ensure that a player is connected within Atlas, and reuse if possible 
    # tokens stored inside local storage under `game.token`
    #
    # @return nothing on `resolve()`, an Error object on `reject()`
    enforceConnected: ['$q', '$rootScope', '$location', 'atlas', (q, scope, location, atlas) ->
      dfd = q.defer()
      
      scope.$on '$routeChangeStart', callback = (event, current, previous) ->
        console.log 'current route:', current?.$$route?.name, 'previous:', previous?.$$route?.name
        
      # handle enforcement rejections
      scope.$on '$routeChangeError', callback = (event, current, previous, reason) ->
        scope.$off '$routeChangeError', callback
        # goes back to login if no token found
        reason.message = 'session expired' if reason?.message in ['no token found', 'handshake unauthorized']
        location.path("#{conf.basePath}login").search(error: reason.message).replace()
        
      # accept if player connected
      if atlas.connected
        dfd.resolve() 
      else
        # get token from locale storage
        token = localStorage.getItem 'game.token'
        # Immediately redirect to login if no token found
        unless token?
          dfd.reject new Error 'no token found' 
        else
          # try to connect
          atlas.connect token, (err, player) ->
            scope.$apply ->
              if err?
                return dfd.reject err
              # save new token an proceed
              localStorage.setItem 'game.token', player.token
              dfd.resolve()
      
      dfd.promise
    ]
    
    # Read error value into labels, and return human readable error message.
    parseError: (err) ->
      console.log err
      err = err.substr err.indexOf('Error: ')+7
      # error may contain arguments
      args = []
      key = err
      split = err.split ' '
      if split.length >= 2
        key = split[0]
        split.splice 0, 1
        args = split
      return if key of conf.errors then _.sprintf.apply _, [conf.errors[key]].concat(args) else err
    
  return exports