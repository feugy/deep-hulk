'use strict'

define [
  'underscore'
  'jquery'
  'util/common'
  'text!template/choose_dialog.html'
], (_, $, {getInstanceImage, parseError}, chooseDialogTpl) ->
    
  # two mode controller: displays squad configuration (for marines, before starting game)
  # or displays the game board (for marines and alien)
  class BoardController
              
    # Controller dependencies
    @$inject: ['$scope', '$location', '$dialog', 'atlas', '$rootScope', '$filter', '$interpolate']
    
    # Controller scope, injected within constructor
    scope: null
    
    # Link to Atlas service
    atlas: null
    
    # Link to Angular location service
    location: null
    
    # Link to Angular dialog service
    dialog: null
    
    # Angular's filter factory
    filter: null
    
    # Angular's expression interpolation factory
    interpolate: null
    
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
    # @param filter [Function] Angular's filter factory
    # @param interpolate [Function] Angular's expression interpolation factory
    constructor: (@scope, @location, @dialog, @atlas, rootScope, @filter, @interpolate) ->
      @_applicableRules = {}
      @_inhibit = false
      @_currentZone = null
      @scope.zoom = 1
      @scope.zone = null
      @scope.canEndTurn = false
      @scope.hasNextAction = false
      @scope.hasPrevAction = false
      @scope.canStopReplay = false
      @scope.activeRule = null
      @scope.activeWeapon = 0
      @scope.showOrders = false
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
        
      @scope._onMapClick = @_onClick
      @scope._onMapRightclick = @_onSelect
      @scope._onSelectMember = (member) => _.defer => @_onSelect null, items:[member]
      @scope._askToExecuteRule = @_askToExecuteRule
      @scope._onEndTurn = @_onEndTurn
      @scope._onEndDeploy = @_onEndDeploy
      @scope._onBlipDeployed = @_onBlipDeployed
      @scope._onDisplayEquipment = @_onDisplayEquipment
      @scope._onApplyOrder = @_onApplyOrder
      @scope._onHover = (evt, details) =>
        @displayDamageZone(evt, details.field) if @scope.activeRule is 'shoot'
      @scope.getInstanceImage = getInstanceImage
      @scope.deployScope = null
      @scope.sendMessage = @sendMessage
      # show help unless specified
      @scope.showHelp = false
      @scope.help = null
      
      # navigate to other page
      @scope.navTo = (path, params = {}) =>
        @location.path("#{conf.basePath}#{path}").search params
        
      # update zone on replay quit/enter
      rootScope.$on 'replay', (ev, details) =>
        @_updateInhibition()
        if details.active
          @scope.zone = null
        else
          @_currentZone = null
          @_toggleDeployMode false
      
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
        
        document.title = @filter('i18n') 'titles.app', args: game
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
      
    # Display a notification to player.
    # If tab has not focus, tries to display a desktop notification
    notify: (notif) =>
      # always displays in-game
      @scope.notifs.push notif
      if Notification?.permission is 'granted' and document.hidden
        # send a desktop notification
        popup = new Notification @filter('i18n')('titles.desktopNotification', args: @scope.game), 
          body: notif.content
          icon: "#{conf.rootPath}image/notif-alien.png"
        # click will open the game
        popup.onclick = => window.focus()
        # auto close after 4 seconds
        _.delay =>
          popup.close()
        , 4000
          
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
        @scope.$apply( => @notify kind: 'error', content: parseError err) if err?
      
    # **private**
    # Inihibit interface when:
    # - replay in progress
    # - deployment in progress and not alien
    # - single player and not current player
    # - multiple payers and no actions left
    _updateInhibition: =>
      if @atlas.replayPos?
        # action replay in progress
        @_inhibit = true
      else if @scope.squad?.deployZone?
        # during deployement, only alien can play
        @_inhibit = not @scope.squad.isAlien
      else if @scope.squad?.actions < 0 or @scope.game?.singleActive and @scope.squad?.activeSquad isnt @scope.squad?.name
        # squad is not active or has no actions left
        @_inhibit = true
      else
        @_inhibit = false
      
    # **private**
    # Require help from the server if available.
    # Won't send any request if help is not wanted
    #
    # @param action [String] action for which help is needed
    _askForHelp: (action) =>
      return unless @scope.showHelp and @scope.squad?
      @atlas.ruleService.execute 'getHelp', @atlas.player, @scope.squad, {action: action}, (err, result) => @scope.$apply =>
        return @notify kind:'error', content: parseError err if err?
        @scope.help = result
      
    # **private**
    # Update replay commands after a replay action
    _updateReplayCommands: =>
      @scope.canStopReplay = @atlas.replayPos?
      @scope.hasPrevAction = @atlas.hasPreviousAction
      @scope.hasNextAction = @atlas.hasNextAction
      
    # **private**
    # Fetch the current squad and all its members.
    # Refresh view once finished.
    # 
    # @param squad [Item] fetched squad
    _fetchSquad: (squad) =>
      # get squad and its members
      @atlas.Item.fetch [squad], (err, [squad]) => 
        return @scope.$apply( => @notify kind:'error', content: parseError err) if err?
          
        # then get members
        @atlas.Item.fetch squad.members, (err) => @scope.$apply => 
          return @notify kind:'error', content: parseError err if err?
          @scope.selected = null
          @scope.squad = squad
          
          @scope.showHelp = not @atlas.player.prefs?.discardHelp
          @_askForHelp 'start'
          
          # send notification in single player mode
          @_updateInhibition()
          @_onActiveSquadChange()
          @_updateChosenOrders()
            
          # blips deployment, blip displayal
          if @scope.squad?.deployZone?
            @_toggleDeployMode()
          if @scope.squad.actions < 0 
            @scope.canEndTurn = false 
            @notify kind: 'info', content: conf.texts.notifs.waitForOther unless @scope.game.singleActive
          else
            @scope.canEndTurn = true
          
    # ** private**
    # Adapt UI to current deploy mode:
    # - If a deploy zone is added to squad: put info on deploy start, and for alien drop deploy zone
    # - If a deploy zone is removed: clean zone, and for marine, put info on deploy end
    #
    # @param withNotifs [Boolean] set to false to inhibit notifications send to player. Default to true.
    _toggleDeployMode: (withNotifs = true)=>
      return unless @scope.squad?
      @_updateInhibition()
      if @scope.squad.deployZone?
        @_askForHelp 'startDeploy'
        @scope.canEndTurn = false
        if @scope.squad.isAlien
          # Auto select the first zone to deploy
          first = @scope.squad.deployZone.split(',')[0]
          # but quit if first is still handled
          return if first is @_currentZone
          @_currentZone = first
          @scope.deployScope = 'deployBlip'
          # add notification
          @notify kind: 'info', content: conf.texts.notifs.deployBlips if withNotifs
          # highligth deployable zone
          @atlas.ruleService.execute 'deployZone', @atlas.player, @scope.squad, {zone:@_currentZone}, (err, zone) => 
            @scope.$apply =>
              @notify kind: 'error', content: parseError err if err?
              return @scope.zone = null if err? or !zone? or zone.length is 0
              @scope.zone = 
                tiles: zone
                kind: 'deploy'
        else
          # add notification and inhibit
          @notify kind: 'info', content: conf.texts.notifs.deployInProgress
          @scope.selected = null
      else
        @_askForHelp 'endDeploy'
        if @scope.squad.isAlien
          @scope.canEndTurn = true
          # clean alien previous notifications
          @scope.notifs.splice 0, @scope.notifs.length
        else
          # indicates to marine that they can go on !
          @notify kind: 'info', content: conf.texts.notifs.deployEnded if withNotifs
          @_updateChosenOrders()
        @_currentZone = null
        @scope.deployScope = null
        # Redraw previously highlighted zone
        @_onSelectActiveRule null, @scope.activeRule, @scope.activeWeapon
              
    # **private**
    # Trigger a given rule of currently selected character
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
      @_executeRule rule
                
    # **private**
    # Execute the given rule, using _applicableRules to get parameters and so one 
    #
    # @param rule [String] name of the selected rule to execute inside applicables
    _executeRule: (rule) =>
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
        return @scope.$apply( => @notify kind: 'error', content: parseError err) if err?   
        # refresh movable tiles
        @displayMovable()
      
      @_askForHelp rule
      
    # **private**
    # If first action and remaining orders, display dialog box to trigger them.
    _updateChosenOrders: =>
      @scope.showOrders = @scope.squad.firstAction and @scope.squad.orders.length > 0 and not @_inhibit
      @_askForHelp 'order' if @scope.showOrders
        
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
    # Display to player a notification on which squad is active, if game is in proper mode
    _onActiveSquadChange: =>
      return unless @scope.game.singleActive
      @_updateInhibition()
      if @scope.squad.activeSquad isnt @scope.squad.name
        @notify kind: 'info', content: @interpolate(conf.texts.notifs.waitForSquad) target: conf.labels[@scope.squad.activeSquad or 'noActiveSquad']
      else
        @notify kind: 'info', content: conf.texts.notifs.playNow
        
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
                @_updateInhibition()
                @scope.canEndTurn = @scope.squad.actions >= 0
              if 'deployZone' in changes
                @_toggleDeployMode() 
              if 'activeSquad' in changes
                @_onActiveSquadChange()
              if 'firstAction' in changes
                @_updateChosenOrders()
            else if model?.id is @scope.game?.id
              if 'finished' in changes
                return @location.path "#{conf.basePath}end" if model.finished
              if 'turn' in changes
                # if turn has change, notify
                @notify kind: 'info', content: conf.texts.notifs.newTurn
                # quit replay
                @atlas.stopReplay()
              if 'prevActions' in changes
                @_updateReplayCommands()
              if 'events' in changes
                # try to display notification when other squad uses equipment or orders
                event = @scope.game.events[-1..]?[0]
                if event?.id isnt @scope.squad.id
                  # Display notification
                  content = conf.texts.notifs["#{event.used}Used"]
                  return unless content?
                  @notify kind: 'info', content: @interpolate(content) target: @filter('i18n') "labels.#{event.name}"
              if 'mainWinner' in changes and @scope.squad?
                if @scope.game.mainWinner is @scope.squad.name
                  content = conf.texts.notifs.mainMissionCompleted
                else
                  content = @interpolate(conf.texts.notifs.mainMissionCompletedBy) target: @filter('i18n') "labels.#{@scope.game.mainWinner}"
                @notify kind: 'info', content: content
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
      return if @_inhibit
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
    # Handler invoked when clicking on map: 
    # - selected member ? resolves (an applies) active rule on clicked target
    # - selected member, 'shoot' is active and autoCannon ? adds a target
    # - reinforcement target and alien ? tries to reinforce.
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
      
      if @scope.selected?
        # for shoot with autocannon, need to select targets
        if @scope.activeRule is 'shoot' and @scope.selected.weapons[@scope.activeWeapon]?.id is 'autoCannon'
          @scope.needMultipleTargets = true
          # add to current targets
          @_multipleTargets.push details.field if details.field?
        else
          # resolve board rules for the selected item at this coord
          @atlas.ruleService.resolve @scope.selected, details.x, details.y, @scope.activeRule, (err, applicables) =>
            return @scope.$apply( => @notify kind: 'error', content: parseError err) if err?
            # keep for further use
            @_applicableRules = applicables
            keys = _.keys applicables
            return if keys.length is 0
            @_executeRule keys[0] if keys.length is 1 and keys
      else if @scope.squad.supportBlips > 0 and _.any(details?.items, (item) -> item?.type?.id is 'reinforcement')
        # click on reinforcement get possible blip to reinforce
        blipIdx = (i for member, i in @scope.squad.members when member?.map is null and member?.isSupport)
        return unless blipIdx.length
        # randomly pick one and go !
        @atlas.ruleService.execute 'reinforce', @atlas.player, @scope.squad, 
          x: details.x
          y: details.y
          rank: blipIdx[_.random 0, blipIdx.length-1]
        , (err, result) =>
          # displays deployement errors
          return @scope.$apply( => @notify kind: 'error', content: parseError err) if err?
      
    # **private**
    # Display a modal popup to choose equipement to apply
    _onDisplayEquipment: (event) =>
      outer = 
        possibles: (name: item, selectMember: item is 'meltaBomb' for item in @scope.squad.equipment when item isnt 'detector')
        selected: []
        members: (marine for marine in @scope.squad.members when not marine.dead) 
        hovered: null
        displayHelp: (event, item) => outer.hovered = item
      buttons = [label: conf.buttons.close]
      
      if outer.possibles.length
        buttons.splice 0, 0, label: conf.buttons.equip, result: true
        message = conf.texts.applyEquipment
      else 
        message = conf.texts.noEquipment
        
      @dialog.messageBox(conf.titles.equipment, message, buttons, chooseDialogTpl, outer).open().then (confirmed) =>
        return unless confirmed and outer.selected.length is 1
        selected = outer.selected[0]
        marine = _.findWhere(@scope.squad.members, id:selected.memberId) or @scope.squad.members[0]
        @atlas.ruleService.execute 'useEquipment', @scope.squad, marine, {equipment: selected.name}, (err, message) => @scope.$apply =>
          return @notify kind: 'error', content: parseError err if err?
          # add a notification
          if message
            @notify kind: 'info', content: @interpolate(conf.texts.notifs[message]) target: marine?.name
        
    # **private**
    # On order selection, relay to server o effectively apply the order
    #
    # @param order [String] chosen order
    # @param memberId [String] if required by chosen order, selected member id
    _onApplyOrder: (order, memberId = null) =>
      marine = _.findWhere(@scope.squad.members, id:memberId) or @scope.squad.members[0]
      @atlas.ruleService.execute 'applyOrder', @scope.squad, marine, {order: order}, (err, message) => @scope.$apply =>
        return @notify kind: 'error', content: parseError err if err?
        # add a notification
        if message
          @notify kind: 'info', content: @interpolate(conf.texts.notifs[message]) target: marine?.name 
                
    # **private**
    # After a modal confirmation, trigger the end of turn.
    # No confirmation if squad hasn't any remaining actions
    _onEndTurn: =>
      return if @_inhibit
      # rule triggering
      trigger = =>
        @atlas.ruleService.execute 'endOfTurn', @atlas.player, @scope.squad, {}, (err) => @scope.$apply =>
          return @notify kind: 'error', content: parseError err if err?
          # add a notification
          @notify kind: 'info', content: conf.texts.notifs.waitForOther unless @scope.game.singleActive
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
      return if @_inhibit or @_currentZone is null
      # rule triggering
      trigger = =>
        @atlas.ruleService.execute 'endDeploy', @atlas.player, @scope.squad, {zone: @_currentZone}, (err) =>
          return @scope.$apply( => @notify kind: 'error', content: parseError err) if err?
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
        blipIdx = (i for member, i in @scope.squad.members when member?.map is null and not member?.isSupport)
        return unless blipIdx.length > 0
        _.extend coord, 
          zone: @_currentZone
          rank: blipIdx[_.random 0, blipIdx.length-1]
      # trigger the relevant rule
      @atlas.ruleService.execute 'deployBlip', @atlas.player, @scope.squad, coord, (err, result) =>
        # displays deployement errors
        @_askForHelp 'deploy'
        return @scope.$apply( => @notify kind: 'error', content: parseError err) if err?

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