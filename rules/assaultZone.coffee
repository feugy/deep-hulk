_ = require 'underscore'
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
    # always use first weapon for close combat
    return callback null, if actor.ccNum >= 1 and actor.weapons[0]?.cc? then [] else null
      
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
    # dreadnoughts can move up to x+2 and y+2
    range = if actor.kind is 'dreadnought' and actor.revealed then 2 else 1
    # select all nearest objects (to get walls)
    selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+range, y:actor.y+range}, (err, items) =>
      return callback err if err?
      # select all nearest fields in the range
      Field.where('mapId', actor.map.id).where('x').gte(actor.x-1).where('x').lte(actor.x+range)
          .where('y').gte(actor.y-1).where('y').lte(actor.y+range).exec (err, fields) =>
        return callback err if err?
        # deny attacker if actor is in base
        return callback null, null if _.findWhere(fields, x:actor.x, y:actor.y).typeId[0..4] is 'base-'
      
        # if actor is dreadnought, all part must be testes
        isDreadnought = actor.kind is 'dreadnought' and actor.revealed
        candidates = [actor]
        candidates = candidates.concat actor.parts if isDreadnought
        tiles = []
        # checks one possible candidate on the same line to exclude diagonals
        for tile in fields when isTargetable(actor, tile, 0, items)?
          tiles.push tile if _.find(candidates, (candidate) -> tile.x is candidate.x or tile.y is candidate.y)?
        callback null, tiles:tiles
  
module.exports = new AssaultZoneRule 'hints'