'use strict'

define [
  'underscore'
  'util/common'
], (_, {getInstanceImage, parseError}) ->
  
  # two mode controller: displays squad configuration (for marines, before starting game)
  # or displays the game board (for marines and alien)
  class BoardController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', '$dialog', 'atlas', '$rootScope']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Link to Atlas service
    atlas: null
    
    # Link to Angular location service
    location: null
    
    # Link to Angular dialog service
    dialog: null
    
    #**private**
    # Inhibit commands while aliens are deploying, action replay active or when turn has ended
    _inhibit: false
    
    # **private**
    # Kept applicable rules of the selected item with their targets and parameters
    _applicableRules: {}
    
    # **private**
    # pending rule with parameters
    _pending: null
    
    # **private**
    # During deployement phase, store current zone deployed
    _currentZone: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] Angular current scope
    # @param location [Object] Angular location service
    # @param dialog [Object] Angular dialog service
    # @param atlas [Object] Atlas service
    # @param rootScope [Object] Angular root scope
    constructor: (@scope, @location, @dialog, @atlas, rootScope) ->
      @_applicableRules = {}
      @_inhibit = false
      @_currentZone = null
      @scope.zoom = 1
      @scope.menuItems = null
      @scope.zone = null
      @scope.canEndTurn = 'disabled'
      @scope.hasNextAction = ''
      @scope.hasPrevAction = ''
      @scope.canStopReplay = ''
      @scope.activeRule = null
      @scope.log = []
      @scope._onSelectActiveRule = @_onSelectActiveRule
      @scope._onNextAction = =>
        @atlas.nextAction => @scope.$apply => @_updateReplayCommands()
      @scope._onPrevAction = => 
        @atlas.previousAction => @scope.$apply => @_updateReplayCommands()
      @scope._onStopReplay = => 
        @atlas.stopReplay => @scope.$apply => @_updateReplayCommands()
        
      @scope._onMapClick = (event, details) => @_onClick event, details
      @scope._onMapRightclick = @_onSelect
      @scope._askToExecuteRule = @_onOpen
      @scope._onOpen = @_onOpen
      @scope._onEndTurn = @_onEndTurn
      @scope._onEndDeploy = @_onEndDeploy
      @scope._onBlipDeployed = @_onBlipDeployed
      @scope._onSelectMenuItem = @_onSelectMenuItem
      @scope._onHover = (evt, details) =>
        @displayDamageZone(evt, details.field) if @scope.activeRule is 'shoot'
      @scope.getInstanceImage = getInstanceImage
      @scope.deployScope = null
      
      # update zone on replay quit/enter
      rootScope.$on 'replay', (ev, details) =>
        if details.active
          @scope.zone = null
          @_inhibit = true
        else
          # inhibit on turn end or deployment in progress unles is alien and needs deployement
          @_inhibit = if @scope.squad?.isAlien and @scope.squad?.deployZone? then false else @scope.squad?.actions < 0 or @scope.squad?.deployZone?
          @_onSelectActiveRule ev, @scope.activeRule
      
      # update on model changed
      rootScope.$on 'modelChanged', @_onModelChanged
      
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
        @atlas.initReplay game
        @_updateReplayCommands()
        
        squad = _.find game.squads, (squad) => squad.player is @atlas.player.email
        # redirect to configuration if marine and not on map
        return @location.path "#{conf.basePath}configure-squad" unless squad.map? or squad.isAlien
        # fetch squand and all of its members
        @_fetchSquad squad
          
    # When toggeling move mode, changing selected character, or after a move, 
    # check on server reachable tiles and display them
    displayMovable: =>
      # defer because click on mode button is processed before changing the activeRule value
      unless not @_inhibit and @scope.selected? and @scope.activeRule is 'move' and !@atlas.ruleService.isBusy()
        return
      @atlas.ruleService.execute 'movable', @scope.selected, @scope.selected, {}, (err, reachable) => @scope.$apply =>
        # silent error, no moves, no more selected: clear zone
        if err? or !reachable? or reachable.length is 0 or @scope.selected is null
          return @scope.zone = null 
        @scope.zone =
          tiles: reachable
          origin: @scope.selected
          kind: 'move'
                  
    # When hovering tiles, check on server damage zone and display it
    #
    # @param target [Item|Field] targeted item or field
    displayDamageZone: (evt, details) =>
      unless details? and not @_inhibit and details? and @scope.selected? and @scope.activeRule in ['shoot', 'assault']
        return
      # do NOT ignore assault resolution if service is busy
      if @atlas.ruleService.isBusy() and @scope.activeRule isnt 'assault'
        return
      @atlas.ruleService.execute "#{@scope.activeRule}Zone", @scope.selected, details, {}, (err, result) => @scope.$apply =>
        # silent error: no zone
        if err? or @scope.selected is null
          return @scope.zone = null
        result.origin = @scope.selected
        result.target = details
        result.kind = @scope.activeRule
        @scope.zone = result
        
    # **private**
    # Update action zone depending on new active rule
    #
    # @param event [Event] triggering event
    # @param rule [String] new value for active rule
    _onSelectActiveRule: (event, rule) =>
        @scope.activeRule = rule
        if rule is 'move'
          @displayMovable()
        else if rule is 'assault'
          @displayDamageZone event, @scope.selected
        else 
          @scope.zone = null
          
    # **private**
    # Update replay commands after a replay action
    _updateReplayCommands: =>
      @scope.canStopReplay = if @atlas.replayPos? then '' else 'disabled'
      @scope.hasPrevAction = if @atlas.hasPreviousAction then '' else 'disabled'
      @scope.hasNextAction = if @atlas.hasNextAction then '' else 'disabled'
      
    # **private**
    # Fetch the current squad and all its members.
    # Refresh view once finished.
    # 
    # @param squad [Item] fetched squad
    _fetchSquad: (squad) =>
      # get squad and its members
      @atlas.Item.fetch [squad], (err, [squad]) => 
        return @scope.$apply( => @scope.log.splice 0, 0, parseError err.message) if err?
        # then get members
        @atlas.Item.fetch squad.members, (err) => @scope.$apply => 
          return @scope.log.splice 0, 0, parseError err.message if err?
          @scope.selected = null
          @scope.squad = squad
          # blips deployment, blip displayal
          if @scope.squad.deployZone?
            @_initBlipDeployement()
          if @scope.squad.actions < 0 
            @scope.canEndTurn = 'disabled' 
            @scope.log.splice 0, 0, conf.msgs.waitForOther
          else
            @scope.canEndTurn = ''
          # inhibit on replay (always) or turn end (if not alien and deploy) or deploy (and not alien)
          @_inhibit = if @scope.squad.isAlien and @scope.squad.deployZone? then @atlas.replayPos? else @atlas.replayPos? or @scope.squad.actions < 0 or @scope.squad.deployZone?
          
    # ** private**
    # If a deploy zone is added to alien squad, swith to blip deployement mode with a info dialog
    _initBlipDeployement: =>
      if @scope.squad.deployZone?
        if @scope.squad.isAlien
          # Auto select the first zone to deploy
          first = @scope.squad.deployZone.split(',')[0]
          # but quit if first is still handled
          return if first is @_currentZone
          @_currentZone = first
          @scope.deployScope = 'deployBlip'
          # add log
          @scope.log.splice 0, 0, conf.msgs.deployBlips
          # highligth deployable zone
          @atlas.ruleService.execute 'deployZone', @atlas.player, @scope.squad, {zone:@_currentZone}, (err, zone) => 
            @scope.$apply =>
              @scope.log.splice 0, 0, parseError err.message if err?
              if !zone? or zone.length is 0
                return @scope.zone = null
              @scope.zone = 
                tiles: zone
                kind: 'deploy'
              # inhibit on replay
              @_inhibit = @atlas.replayPos?
        else
          # add log and inhibit
          @scope.log.splice 0, 0, conf.msgs.deployInProgress
          @_inhibit = true
      else
        @scope.log.splice 0, 0, conf.msgs.deployEnded unless @scope.squad.isAlien
        @_currentZone = null
        @scope.deployScope = null
        # inhibit on turn end or replay pos
        @_inhibit = @scope.squad.actions < 0 or @atlas.replayPos?
        # Redraw previously highlighted zone
        @_onSelectActiveRule null, @scope.activeRule
      
    # **private**
    # Multiple behaviour when model update is received:
    # - navigate away if game was removed
    # - update end of turn if squad changed
    # - remove selected if selected model dies
    #
    # @param event [Event] change event
    # @param operation [String] operation kind: 'creation', 'update', 'deletion'
    # @param model [Model] concerned model
    # @param changes [Array<String>] name of changed property for an update
    _onModelChanged: (ev, operation, model, changes) => 
      switch operation
        when 'deletion'
          if model?.id is @scope.game?.id
            @location.path("#{conf.basePath}home").search err: 'game removed'
        when 'update'
          @scope.$apply =>
            if model?.id is @scope.squad?.id 
              if 'actions' in changes
                # inhibit on replay (always) or turn end (if not alien and deploy) or deploy (and not alien)
                @_inhibit = if @scope.squad.isAlien and @scope.squad.deployZone? then @atlas.replayPos? else 
                  @atlas.replayPos? or @scope.squad.actions < 0 or @scope.squad.deployZone?
                if @scope.squad.actions < 0
                  @scope.canEndTurn = 'disabled'
                else
                  @scope.canEndTurn = ''
                  # auto trigger turn end
                  @_onEndTurn() if @scope.squad.actions is 0
              if 'deployZone' in changes
                @_initBlipDeployement() 
            else if model?.id is @scope.game?.id
              if 'finished' in changes
                return @location.path "#{conf.basePath}end" if model.finished
              if 'turn' in changes
                # if turn has change, add log
                @scope.log.splice 0, 0, conf.msgs.newTurn
              if 'prevActions' in changes
                @_updateReplayCommands()
            else if model is @scope.selected and model.dead
              @scope.selected = null
    
    # **private**
    # Select a given item, or unselect it if previously selected
    #
    # @param event [Event] click event
    # @param details [Object] map details: 
    # @option details map [Map] clicked map model
    # @option return x [Integer] the x map coordinate
    # @option return y [Integer] the y map coordinate
    # @option details items [Array<Item>] item models at this coordinates (may be empty)
    # @option details field [Field] field model at this coordinates (may be null)
    _onSelect: (event, details) =>
      # find selectable item inside clicked items
      item = _.find details.items, (item) => item in @scope.squad.members
      @scope.$apply =>
        if @scope.selected is item
          @scope.selected = null
        else
          @scope.selected = item
          
    # **private**
    # Handler invoked when clicking on map. Try to fire move rule, or to display
    # menu with move and selection.
    # Resolves relevant rules if a squad member is selected.
    #
    # @param event [Event] click event
    # @param details [Object] map details: 
    # @option details map [Map] clicked map model
    # @option return x [Integer] the x map coordinate
    # @option return y [Integer] the y map coordinate
    # @option details items [Array<Item>] item models at this coordinates (may be empty)
    # @option details field [Field] field model at this coordinates (may be null)
    _onClick: (event, details) =>
      return if @_inhibit or not @scope.activeRule?
      @scope.$apply =>
        @scope.menuItems = []
        @scope.path = []
      
      proceed = (err = null, applicables = {}) =>
        console.error err if err?
        # keep for further use
        @_applicableRules = applicables
        keys = _.keys applicables
        return if keys.length is 0
        if keys.length is 1 and keys
          @_onSelectMenuItem null, keys[0]
        else
          # Display choices in map menu 
          @scope.$apply =>
            @scope.menuItems = keys
          
      if @scope.selected?
        # for shoot, restrict to category. Otherwise, restrict to rule id
        restriction = if @scope.activeRule is 'shoot' then [@scope.activeRule] else @scope.activeRule
        # resolve board rules for the selected item at this coord
        @atlas.ruleService.resolve @scope.selected, details.x, details.y, restriction, proceed
      else 
        # no selected item, just proceed.
        proceed()
        
    # **private**
    # Trigger currently selected character to open next door.
    _onOpen: =>
      return if @_inhibit and not(@scope.selected?.doorToOpen?)
      # fake resolution and trigger rule
      @_applicableRules = 
        open: [target: @scope.selected.doorToOpen]
      @_onSelectMenuItem null, 'open'
          
    # **private**
    # Handler of map menu selection. Trigger the corresponding rule
    #
    # @param event [Event] click event inside map menu
    # @param item [String] name of the selected item inside menu
    _onSelectMenuItem: (event, item) =>
      # do not support yet multiple targets nor parameters
      return console.error "multiple targets not supported yet for rule #{item}" if @_applicableRules[item].length > 1
      return console.error "parameters not supported yet for rule #{item}" if @_applicableRules[item][0].params?.length > 0
            
      # trigger rule
      @atlas.ruleService.execute item, @scope.selected, @_applicableRules[item][0].target, {}, (err, result) =>
        return @scope.$apply(=> @scope.log.splice 0, 0, parseError err.message) if err?   
        # refresh movable tiles
        @displayMovable()
                
    # **private**
    # After a modal confirmation, trigger the end of turn.
    # No confirmation if squad hasn't any remaining actions
    _onEndTurn: =>
      return if @_inhibit
      # rule triggering
      trigger = =>
        @atlas.ruleService.execute 'endOfTurn', @atlas.player, @scope.squad, {}, (err) => @scope.$apply =>
          return @scope.log.splice 0, 0, parseError err.message if err?
          # add log
          @scope.log.splice 0, 0, conf.msgs.waitForOther
      return trigger() if @scope.squad.actions is 0
      # still actions ? confirm end of turn
      confirm = @dialog.messageBox conf.titles.confirmEndOfTurn, conf.msgs.confirmEndOfTurn, [
        {label: conf.buttons.yes, result: true}
        {label: conf.buttons.no}
      ]
      confirm.open().then (confirmed) =>
        trigger() if confirmed
        
    # **private**
    # After a model confirmation, trigger the blip deployement end
    _onEndDeploy: =>
      return if @_inhibit
      # rule triggering
      trigger = =>
        @atlas.ruleService.execute 'endDeploy', @atlas.player, @scope.squad, {zone: @_currentZone}, (err) =>
          return @scope.$apply(=> @scope.log.splice 0, 0, parseError err.message) if err?  
          # proceed with next deployement or quit mode
          @_initBlipDeployement()
      # still actions ? confirm end of turn
      confirm = @dialog.messageBox conf.titles.confirmDeploy, conf.msgs.confirmEndDeploy, [
        {label: conf.buttons.yes, result: true}
        {label: conf.buttons.no}
      ]
      confirm.open().then (confirmed) =>
        trigger() if confirmed
    
    # **private**
    # When a blip has been dropped into the map, randomly affect an available member to this position
    #
    # @param coord [Object] x and y coordinates of the deployed blip
    # @param model [Object] if set, redeploy an existing blip
    _onBlipDeployed: (coord, model) =>
      if model?
        # reuse an existing blip
        _.extend coord, 
          zone: @_currentZone
          rank: @scope.squad.members.indexOf model
      else
        # randomly choose one of the deployable blip: 
        # we must send its rank into the squad.members array that also contains deployed blips
        blipIdx = (i for member, i in @scope.squad.members when member?.map is null)
        return unless blipIdx.length > 0
        _.extend coord, 
          zone: @_currentZone
          rank: blipIdx[_.random 0, blipIdx.length-1]
      # trigger the relevant rule
      @atlas.ruleService.execute 'deployBlip', @atlas.player, @scope.squad, coord, (err, result) => @scope.$apply =>
        # displays deployement errors
        return @scope.log.splice 0, 0, parseError err.message if err?