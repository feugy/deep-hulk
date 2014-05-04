_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
Field = require 'hyperion/model/Field'
{moveCapacities} = require './constants'
{distance, selectItemWithin, removeFromMap, addAction} = require './common'
{isReachable, detectBlips, findNextDoor, isDreadnoughtUnderDoor} = require './visibility'

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
    # inhibit if waiting for deployment or other squad
    if actor.squad?.deployZone? or actor.squad?.activeSquad? and actor.squad.activeSquad isnt actor.squad.name
      return callback null, null 
    # simple conditions, target is field, actor not dead or reinforcing, target at 1~2 distance
    unless target.mapId? and not actor.dead and actor.moves >= 1 and 2 >= distance actor, target
      return callback null, null
    # for dreadnaught, select enought tiles to check that no part share tile with other aliens
    coord = x: target.x, y: target.y
    if actor.kind is 'dreadnought' and actor.revealed
      coord.y++ if coord.y is actor.y
      coord.x++ if coord.x is actor.x
    # now check wall rules: get all items at actor and target coordinates
    selectItemWithin actor.map.id, actor, coord, (err, items) =>
      return callback err, null if err?
      # isReachable will check distance and obstacle conditions
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
    effects = [[actor, _.pick actor, 'id', 'moves', 'x', 'y', 'transition', 'doorToOpen', 'underDoor']]
      
    targetType = target.typeId
    x = target.x
    y = target.y
    isDreadnought = actor.kind is 'dreadnought' and actor.revealed
    
    if isDreadnought
      # only move of one horizontally or vertically
      if x is actor.x+2 or x is actor.x-1
        # moving horizontally
        y = actor.y
        x-- if x is actor.x+2
      else
        # moving vertially
        x = actor.x
        y-- if y is actor.y+2
    
    # evaluate move direction
    if y is actor.y
      direction = if x < actor.x then '-l' else '-r'
    else 
      direction = if y < actor.y then '-b' else '-t'
    actor.transition = "move#{direction}"
    
    # checks that a field exists where actor wants to move, or quit
    Field.where('mapId', actor.map.id).where('x', actor.x).where('y', actor.y).exec (err, [previous]) =>
      return callback err if err?
      
      base = "base-#{actor.squad.name}"
      # consume a move unless in your base
      unless targetType is base
        actor.moves -= 1 
        actor.squad.firstAction = false
      if actor.moves is 0
        actor.squad.actions--
        
      # if consumming more than 1 allowed moves and having by section order, then reduce range attacks
      allowed = moveCapacities[actor.weapons[0].id]
      if actor.moves < allowed and actor.equipment and 'bySections' in actor.equipment
        actor.rcNum--
        actor.equipment.splice actor.equipment.indexOf('bySections'), 1
        
      # update actor coordinates
      console.log "#{actor.name or actor.kind} (#{actor.squad.name}) moves from #{actor.x}:#{actor.y} to #{x}:#{y} (remains #{actor.moves})"
      actor.x = x
      actor.y = y
      
      if isDreadnought
        # updates also dreadnought parts
        for i in [0..2]
          actor.parts[i].x = actor.x+(if i is 0 then 1 else i-1)
          actor.parts[i].y = actor.y+(if i is 0 then 0 else 1)
  
      # return safe to base !
      if previous.typeId isnt base and targetType is base
        effects[0][1].dead = false
        return removeFromMap actor, @, (err) =>
          return callback err if err?
          addAction 'move', actor, effects, @, callback
      
      # check if actor can now open a door
      # dreadnought may open door at x+2 and y+2
      range = if isDreadnought then 2 else 1
      selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+range, y:actor.y+range}, (err, items) =>
        return callback err if err?
        
        # keep info if under door or not
        actor.underDoor = isDreadnoughtUnderDoor items, actor if isDreadnought
        
        # search for next door
        actor.doorToOpen = findNextDoor (if isDreadnought then actor.parts.concat [actor] else actor), items
        
        processReveal = =>
          # do not reveal blip if we are in your base
          return callback null unless targetType isnt "base-#{actor.squad.name}"
          detectBlips actor, @, effects, (err, revealed) =>
            return callback err if err?
            return callback() if targetType is base
            addAction 'move', actor, effects, @, callback
            
        # at last reveal new aliens
        processReveal()
  
module.exports = new MoveRule()