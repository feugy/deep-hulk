Rule = require 'hyperion/model/Rule'
Field = require 'hyperion/model/Field'
{selectItemWithin} = require './common'
{isReachable} = require './visibility'

# Map possible movement: returns tiles that a character can reach
class MovableRule extends Rule

  # Do not compute unless character has remaining moves
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
    return callback null, if actor.moves >= 1 then [] else null
    
  # Returns reachable tiles.
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target: ignored
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback tiles [Array] an array of reachable coordinates
  execute: (actor, target, params, context, callback) =>
    # select all nearest tiles
    selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+1, y:actor.y+1}, (err, items) =>
      return callback err if err?
      # select all nearest fields
      Field.where('mapId', actor.map.id).where('x').gte(actor.x-1).where('x').lte(actor.x+1)
          .where('y').gte(actor.y-1).where('y').lte(actor.y+1).exec (err, fields) ->
        return callback err if err?
        # return reachable tiles coordinates
        callback null, (x:tile.x, y:tile.y for tile in fields when isReachable actor, tile, items)
  
module.exports = new MovableRule 'hints'