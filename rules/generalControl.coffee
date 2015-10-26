_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{useTwist, makeState, getNextDoor, selectItemWithin} = require './common'
{findNextDoor} = require './visibility'

# "GeneralControl" twist rule: invert selected doors
class GeneralControlRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (game, squad, context, callback) =>
    unless squad.isAlien and squad.waitTwist and squad.twist is 'generalControl'
      return callback null, null 
  
    # select doors from map, either closed or opened, but do not allows to opened undeployed zones
    Item.where('map', squad.map.id).where('type', 'door').where('closed', false).exec (err, doors) =>
      return callback err if err?
      # removes next door
      candidates = []
      for door in doors when not(door.zone1? or door.zone2?)
        next = getNextDoor door
        candidates.push door unless _.findWhere(candidates, next)?
        
      callback null, [
        name: 'target'
        type: 'object'
        numMin: 0
        numMax: candidates.length
        within: candidates
      ]

  # Opens closed door and close opened ones.
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    twist = squad.twist
    # no target found
    unless params.target?
      return useTwist twist, game, squad, [], @, callback
      
    effects = []
    # select all wall, doors, marines and alien within map to check visibility and doors to open
    selectItemWithin squad.map.id, (err, items) =>
      return callback err if err?
      
      for doorId in params.target
        door = _.findWhere items, id: doorId
        
        # get next door
        next = getNextDoor door
        console.log "applied twist #{twist} to close door at #{door.x}:#{door.y}"
        
        nextDoor = _.findWhere items, x:next.x, y:next.y, type: door.type
         
        # close them
        for part in [door, nextDoor]
          effects.push makeState part, 'closed', 'imageNum'
          part.closed = true
          part.imageNum += 2
          @saved.push part
            
      # update doorToOpen for all marines/aliens
      for actor in items when actor.type.id in ['marine', 'alien']
        positions = [actor]
        if actor.kind is 'dreadnought' and actor.revealed
          # for dreadnought, check all parts, but no need to resolve tham, we can do the computation
          for i in [0..2]
            positions.push 
              x: actor.x+(if i is 0 then 1 else i-1)
              y: actor.y+(if i is 0 then 0 else 1)
        newDoorToOpen = findNextDoor positions, items
        if newDoorToOpen isnt actor.doorToOpen
          effects.push makeState actor, 'doorToOpen'
          actor.doorToOpen = newDoorToOpen
          @saved.push actor
      
      useTwist twist, game, squad, effects, @, callback
  
module.exports = new GeneralControlRule 'twists'