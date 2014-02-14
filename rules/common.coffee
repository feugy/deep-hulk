_ = require 'underscore'
utils = require 'hyperion/util/model'
Item = require 'hyperion/model/Item'
Event = require 'hyperion/model/Event'
EventType = require 'hyperion/model/EventType'

actionType = null
EventType.findCached ['action'], (err, [type]) =>
  err = "no type found" if !err and !type?
  throw new Error "Failed to select action event type at start: #{err?.message or err}" if err?
  actionType = type 

dices =
  w: [0, 0, 0, 0, 1, 2]
  r: [0, 0, 0, 1, 1, 3]
  
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
    (item.squad?.id or item.squad)?.replace(/-\d$/, '')?.replace 'squad', 'game'
    
  # Load game corresponding to a given item (that must have a squad)
  #
  # @param item [Item|String] item used to retreive game id, or gameId (as String)
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback game [Item] the corresponding game
  getGame: (item, callback) ->
    gameId = item
    unless item is String
      gameId = module.exports.getGameId item
      unless gameId?
        return callback new Error "Cannot remove item #{item?.id} (#{item?.type?.id}) from map because it doesn't have a squad" 
      
    Item.findCached [gameId], (err, [game]) ->
      err = new Error "no game with id #{gameId} found" if !err and !game?
      return callback err if err?
      callback null, game
    
  # Roll dices
  #
  # @param spec [String] a given dices specification: (DL)+ where D is a number and L is 'w' or 'r': 3w2r
  # @return an array of dices results: numbers in the same order as spec
  rollDices: (spec) ->
    match = spec.match /(\d[wr])/g
    result = []
    for spec in match
      times = parseInt spec[0]
      for t in [1..times]
        # role a 6-face dice
        result.push dices[spec[1]][Math.floor Math.random()*6]
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
    return Item.find {map: mapId}, callback unless from?
    if from.x is to.x and from.y is to.y
      Item.find {map: mapId, x: from.x, y: from.y}, callback
    else
      Item.where('map', mapId)
        .where('type').ne('logEntry')
        .where('x').gte(if from.x > to.x then to.x else from.x)
        .where('x').lte(if from.x > to.x then from.x else to.x)
        .where('y').gte(if from.y > to.y then to.y else from.y)
        .where('y').lte(if from.y > to.y then from.y else to.y)
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
    winner.squad.points += looser.points if looser.squad.isAlien isnt winner.squad.isAlien
    rule.saved.push looser.squad, winner.squad
    callback null
    
  # When a marine or alien character is removed from map (by killing it or when quitting)
  # this method checks that game still goes on. 
  # A game may end if:
  # - no more marine is on the map
  #
  # @param item [Item] the removed item
  # @param rule [Rule] the concerned rule, for saves
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  removeFromMap: (item, rule, callback) ->     
    mapId = item?.map?.id
    unless mapId?
      return callback new Error "Cannot remove item #{item?.id} (#{item?.type?.id}) from map because it doesn't have one"
    # Mak as dead  
    item.life = 0
    item.dead = true
    # decreases actions
    item.squad.actions-- unless item.moves is 0
    item.squad.actions -= Math.max item.rcNum, item.ccNum
    # removing last living marine on map
    Item.find {map: mapId, type: 'marine', dead:false}, (err, marines) ->
      return callback err if err?
      if marines.length is 1 and marines[0]?.id is item?.id
        # select the game object and modifies it
        module.exports.getGame item, (err, game) ->
          return callback err if err?
          game.finished = true
          console.log "game #{game.name} is finished"
          rule.saved.push game
      # end
      callback null
     
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
        saved = _.find rule.saved, (saved) -> saved?.id is obj?.id
        objects[i] = saved if saved?
        i++
  
  # Add an action to current game, for action replay
  #
  # @param kind [String] action kind
  # @param actor [Item] concerned actor, used to retrieve game. Must have a squad
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
      game.prevActions.push prev = new Event
        id: utils.generateId()
        type: actionType
        kind: kind
        actorId: actor.id
        gameId: game.id
        effects: JSON.stringify cleanValues _.pluck effects, 1
        
      # and next state, computed from current models
      newValues = (
        for effect in effects
          newEffect = {}
          # get values directly from modified model
          newEffect[attr] = effect[0][attr] for attr of effect[1]
          newEffect
      )
      
      game.nextActions.push next = new Event
        id: utils.generateId()
        type: actionType
        kind: kind
        actorId: actor.id
        gameId: game.id
        effects: JSON.stringify cleanValues newValues
        
      rule.saved.push prev, next, game
      callback null
}