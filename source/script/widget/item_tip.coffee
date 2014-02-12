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
      @scope.rcDamages = ""
      
      getDamages = =>
        @scope.ccDamages = "labels.#{@scope.src.weapon.cc or 'noCc'}"
        @scope.rcDamages = "labels.#{@scope.src.weapon.rc or 'noRc'}"
        
      # Weapon resolution if needed
      return @_resolveWeapon(=> @scope.$apply getDamages) unless @scope.src.weapon?.id?
      getDamages()
      
    # **private**
    # Resolve weapon to get details. Replace source own weapon
    # @param end [Function] callback invoked when weapon is resolved
    _resolveWeapon: (end) =>
      # first, lool into the cache
      @atlas.Item.findById @scope.src.weapon, (err, weapon) =>
        console.error "Failed to find weapon by id for tip:", err if err?
        if weapon?
          @scope.src.weapon = weapon
          return end()
        # or ask to server
        @atlas.Item.fetch [@scope.src.weapon], (err, [weapon]) => 
          console.error "Failed to fetch weapon for tip:", err if err?
          @scope.src.weapon = weapon
          end()