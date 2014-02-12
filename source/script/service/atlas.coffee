'use strict'

define [
  'app', 
  'atlas'
], (app, AtlasFactory) ->
  
  # declare Atlas as an angular service
  app.factory 'atlas', ['$rootScope', (scope) -> 
    
    # instanciate the Atlas library
    service = AtlasFactory scope, 
      debug: false
      # Extension point invoked when an update is received from server, before processing data.
      # Cancel updates of models that are concerned by replay action 
      # @param className [String] updated model class name
      # @param changes [Object] raw new values (always contains id)
      # @param  callback [Function] end callback to resume update process. Invoke with null and changes, or with anything as first argument to cancel update
      preUpdate: (className, changes, callback) ->
        return callback null, changes unless className is 'Item' and unwiredIds?
        callback changes.id in unwiredIds, changes
        
    # for debug purposes
    window._atlas = service
    
    scope.$on 'modelChanged', (ev, operation, model, changes) -> 
      # updates game replay action length if needed
      if operation is 'update' and model.id is replayGame?.id and 'nextActions' in changes
        service.replayLength = replayGame.nextActions?.length
        service.hasNextAction = service.replayPos? and  service.replayPos < service.replayLength
        service.hasPreviousAction = service.replayLength > 0
      # refresh scope when model changed
      scope.$apply()
    
    ############################################################################
    # add replay action facilities
      
    # current position within the replay action stack 
    service.replayPos = null
    
    # Number of total actions in replay
    service.replayLength = 0
    
    # Indicate the existence of a next action
    service.hasNextAction = false
    
    # Indicates the existence of a previous action
    service.hasPreviousAction = false
    
    # **private**
    # the game being watched
    replayGame = null
    
    # **private**
    # items ids beeing unwired during action replay
    unwiredIds = null
    
    # Init the replay service with a given game
    # @param game [Model] the game model being watched.
    service.initReplay = (game) ->
      replayGame = game
      unwiredIds = null
      @replayLength = replayGame?.nextActions?.length
      @replayPos = null
      @hasPreviousAction = @replayLength > 0
      @hasNextAction = false
      
    # Navigate to next action in game history.
    #
    # @param callback [Function] invoked without arguments when models have been updated
    service.nextAction = (callback = ->) -> @navigate 1, callback
    
    # Navigate to previous action in game history.
    #
    # @param callback [Function] invoked without arguments when models have been updated
    service.previousAction = (callback = ->) -> @navigate -1, callback
    
    # Quit action replay.  
    #
    # @param callback [Function] invoked without arguments when models have been updated
    service.stopReplay = (callback = ->) -> @navigate null, callback
    
    # Navigate within the game history.
    # When entering action replay mode, modified models are unwired from server 
    # updates, and "fake" server updates are used to simulate history.
    # Once in this mode, no other action are permitted
    # If amound aims at an unknown game action, the game will remain unchanged.
    #
    # @param amount [Number] Number of action to go back (negative) or forward (positive), or null to leave action replay
    # @param callback [Function] invoked without arguments when models have been updated
    service.navigate = (amount, callback = ->) ->
      # quit replay action mode
      if amount is null
        return callback null unless @replayPos?
        forward = true
        amount = @replayLength - @replayPos
      else
        forward = amount > 0
      step = Math.abs amount
            
      # enter in replay action mode if not already the case
      @replayPos = @replayLength unless @replayPos? 
      # check new expected position
      return unless 0 <= @replayPos+amount <= @replayLength
             
      applyAction = =>
        # use nextActions if amount is positive, and prevActions otherwise
        if forward
          @replayPos++ 
          action = replayGame.nextActions[@replayPos-1]
        else 
          @replayPos--
          action = replayGame.prevActions[@replayPos]
        
        @hasNextAction = @replayPos < @replayLength
        @hasPreviousAction = @replayPos > 0
            
        # always start from fresh item and apply all previous actions
        async.each JSON.parse(action.effects), (effect, next) =>
          @Item.findById effect.id, (err, item) =>
            return next err if err?
            @modelUpdate 'Item', effect, next
        , (err) =>
          return callback err if err? 
          
          if @replayPos is @replayLength
            @replayPos = null
            # wired all unwired models
            unwiredIds = null
            console.log "quit action replay"
            scope.$broadcast 'replay', active:false
          
          if --step > 0
            applyAction()
          else
            callback err
                           
      if unwiredIds is null
        console.log "enter action replay"
        scope.$broadcast 'replay', active:true
        # get all models from map to keep their ids for unwiring
        @Map.findById replayGame.id.replace('game', 'map'), (err, map) =>
          return console.error err if err?
          @Item.find map: map, (err, fresh) =>
            return console.error err if err?   
            unwiredIds = _.pluck fresh, 'id'
            applyAction()
      else
        # immediately navigate into replay history
        applyAction()

    service
  ]