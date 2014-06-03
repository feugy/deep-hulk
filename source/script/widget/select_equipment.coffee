'use strict'

define [
  'underscore'
  'app'
  'text!template/select_equipment.html'
], (_, app, template) ->
    
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
      # extra css class applied on rendering
      extraClass: '=?'
      
    # controller
    controller: SelectEquipment
    controllerAs: 'ctrl'
    
  class SelectEquipment
                  
    # Controller dependencies
    @$inject: ['$scope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # list of selected equipements
    selected: []
    
    # member corresponding to selected equipement
    selectedMembers: []
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] directive scope
    constructor: (@scope) ->
      @selected = []
      @getMemberName = (member) -> member?.name or '...'
      @selectedMembers = []
      
      @scope.$watch 'equipments', (value) =>
        return unless value?
        @selected = []
        @selectedMembers = []
        for equip, i in @scope.equipments
          @selected[i] = false
          @selectedMembers[i] = null
          # enrich with specific choose member function for this equipement
          ((equip, idx) =>
            equip.chooseMember = (event, choosen) =>
              @chooseMember equip.name, idx, choosen
          ) equip, i
      
    # When selecting a member, ensure that the corresponding equipement is selected
    #
    # @param equip [String] clicked equipment name
    # @param idx [Number] index of the clicked equipment in the possible choices
    # @param member [String] selected member for this equipement
    chooseMember: (equip, idx, member) =>
      return unless member? 
      _.defer => @toggle equip, idx, true
        
    # Select or deselect a given equipement
    #
    # @param equip [String] clicked equipment name
    # @param idx [Number] index of the clicked equipment in the possible choices
    # @param force [Boolean] true to force selected. Will only update target if already selected
    toggle: (equip, idx, force=false) =>
      selectedId = null
      for item in @scope.equipments when item.name is equip and item.selectMember
        selectedId = @selectedMembers[idx]?.id
        break
      
      remove = =>
        # remove existing choice
        for item, i in @scope.target when item.name is equip
          @scope.target.splice i, 1
          break
        @selected[idx] = false 
        
      # force update if needed
      remove() if force and @selected[idx]
      if @selected[idx]
        remove()
      else if @scope.target.length < @scope.number
        @scope.target.push name: equip, memberId: selectedId
        @selected[idx] = true
      else if @scope.number is 1
        # only one choice: toggle it
        @scope.target.splice 0, 1, name: equip, memberId: selectedId
        @selected = (i is idx for e, i in @scope.equipments)