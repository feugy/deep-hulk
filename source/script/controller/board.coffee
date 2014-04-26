'use strict'

define [
  'underscore'
  'jquery'
  'util/common'
], (_, $, {getInstanceImage, parseError}) ->
    
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
    
    # **private**
    # Some weapons need to select multiple targets. Temporary store them
    _multipleTargets: []
    
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
      @scope.canEndTurn = ''
      @scope.hasNextAction = ''
      @scope.hasPrevAction = ''
      @scope.canStopReplay = ''
      @scope.activeRule = null
      @scope.activeWeapon = 0
      # If selected character is shooting with a weapon needing multiple targets, 
      @scope.needMultipleTargets = false
      @scope.log = []
      @scope.notifs = []
      @scope._onSelectActiveRule = @_onSelectActiveRule
      @scope._onNextAction = =>
        @atlas.nextAction => @scope.$apply => @_updateReplayCommands()
      @scope._onPrevAction = => 
        @atlas.previousAction => @scope.$apply => @_updateReplayCommands()
      @scope._onStopReplay = => 
        @atlas.stopReplay => @scope.$apply => @_updateReplayCommands()
        
      @scope._onMapClick = (event, details) => @_onClick event, details
      @scope._onMapRightclick = @_onSelect
      @scope._onSelectMember = (member) => _.defer => @_onSelect null, items:[member]
      @scope._askToExecuteRule = @_askToExecuteRule
      @scope._onEndTurn = @_onEndTurn
      @scope._onEndDeploy = @_onEndDeploy
      @scope._onBlipDeployed = @_onBlipDeployed
      @scope._onSelectMenuItem = @_onSelectMenuItem
      @scope._onHover = (evt, details) =>
        @displayDamageZone(evt, details.field) if @scope.activeRule is 'shoot'
      @scope.getInstanceImage = getInstanceImage
      @scope.deployScope = null
      @scope.sendMessage = @sendMessage
      # show help unless specified
      @scope.showHelp = false
      @scope.help = null
        
      # update zone on replay quit/enter
      rootScope.$on 'replay', (ev, details) =>
        if details.active
          @scope.zone = null
          @_inhibit = true
        else
          # inhibit on turn end or deployment in progress unles is alien and needs deployement
          @_inhibit = if @scope.squad?.isAlien and @scope.squad?.deployZone? then false else @scope.squad?.actions < 0 or @scope.squad?.deployZone?
          console.log "coucou", @scope.squad?.isAlien, @scope.squad?.deployZone
          @_currentZone = null
          @_toggleDeployMode()
      
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
        # redirect to configuration if not on map
        return @location.path "#{conf.basePath}configure" unless squad.map?
        # fetch squand and all of its members
        @_fetchSquad squad
      
      # bind key listener
      $(window).on 'keydown.board', @_onKey
      @scope.$on '$destroy', => 
        $(window).off 'keydown.board'
          
    # When toggeling move mode, changing selected character, or after a move, 
    # check on server reachable tiles and display them
    displayMovable: =>
      # defer because click on mode button is processed before changing the activeRule value
      unless not @_inhibit and @scope.selected? and @scope.activeRule is 'move' and !@atlas.ruleService.isBusy()
        return
      # save variable locally to avoid changes while waiting for response
      selected = @scope.selected
      @atlas.ruleService.execute 'movable', selected, selected, {}, (err, reachable) => @scope.$apply =>
        # silent error, no moves, no more selected: clear zone
        return @scope.zone = null if err? or !reachable? or reachable.length is 0 or @scope.selected isnt selected
        @scope.zone =
          tiles: reachable
          origin: selected
          kind: 'move'
                  
    # When hovering tiles, check on server damage zone and display it
    #
    # @param evt [Event] event that add trigger zone displayal (unused)
    # @param details [Item|Field] targeted item or field on which damage zone is evaluated
    displayDamageZone: (evt, details) =>
      unless details? and not @_inhibit and details? and @scope.selected? and @scope.activeRule in ['shoot', 'assault']
        return
      # do NOT ignore assault resolution if service is busy
      if @atlas.ruleService.isBusy() and @scope.activeRule isnt 'assault'
        return
      params = 
        weaponIdx: @scope.activeWeapon
        multipleTargets: ("#{target.x}:#{target.y}" for target in @_multipleTargets)
      # save variable locally to avoid changes while waiting for response
      selected = @scope.selected
      rule = @scope.activeRule
      @atlas.ruleService.execute "#{rule}Zone", selected, details, params, (err, result) => @scope.$apply =>
        # silent error
        return @scope.zone = null if err? or not result? or @scope.selected isnt selected
        result.origin = selected
        result.target = details
        result.kind = rule
        @scope.zone = result
        
    # Send a new message into the game chat
    #
    # @param content the message sent
    sendMessage: (content) =>
      @atlas.ruleService.execute "sendMessage", @scope.game, @scope.squad, {content:content}, (err, result) => 
        @scope.$apply( => @scope.notifs.push kind: 'error', content: parseError err) if err?
        
    # **private**
    # Update action zone depending on new active rule
    #
    # @param event [Event] triggering event
    # @param rule [String] new value for active rule
    # @param weapon [Numer] selected weapon rank (in weapons) to use in case of shoot
    _onSelectActiveRule: (event, rule, weapon = 0) =>
      @scope.activeRule = rule
      @scope.activeWeapon = weapon
      # reset targets
      @scope.needMultipleTargets = false
      @_multipleTargets = []
      @scope.zone = null
      if rule is 'move'
        @displayMovable()
      else if rule is 'assault'
        @displayDamageZone event, @scope.selected
          
    # **private**
    # Require help from the server if available.
    # Won't send any request if help is not wanted
    #
    # @param action [String] action for which help is needed
    _askForHelp: (action) =>
      return unless @scope.showHelp and @scope.squad?
      @atlas.ruleService.execute 'getHelp', @atlas.player, @scope.squad, {action: action}, (err, result) => @scope.$apply =>
        return @scope.notifs.push kind:'error', content: parseError err if err?
        @scope.help = result
      
    # **private**
    # Update replay commands after a replay action
    _updateReplayCommands: =>
      @scope.canStopReplay = if @atlas.replayPos? then 'enabled' else ''
      @scope.hasPrevAction = if @atlas.hasPreviousAction then 'enabled' else ''
      @scope.hasNextAction = if @atlas.hasNextAction then 'enabled' else ''
      
    # **private**
    # Fetch the current squad and all its members.
    # Refresh view once finished.
    # 
    # @param squad [Item] fetched squad
    _fetchSquad: (squad) =>
      # get squad and its members
      @atlas.Item.fetch [squad], (err, [squad]) => 
        return @scope.$apply( => @scope.notifs.push kind:'error', content: parseError err) if err?
        # then get members
        @atlas.Item.fetch squad.members, (err) => @scope.$apply => 
          return @scope.notifs.push kind:'error', content: parseError err if err?
          @scope.selected = null
          @scope.squad = squad
          
          @scope.showHelp = not @atlas.player.prefs?.discardHelp
          @_askForHelp 'start'

          # blips deployment, blip displayal
          if @scope.squad?.deployZone?
            @_toggleDeployMode()
          if @scope.squad.actions < 0 
            @scope.canEndTurn = '' 
            @scope.notifs.push kind: 'info', content: conf.texts.notifs.waitForOther
          else
            @scope.canEndTurn = 'enabled'
          # inhibit on replay (always) or turn end (if not alien and deploy) or deploy (and not alien)
          @_inhibit = if @scope.squad.isAlien and @scope.squad.deployZone? then @atlas.replayPos? else @atlas.replayPos? or @scope.squad.actions < 0 or @scope.squad.deployZone?
          
    # ** private**
    # Adapt UI to current deploy mode:
    # - If a deploy zone is added to squad: put info on deploy start, and for alien drop deploy zone
    # - If a deploy zone is removed: clean zone, and for marine, put info on deploy end
    _toggleDeployMode: =>
      return unless @scope.squad?
      if @scope.squad.deployZone?
        @_askForHelp 'startDeploy'
        @scope.canEndTurn = '' 
        @_inhibit = true
        if @scope.squad.isAlien
          # Auto select the first zone to deploy
          first = @scope.squad.deployZone.split(',')[0]
          # but quit if first is still handled
          return if first is @_currentZone
          @_currentZone = first
          @scope.deployScope = 'deployBlip'
          # add notification
          @scope.notifs.push kind: 'info', content: conf.texts.notifs.deployBlips
          # highligth deployable zone
          @atlas.ruleService.execute 'deployZone', @atlas.player, @scope.squad, {zone:@_currentZone}, (err, zone) => 
            @scope.$apply =>
              @scope.notifs.push kind: 'error', content: parseError err if err?
              return @scope.zone = null if err? or !zone? or zone.length is 0
              @scope.zone = 
                tiles: zone
                kind: 'deploy'
        else
          # add notification and inhibit
          @scope.notifs.push kind: 'info', content: conf.texts.notifs.deployInProgress
          @scope.selected = null
      else
        @_askForHelp 'endDeploy'
        if @scope.squad.isAlien
          @scope.canEndTurn = 'enabled' 
          # clean alien previous notifications
          @scope.notifs.splice 0, @scope.notifs.length
        else
          # indicates to marine that they can go on !
          @scope.notifs.push kind: 'info', content: conf.texts.notifs.deployEnded
        @_currentZone = null
        @scope.deployScope = null
        # inhibit on turn end or replay pos
        @_inhibit = @scope.squad.actions < 0 or @atlas.replayPos?
        # Redraw previously highlighted zone
        @_onSelectActiveRule null, @scope.activeRule, @scope.activeWeapon
      
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
            @location.path("#{conf.basePath}home").search err: 'gameRemoved'
        when 'update'
          @scope.$apply =>
            if model?.id is @scope.squad?.id 
              if 'actions' in changes
                # inhibit on replay (always) or turn end (if not alien and deploy) or deploy (and not alien)
                @_inhibit = if @scope.squad.isAlien and @scope.squad.deployZone? then @atlas.replayPos? else 
                  @atlas.replayPos? or @scope.squad.actions < 0 or @scope.squad.deployZone?
                if @scope.squad.actions < 0
                  @scope.canEndTurn = ''
                else
                  @scope.canEndTurn = 'enabled'
                  # auto trigger turn end
                  @_onEndTurn() if @scope.squad.actions is 0
              if 'deployZone' in changes
                @_toggleDeployMode() 
            else if model?.id is @scope.game?.id
              if 'finished' in changes
                return @location.path "#{conf.basePath}end" if model.finished
              if 'turn' in changes
                # if turn has change, notify
                @scope.notifs.push kind: 'info', content: conf.texts.notifs.newTurn
                # quit replay
                @atlas.stopReplay()
              if 'prevActions' in changes
                @_updateReplayCommands()
              if 'mainWinner' in changes and @scope.squad?
                if @scope.game.mainWinner is @scope.squad.name
                  content = conf.texts.notifs.mainMissionCompleted
                else
                  content = _.sprintf conf.texts.notifs.mainMissionCompletedBy, @scope.game.mainWinner
                @scope.notifs.push kind: 'info', content: content
            else if model is @scope.selected and model.dead
              @scope.selected = null
            else if model is @atlas.player and 'prefs' in changes
              @scope.showHelp = not @atlas.player.prefs?.discardHelp
            
    
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
      return if @scope.squad?.deployZone?
      # find selectable item inside clicked items
      item = _.find details.items, (item) => 
        return false if item.dead
        # takes in acccount possible parts (for dreadnought)
        return true for member in @scope.squad.members when member is item or (member.parts? and item in member.parts)
        false
      # if part is returned, use its main object
      item = item?.main or item
      
      @scope.$apply =>
        if @scope.selected is item
          @scope.selected = null
        else
          @scope.selected = item
          _.defer => @_askForHelp 'select'
          
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
      return if @_inhibit or not @scope.activeRule? or @scope.squad?.deployZone?
      @scope.$apply =>
        @scope.menuItems = []
        @scope.path = []
      
      proceed = (err = null, applicables = {}) =>
        return @scope.$apply( => @scope.notifs.push kind: 'error', content: parseError err) if err?
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
        # for shoot with autocannon, need to select targets
        if @scope.activeRule is 'shoot' and @scope.selected.weapons[@scope.activeWeapon]?.id is 'autoCannon'
          @scope.needMultipleTargets = true
          # add to current targets
          @_multipleTargets.push details.field if details.field?
        else
          # resolve board rules for the selected item at this coord
          @atlas.ruleService.resolve @scope.selected, details.x, details.y, @scope.activeRule, proceed
      else 
        # no selected item, just proceed.
        proceed()
        
    # **private**
    # Trigger a given rule of currently selected character, as it it was selected on menu
    #
    # @param rule [String] rule to trigger
    _askToExecuteRule: (rule) =>
      return if @_inhibit and not @scope.selected?
      switch rule
        when "open"
          return unless @scope.selected.doorToOpen?
          @_applicableRules = open: [target: @scope.selected.doorToOpen]
          break
        when "shoot"
          @_applicableRules = shoot: [target: @_multipleTargets[0]]
      @_onSelectMenuItem null, rule
          
    # **private**
    # Handler of map menu selection. Trigger the corresponding rule
    #
    # @param event [Event] click event inside map menu
    # @param rule [String] name of the selected item inside menu
    _onSelectMenuItem: (event, rule) =>
      # do not support yet multiple targets nor parameters
      return console.error "multiple targets not supported yet for rule #{rule}" if @_applicableRules[rule].length > 1
      return console.error "parameters not supported yet for rule #{rule}" if rule isnt 'shoot' and @_applicableRules[rule][0].params?.length > 0
            
      # trigger rule
      if rule is 'shoot'
        params = 
          weaponIdx: @scope.activeWeapon 
          multipleTargets: ("#{target.x}:#{target.y}" for target in @_multipleTargets)
          
        # reset mutliple targets
        @scope.needMultipleTargets = false
        @_multipleTargets = []
      else 
        params = {}
        
      @atlas.ruleService.execute rule, @scope.selected, @_applicableRules[rule][0].target, params, (err, result) =>
        return @scope.$apply( => @scope.notifs.push kind: 'error', content: parseError err) if err?   
        # refresh movable tiles
        @displayMovable()
      
      @_askForHelp rule
                
    # **private**
    # After a modal confirmation, trigger the end of turn.
    # No confirmation if squad hasn't any remaining actions
    _onEndTurn: =>
      return if @_inhibit
      # rule triggering
      trigger = =>
        @atlas.ruleService.execute 'endOfTurn', @atlas.player, @scope.squad, {}, (err) => @scope.$apply =>
          return @scope.notifs.push kind: 'error', content: parseError err if err?
          # add a notification
          @scope.notifs.push kind: 'info', content: conf.texts.notifs.waitForOther
      return trigger() if @scope.squad.actions is 0
      # still actions ? confirm end of turn
      confirm = @dialog.messageBox conf.titles.confirmEndOfTurn, conf.texts.confirmEndOfTurn, [
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
          return @scope.$apply( => @scope.notifs.push kind: 'error', content: parseError err) if err?
          # proceed with next deployement or quit mode
          @_toggleDeployMode()
      # still actions ? confirm end of turn
      confirm = @dialog.messageBox conf.titles.confirmDeploy, conf.texts.confirmEndDeploy, [
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
      @atlas.ruleService.execute 'deployBlip', @atlas.player, @scope.squad, coord, (err, result) =>
        # displays deployement errors
        console.log err, parseError err if err?
        @_askForHelp 'deploy'
        return @scope.$apply( => @scope.notifs.push kind: 'error', content: parseError err) if err?

    # **private**
    # Key up handler, to select this character with shortcut
    #
    # @param event [Event] key up event
    _onKey: (event) =>
      # disable if cursor currently in an editable element
      return if event.target.nodeName.toLowerCase() in ['input', 'textarea', 'select']
      # select current character if shortcut match
      if event.ctrlKey and event.keyCode in [49...57]
        @scope.$apply => @scope.selected = _.where(@scope.squad.members, dead:false)[event.keyCode-49]
        # stop key to avoid browser default behavior
        event.preventDefault()
        event.stopImmediatePropagation()
        return false