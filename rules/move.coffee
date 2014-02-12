_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
Field = require 'hyperion/model/Field'
{distance, selectItemWithin, removeFromMap, addAction} = require './common'
{isReachable, detectBlips, moveBlip, findNextDoor} = require './visibility'

# Map movement
# Allows to move on the next tile
class MoveRule extends Rule

  # Move allowed next tiles containing a Field while actor has remaining moves.
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
    # check simple conditions before selecting items
    unless target.mapId? and not actor.dead and actor.moves >= 1 and 1 is distance actor, target
      return callback null, null 
    # now check wall rules: get all items at actor and target coordinates
    selectItemWithin actor.map.id, actor, target, (err, items) =>
      return callback err, null if err?
      callback null, if isReachable actor, target, items then [] else null

  # Move marine to the next tile.
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  execute: (actor, target, params, context, callback) =>
    # game action current state 
    effects = [[actor, _.pick actor, 'id', 'moves', 'x', 'y', 'transition', 'doorToOpen']]
      
    # evaluate move direction
    if target.y is actor.y
      direction = if target.x < actor.x then '-l' else '-r'
    else 
      direction = if target.y < actor.y then '-b' else '-t'
    actor.transition = "move#{direction}"
    
    # checks that a field exists where actor wants to move, or quit
    Field.where('mapId', actor.map.id).where('x', actor.x).where('y', actor.y).exec (err, [previous]) =>
      return callback err if err?
      
      base = "base-#{actor.squad.name}"
      # consume a move unless in your base
      actor.moves -= 1 unless target.typeId is base
      if actor.moves is 0
        actor.squad.actions--
        
      console.log "#{actor.name or actor.kind} (#{actor.squad.name}) moves from #{actor.x}:#{actor.y} to #{target.x}:#{target.y} (remains #{actor.moves})"
      # update actor coordinates
      actor.x = target.x
      actor.y = target.y
      
      # return safe to base !
      if previous.typeId isnt base and target.typeId is base
        effects[0][1].dead = false
        return removeFromMap actor, @, =>
          addAction 'move', actor, effects, @, callback
      
      # check if actor can now open a door
      selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+1, y:actor.y+1}, (err, items) =>
        return callback err if err?
        actor.doorToOpen = findNextDoor actor, items
        
        processReveal = =>
          # do not reveal blip if we are in your base
          return callback null unless target.typeId isnt "base-#{actor.squad.name}"
          detectBlips actor, @, effects, (err, revealed) =>
            return callback err if err?
            addAction 'move', actor, effects, @, callback
        
        # if marine, check if enter a deployable zone
        if actor.type.id is 'marine'
          deployable = _.find items, (item) -> item.x is actor.x and item.y is actor.y and item.type.id is 'deployable'
          if deployable?
            # inhibit actor actions
            actor.squad.deployZone = deployable.zone
            # ask alien player to deploy this zone
            return Item.where('type', 'squad').where('map', actor.map.id).where('isAlien', true).exec (err, [alien]) =>
              return callback err if err?
              return callback new Error "no alien squad found" unless alien?
              unless alien.deployZone?
                alien.deployZone = deployable.zone
              else if -1 is alien.deployZone.indexOf deployable.zone
                alien.deployZone += ",#{deployable.zone}"
              @saved.push alien
              # at last reveal new aliens
              processReveal()
            
        # at last reveal new aliens
        processReveal()
  
module.exports = new MoveRule()