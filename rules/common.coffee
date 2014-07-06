_ = require 'underscore'
async = require 'async'
utils = require 'hyperion/util/model'
Item = require 'hyperion/model/Item'
ClientConf = require 'hyperion/model/ClientConf'
{checkMission} = require './missionUtils'
{freeGamesId} = require './constants'

dices =
  w: [0, 0, 0, 0, 1, 2]
  r: [0, 0, 0, 1, 2, 3]
  
# Removes types from stored action values
#
# @param obj [Object] clean object
cleanValues = (obj) ->
  if _.isArray obj
    res = []
    # do not store linked objects types within arrays
    for value, i in obj 
      if _.isObject value
        if value._className in ['ItemType', 'EventType', 'Map']
          # do not store whole type
          res[i] = value.id
        else
          typeId = undefined
          if value._className in ['Item', 'Event']
            typeId = value.type.id
            delete value.type
          res[i] = cleanValues value
          res[i].type = typeId
      else
        res[i] = value
        
  else if _.isObject obj
    res = {}
    if obj._className in ['ItemType', 'EventType', 'Map']
      # do not store whole type
      return obj.id
    else if obj._className in ['Item', 'Event']
      # do not store linked objects types
      obj = obj.toJSON()
      obj.type = obj.type?.id
      obj.map = obj.map?.id
    # recurse on other properties
    for attr, value of obj
      res[attr] = cleanValues value
  
  else
    res = obj
  res
    
module.exports = {
  
  # Reset flags used during help displayal
  #
  # @param player [Player] player whose prefs are updated
  resetHelpFlags: (player) ->
    # reset help flags
    player.prefs.help = {}
  
  # Sum elements of an array
  #
  # @param arr [Array<Number>] numbers to sum
  # @return the sum of array elements
  sum: (arr) ->
    _.reduce arr, ((memo, num) => memo+num), 0
  
  # Returns the game id from a given item (must have a squad)
  #
  # @param item [Item] item used to retreive game id
  # @return the corresponding game id
  getGameId: (item) ->
    id = if item.type.id is 'squad' then item.id else item.squad?.id or item.squad
    id?.replace(/-\d$/, '')?.replace 'squad', 'game'
    
  # Load game corresponding to a given item (that must be or have a squad)
  #
  # @param item [Item|String] marine/squad used to retreive game id, or gameId itself (as String)
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback game [Item] the corresponding game
  getGame: (item, callback) ->
    gameId = item
    unless item is String
      gameId = module.exports.getGameId item
      unless gameId?
        return callback new Error "Failed to retrieve game from item #{item?.id} (#{item?.type?.id})" 
      
    Item.findCached [gameId], (err, [game]) ->
      err = new Error "no game with id #{gameId} found" if !err and !game?
      return callback err if err?
      callback null, game
     
  # Get from configuration the bounding rect of a given deploy zone
  #
  # @param missionId [String] id of the current mission, read into configuration
  # @param zone [String] id to identify consulted zone, null to get all zones
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback zone [Object] a JSON object containing lowY, lowX and upY upX
  getDeployZone: (missionId, zone, callback) ->
    # get deployable zone dimensions in configuration
    ClientConf.findCached ['default'], (err, [conf]) =>
      return callback err if err?
      zones = conf.values.maps[missionId]
      if zone?
        # get selected zone
        if zone of zones
          callback null, zones[zone]
        else
          callback new Error "no deployable zone #{zone} on mission #{missionId}" 
      else
        # return all zones
        callback null, zones
      
  # Apply damages on a target, randomly removing enought weapon if target is a dreadnought
  # No effect if target isn't a dreadnought, or if target is dead
  #
  # @param target [Model] damaged target
  # @param loss [Number] lost life points.
  damageDreadnought: (target, loss) ->
    if target.kind is 'dreadnought' and target.life > 0
      for i in [0...loss]
        idx = 1 + Math.floor Math.random()*(target.weapons.length-1)
        console.log "#{target.kind} (#{target.squad.name}) lost its #{target.weapons[idx].id} !"
        target.weapons.splice idx, 1
    
  # Roll dices
  #
  # @param spec [Object] a given dices specification: r for red dices, w for white dices
  # @param reroll [Boolean] true to allow one dice to be re-rolled. default to false
  # @return an array of dices results: numbers in the same order as spec
  rollDices: (spec, reroll = false) ->
    return [0] unless spec
    
    result = []
    for kind, num of spec when num > 0
      for t in [1..num]
        # role a 6-face dice
        result.push dices[kind][Math.floor Math.random()*6]
        
    if reroll
      i = 0
      # reroll rules: reroll first dice bellow last 2 possible results.
      for kind, num of spec when num > 0 
        for t in [1..num]
          if result[i] < dices[kind][4]
            value = dices[kind][Math.floor Math.random()*6]
            console.log "reroll dice !"
            #  Then use new roll if better.
            result[i] = value if value > result[i]
            return result
          i++
    result
    
  # Distance function: number of tiles between two point on a map
  # (distance du fou d'échiquier)
  #
  # @param ptA [Object] x and y coordinate of first point
  # @param ptB [Object] x and y coordinate of second point
  # @return the number of tiles that separates the two points
  distance: (ptA, ptB) -> 
    Math.max Math.abs(ptA.x-ptB.x), Math.abs(ptA.y-ptB.y)
    
  # Select items within rectangle delimited by from and to coordinates.
  # Dead characters are not returned.
  #
  # @param mapId [String] id of current map
  # @param from [Object] optionnal shooter position (x/y coordinates). Select in all map if not specified
  # @param to [Object] optionnal target position (x/y coordinates). Use from if not specified
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback items [Array<Item>] loaded items between shooter and target
  selectItemWithin: (mapId, from, to, callback) ->
    if _.isFunction from
      callback = from
      from = null
    else if _.isFunction to
      [callback, to] = [to, from]
    return Item.where('map', mapId).where('dead').ne(true).exec callback unless from?
    if from.x is to.x and from.y is to.y
      Item.where('map', mapId)
        .where('x', from.x)
        .where('y', from.y)
        .where('dead').ne(true)
        .exec callback
    else
      Item.where('map', mapId)
        .where('x').gte(if from.x > to.x then to.x else from.x).lte(if from.x > to.x then from.x else to.x)
        .where('y').gte(if from.y > to.y then to.y else from.y).lte(if from.y > to.y then from.y else to.y)
        .where('dead').ne(true)
        .exec callback
    
  # Make points computation for both squad involved in an attack
  #
  # @param winner [Item] item that was won the attack
  # @param looser [Item] item that was killed
  # @param rule [Rule] caller rule, to save modified objects
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  countPoints: (winner, looser, rule, callback) ->
    # subtract points to target team if it's a marine (alien can't loose points)
    looser.squad.points -= looser.points unless looser.squad.isAlien
    # add points to actor team unless target kind is same (do not count friendly fire)
    winner.squad.points += looser.points if winner.squad.isAlien or looser.squad.isAlien
    rule.saved.push looser.squad, winner.squad
    callback null
    
  # Get position of the next door, using the door's image number
  #
  # @param door [Item] door to find neighbor
  # @return the next's door position (x/y coordinates)
  getNextDoor: (door) ->
    # get next door, depending on image num
    switch door.imageNum
      when 0, 2, 8, 10 then x:door.x+1, y:door.y
      when 1, 3, 9, 11 then x:door.x-1, y:door.y
      when 4, 6, 12, 14, 16, 18 then x:door.x, y:door.y-1
      when 5, 7, 13, 15, 17, 19 then x:door.x, y:door.y+1
      else null
        
  # When a marine or alien character is removed from map (by killing it or when quitting)
  # this method checks that game still goes on. 
  # A game may end if no more marine is on the map
  #
  # It's possible to ignore callback, if you are absolutely certain that a marine is still living on map.
  #
  # @param item [Item] the removed item
  # @param rule [Rule] the concerned rule, for saves
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  removeFromMap: (item, rule, callback = ->) ->     
    mapId = item?.map?.id
    unless mapId?
      return callback new Error "Cannot remove item #{item?.id} (#{item?.type?.id}) from map because it doesn't have one"
    # Mak as dead  
    item.life = 0
    item.dead = true
    
    # mark parts for death also
    if item.parts?
      for part in item.parts
        part.dead = true 
        part.life = 0

    # removing last living marine on map
    Item.find {map: mapId, type: 'marine', dead:false}, (err, marines) ->
      return callback err if err?
      return callback null unless marines.length is 1 and marines[0]?.id is item?.id
      # select the game object and modifies it
      module.exports.getGame item, (err, game) ->
        return callback err if err?
        game.finished = true
        console.log "game #{game.name} is finished"
        rule.saved.push game
        # removes also from free games list if necessary
        Item.findCached [freeGamesId], (err, [freeGames]) =>
          return callback err if err?
          idx = freeGames.games.indexOf(game.id)
          if idx isnt -1
            freeGames.games.splice idx, 1
            rule.saved.push freeGames
          # check mission end
          if _.isString item.squad
            return Item.findCached [item.squad], (err, [squad]) =>
              return callback err if err?
              checkMission squad, 'end', null, rule, callback
          checkMission item.squad, 'end', null, rule, callback
     
  # It's possible for a rule to modify or remove items and then to select them
  # from db with their unmodified values, leading to unconsitant results.
  # Merge items with saved/removed object of a given rule
  #
  # @param objects [Array<Model>] list of objects from db, directly modified
  # @param rule [Rule] current rule of which saved/removed object are merges with previous parameter
  mergeChanges: (objects, rule) ->
    last = objects.length-1
    i = 0
    while i < last 
      obj = objects[i]
      # removed may contains object but also just ids
      if _.find(rule.removed, (removed) -> if removed?.id? then removed.id is obj?.id else removed is obj?.id)?
        objects.splice i, 1
        last--
      else
        saved = _.find rule.saved, (other) -> other?.id is obj?.id
        objects[i] = saved if saved?
        i++
  
  # Add an action to current game, for action replay
  #
  # @param kind [String] action kind
  # @param actor [Item] concerned actor, used to retrieve game. Must be or have a squad
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param rule [Rule] current rule of which saved/removed object are merges with previous parameter
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  addAction: (kind, actor, effects, rule, callback) ->
    # retrieve the corresponding game
    module.exports.getGame actor, (err, game) ->
      return callback err if err?
      
      # creates an action for this movement: previous state
      game.prevActions.push
        kind: kind
        actorId: actor.id
        gameId: game.id
        effects: cleanValues (
          for effect in effects
            # adds id if not already present
            effect[1].id = effect[0].id
            effect[1]
        )
        
      # and next state, computed from current models
      game.nextActions.push
        kind: kind
        actorId: actor.id
        gameId: game.id
        effects: cleanValues (
          for effect in effects
            newEffect = id: effect[0].id
            # get values directly from modified model
            newEffect[attr] = effect[0][attr] for attr of effect[1]
            newEffect
        )
      rule.saved.push game
      callback null
      
  # Enrich an existing action's effects, without adding a new action
  #
  # @param actor [Item] concerned actor, used to retrieve game. Must be or have a squad
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param rPos [Number] reverse position to choose which action to enrich. Default to 0 (last action)
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  enrichAction: (actor, effects, rPos, callback) ->
    # default values
    if _.isFunction rPos
      callback = rPos
      rPos = 0
      
    # retrieve the corresponding game
    module.exports.getGame actor, (err, game) ->
      return callback err if err?
    
      last = game.prevActions[game.prevActions.length-(1+rPos)].effects
      for effect in effects
        # adds id if not already present
        effect[1].id = effect[0].id
        last.push cleanValues effect[1]
        
      last = game.nextActions[game.nextActions.length-(1+rPos)].effects
      for effect in effects
        newEffect = id: effect[0].id
        # get values directly from modified model
        newEffect[attr] = effect[0][attr] for attr of effect[1]
        last.push cleanValues newEffect
        
      callback null
    
  # Indicates wether two items have the same position.
  # You need to select the right range of models
  #
  # @param items [Array<Model>] checked models.
  # @return true if two models have the same position
  hasSharedPosition: (items) ->
    for model in items when model?.type?.id in ['marine', 'alien'] and not model?.dead and model?.map?
      item = _.find items, (item) -> item?.id isnt model.id and item?.type?.id is model.type.id and item?.x is model.x and item?.y is model.y and not item?.dead and item?.map?
      if item?
        console.log "has same position (#{model.x}:#{model.y}): #{model.kind or model.name} and #{item.kind or item.name}"
        return true
    return false
    
  # Store current fields values of a given model into effects array, to be used in game log
  #
  # @param model [Model] model for which state is created
  # @param fields [String] list of fields to add to created state
  # @return the created state
  makeState: (model, fields...) ->
    state = [model, {}]
    for field in fields
      state[1][field] = if _.isArray model[field] then model[field].concat() else model[field]
    state
    
  # Store into an actor's log a given result (or list of results).
  #
  # @param actor [Item] the concerned actor
  # @param result [Object|Array<Object>] an arbitrary result or list of results
  logResult: (actor, result) ->
    if _.isArray result
      actor.log = actor.log.concat result
    else
      actor.log.push result
   
  # Common behaviour of all twist:
  # - releases all squad from twist waiting
  # - adds an event to game for replay and notification
  # - send twist name to caller for notification
  #
  # @param twist [String] twist name applied
  # @param game [Item] game concerned
  # @param concerned [Item] squad concerned by this event
  # @param effects [Array] twist effects to be stored in action history
  # @param rule [Rule] rule used to store saved and removed objects
  # @param stopWaiting [Boolean] release all squad from waiting. Default to true
  # @param args [Object] twist message extra arguments (name is used to refer to twist target). Default to undefined
  # @param callback [Function] called when the rule is applied, with an 
  # optionnal error first argument and name of the applied twist as second
  useTwist: (twist, game, concerned, effects, rule, stopWaiting, args, callback) ->
    # default values
    if _.isFunction stopWaiting
      callback = stopWaiting
      args = undefined
      stopWaiting = true
    else if _.isFunction args
      callback = args
      args = undefined
      
    # release other squad from waiting
    if stopWaiting
      other.waitTwist = false for other in game.squads
    
    # add in history for replay and other players
    effects.push module.exports.makeState game, 'events'
    game.events.push 
      name: concerned.name
      kind: 'twist'
      used: twist
      args: args
    module.exports.addAction 'twist', concerned, effects, rule, callback
}