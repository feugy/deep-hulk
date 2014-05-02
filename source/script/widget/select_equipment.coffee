'use strict'

define [
  'app'
  'text!template/select_equipment.html'
], (app, template) ->
    
  app.directive 'selectEquipment', -> 
    # directive template
    template: template
    # will remplace hosting element
    replace: true
    # applicable as element and attribute
    restrict: 'EA'
    # parent scope binding.
    scope: 
      # possible equipments for this squad
      equipments: '='
      # number of expected equipments
      number: '=?'
      # target results
      target: '=?'
      # squad members to select targeters
      members: '=?'
      # invoked with event and choice when mouse is over a given choice
      onHover: '=?'
      
    # controller
    controller: SelectEquipment
    
  class SelectEquipment
                  
    # Controller dependencies
    @$inject: ['$scope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    constructor: (@scope) ->
      @scope.toggle = @_onToggleEquipment
      @scope.selected = []
      @scope.getMemberName = (member) -> member?.name or '...'
      @scope._selectedMembers = []
      
      @scope.$watch 'equipments', (value) =>
        return unless value?
        @scope.selected = (false for e in @scope.equipments)
        @scope._selectedMembers = (null for e in @scope.equipments)
     
    # **private**
    # Select or deselect a given equipement
    #
    # @param equip [String] clicked equipment
    # @param idx [Number] index of the clicked equipment in the possible choices
    _onToggleEquipment: (equip, idx) =>
      selectedId = null
      for item in @scope.equipments when item.name is equip and item.selectMember
        selectedId = @scope._selectedMembers[idx]?.id
        break
        
      if @scope.selected[idx]
        # remove existing choice
        for item, i in @scope.target when item.name is equip
          @scope.target.splice i, 1
          break
        @scope.selected[idx] = false 
      else if @scope.target.length < @scope.number
        @scope.target.push name: equip, memberId: selectedId
        @scope.selected[idx] = true
      else if @scope.number is 1
        # only one choice: toggle it
        @scope.target.splice 0, 1, name: equip, memberId: selectedId
        @scope.selected = (i is idx for e, i in @scope.equipments)
        