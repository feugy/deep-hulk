'use strict'

define [
  'underscore'
  'util/common'
], (_, {getInstanceImage, parseError}) ->
  
  # two mode controller: displays squad configuration (for marines, before starting game)
  # or displays the game board (for marines and alien)
  class BoardController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', '$dialog', 'atlas']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Link to Atlas service
    atlas: null
    
    # Link to Angular location service
    location: null
    
    # Link to Angular dialog service
    dialog: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param dialog [Object] Angular dialog service
    # @param atlas [Object] Atlas service
    constructor: (@scope, @location, @dialog, @atlas) ->
      @scope.configured = {}
      @scope.getInstanceImage = getInstanceImage
      @scope.onDeploy = @_onDeploy
      @scope.closeError = @_closeError
      @scope.lastSelected = null
      @scope.onHoverOption = @_displayHelp
      
      # bind configuration change
      @scope.$watch 'configured', @_onConfigureMarine, true
              
      gId = @location.search()?.id
      return @location.path("#{conf.basePath}home").search({}) unless gId? 
      # search for game details
      @atlas.Item.fetch [gId], (err, [game]) => @scope.$apply =>
        # redirect to home if not found
        err = "game not found: #{gId}" if !err? and !game?
        return @location.path("#{conf.basePath}home").search err: err if err?
        # redirect to end if finished
        return @location.path "#{conf.basePath}end" if game.finished
        # keep game and player's squad
        @scope.game = game
        squad = _.find game.squads, (squad) => squad.player is @atlas.player.email
        # redirect to game if alien or already configured
        return @location.path "#{conf.basePath}board" if squad.isAlien or squad.map?
        # fetch squand and all of its members
        @_fetchSquad squad
       
    # Remove the current error, which hides the alert
    _closeError: =>
      @scope.error = null
      
    # **private**
    # Display help about last selected element
    # 
    # @param event [Event] option markup hover event
    # @param choice [String] hovered option's value
    _displayHelp: (event, choice) =>
      @scope.lastSelected = choice
      
    # **private**
    # Fetch the current squad and all its members.
    # Refresh view once finished.
    # 
    # @param squad [Item] fetched squad
    _fetchSquad: (squad) =>
      # first, ge squad
      @scope.error = null
      @atlas.Item.fetch [squad], (err, [squad]) => 
        return @scope.$apply( => @scope.error = err?.message) if err?
        # then get members
        @atlas.Item.fetch squad.members, (err) => @scope.$apply => 
          return @scope.error = err?.message if err?
          for member in squad.members
            @scope.configured[member.id] = weapon: member?.weapon?.id
          @scope.squad = squad
      
    # **private**
    # Handler invoked when a marine changed.
    # check on server that changes can be applied.
    # 
    # @param current [Object] new configured options for squad members
    # @param previous [Object] previous configured options for squad members
    _onConfigureMarine: (current, previous) =>
      return if _.isEqual {}, previous
      # configure marines equipment
      params = {}
      for id, spec of current
        params["#{id}-weapon"] = spec.weapon
      @scope.error = null
      @atlas.ruleService.execute 'configureSquad', @atlas.player, @scope.squad, params, (err) => @scope.$apply =>
        if err?
          return @scope.error = parseError err?.message
           
    # **private**
    # Handler invoked when the squad is deployed.
    # Confirm deployement and proceed.
    _onDeploy: =>
      confirm = @dialog.messageBox conf.titles.confirmDeploy, conf.msgs.confirmDeploy, [
        {label: conf.buttons.yes, result: true}
        {label: conf.buttons.no}
      ]
      confirm.open().then (confirmed) =>
        return unless confirmed
        @atlas.ruleService.execute 'deploySquad', @atlas.player, @scope.squad, {}, (err) => @scope.$apply =>
          return @scope.error = err?.message if err?   
          # navigate to game
          @location.path "#{conf.basePath}board"