'use strict'

define [
  'app'
  'text!template/orders.html'
], (app, template) ->
    
  app.directive 'orders', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # Squad for which orders can be selected
      squad: '='
      # method invoked when an order has been choosen, 
      # with the order name and selected marine as parameters
      orderChosen: '=?'
      # true to display, false otherwise
      isShown: '='
    # controller
    controller: Orders
    controllerAs: 'ctrl'
    
  class Orders
  
    # Controller dependencies
    @$inject: ['$scope']
    
    # squad for which orders are choosen
    squad: null
    
    # List of displayed orders
    orders: null
    
    # selected order
    selected: null
    
    # for orders that need a target, list of squad members 
    members: null
    
    # currently hovered order
    hovered: null
    
    # flag to distinguish hovered text from hover visibility
    hasHover: false
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    constructor: (scope) ->
      scope.$watchCollection 'ctrl.selected', (value) =>
        return unless @selected?.length > 0
        # check member for orders that need them
        for {name, selectMember} in @orders when name is @selected[0].name
          return if selectMember and not @selected[0].memberId?
        # propagate selected name and memberId
        scope.orderChosen?(@selected[0].name, @selected[0].memberId)
        scope.ctrl.isShown = false
        
      scope.$watchCollection 'squad.orders', => @_reload()
        
      scope.$watch 'squad', (value, old) =>
        @squad = value
        return unless value? and value isnt old
        @_reload()
        
    # **private**
    # Reload selectable orders
    _reload: =>
      return unless @squad?
      @orders = (name: order, selectMember: order is 'heavyWeapon' for order in @squad.orders)
      @selected = []
      # only members with heavy weapons can be ordered
      @members = (marine for marine in @squad.members when not marine.dead and 
        not marine.isCommander and 
        _.any marine.weapons, (w) -> (w?.id or w) in ['flamer', 'autoCannon', 'missileLauncher'])
    
    # Invoked o display details on an hovered order
    #
    # @param event [Event] mouse over event
    # @param order [String] hovered order name
    onDetails: (event, order) =>
      @hovered = order
      @hasHover = true