'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/item_tip.html'
], ($, _, app, template) ->

  # Translate a json capacity descriptor into a string for displayal
  # @param capacity [Object] descriptor containing 'r' and 'w' numeric properties
  # @return corresponding string
  capacityToString = (capacity) =>
    return '' unless capacity?
    ("#{num}#{kind}" for kind, num of capacity).join ''
    
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
      # current player's squad
      squad: '='
      # displayed model
      src: '='
  
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
      @scope.attacks = Math.max @scope.src.rcNum, @scope.src.ccNum
      @scope.armor = if _.contains(@scope.src?.equipment, 'forceField') then @scope.src?.armor-1 else @scope.src?.armor
      @scope.canInspect = @scope.squad.revealBlips > 0
      @scope.inspect = @_onInspect
      @scope.inspected = false
      @scope.isEquipment = (item) -> not(item in ['bySections', 'photonGrenade', 'toDeath'])
      
      getDamages = =>
        # use first weapon for close combat
        @scope.ccDamages = "labels.#{capacityToString(@scope.src.weapons[0]?.cc) or 'noCc'}"
        @scope.rcDamages = []
        for weapon in @scope.src.weapons
          @scope.rcDamages.push "labels.#{capacityToString(weapon?.rc) or 'noRc'}"
        
      # Weapon resolution if needed
      return @_resolveWeapon(=> @scope.$apply getDamages) unless @scope.src.weapons[0]?.id?
      getDamages()
      
    # **private**
    # Temporary unreveal the blip if allowed
    _onInspect: =>
      return unless @scope.canInspect
      @scope.inspected = true
      @atlas.ruleService.execute 'useEquipment', @scope.squad, @scope.squad.members[0], {equipment: 'detector'}, (err, message) =>
        console.error err if err?
        # update remaining inspection
        @scope.canInspect = @scope.squad.revealBlips > 0
      
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