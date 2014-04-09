'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/item_tip.html'
], ($, _, app, template) ->
    
  # The item tip give details on an alien or marine, notably its firepower.
  app.directive 'itemTip', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # controller
    controller: ItemTip
    # parent scope binding.
    scope: 
      src: '=?'
  
  class ItemTip
  
    # Controller dependencies
    @$inject: ['$scope', '$element', 'atlas']
    
    # Link to Atlas service
    atlas: null
    
    # Controller scope, injected within constructor
    scope: null
    
    # enriched element for directive root
    element: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    # @param element [DOM] directive root element
    # @param atlas [Object] Atlas service
    constructor: (@scope, @element, @atlas) ->
      # nothing to to
      @scope.isAlien = @scope.src?.type?.id is 'alien'
      @scope.squadImage = "#{conf.imagesUrl}squad-#{@scope.src.squad.imageNum}.png"
      @scope.ccDamages = ""
      @scope.rcDamages = []
      
      getDamages = =>
        # use first weapon for close combat
        @scope.ccDamages = "labels.#{@scope.src.weapons[0]?.cc or 'noCc'}"
        @scope.rcDamages = []
        for weapon in @scope.src.weapons
          @scope.rcDamages.push "labels.#{weapon?.rc or 'noRc'}"
        
      # Weapon resolution if needed
      return @_resolveWeapon(=> @scope.$apply getDamages) unless @scope.src.weapons[0]?.id?
      getDamages()
      
    # **private**
    # Resolve weapons to get details. Replace source own weapons
    # @param end [Function] callback invoked when weapons are resolved
    _resolveWeapon: (end) =>
      # first, lool into the cache
      @atlas.Item.findCached @scope.src.weapons, (err, weapons) =>
        console.error "Failed to find weapons by id for tip:", err if err?
        if weapons.length is @scope.src.weapons.length
          @scope.src.weapons = weapons
          return end()
        # or ask to server
        @atlas.Item.fetch @scope.src.weapons, (err, weapons) => 
          console.error "Failed to fetch weapons for tip:", err if err?
          @scope.src.weapons = weapons
          end()