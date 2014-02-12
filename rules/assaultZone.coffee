Rule = require 'hyperion/model/Rule'
Field = require 'hyperion/model/Field'
{selectItemWithin} = require './common'
{isTargetable} = require './visibility'

# The AssaultZone rule highlight damage zone in close combat
class AssaultZoneRule extends Rule

  # Do not compute unless character has remaining shoot and ranged weapon
  # Only applicable on visible fields
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
    # deny if actor cannot attack anymore. 
    return callback null, if actor.ccNum >= 1 and actor.weapon.cc? then [] else null
      
  # Returns tiles that are involved in the shoot, depending on the character weapon
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (actor, target, params, context, callback) =>
    # select all nearest objects (to get walls)
    selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+1, y:actor.y+1}, (err, items) =>
      return callback err if err?
      # select all nearest fields in the range
      Field.where('mapId', actor.map.id).where('x').gte(actor.x-1).where('x').lte(actor.x+1)
          .where('y').gte(actor.y-1).where('y').lte(actor.y+1).exec (err, fields) ->
        return callback err if err?
        # return only reachables that are on the same axis (no diagonals)
        callback null, tiles:(x:tile.x, y:tile.y for tile in fields when isTargetable(actor, tile, items) and (tile.x is actor.x or tile.y is actor.y))
  
module.exports = new AssaultZoneRule 'hints'