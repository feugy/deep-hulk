Rule = require 'hyperion/model/Rule'
{useTwist, moveCapacities} = require './common'

# "GeneralAssault" twist rule: all dreadnoughts and androids can move twice
class GeneralAssaultRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (game, squad, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad.isAlien and squad.waitTwist and squad.twist is 'generalAssault'
      return callback null, null 
    callback null, []

  # Reset to 0 available moves and attacks for aliens of a given kind revealed or not.
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
    console.log "applied twist #{twist}"
    
    # adouble moves for androids anddreadnoughts, even not visible
    for member in squad.members when member.kind in ['dreadnought', 'android'] and not member.dead
      member.moves *= 2
      console.log "#{member.kind} (#{squad.name}) affected by #{twist}"
    
    useTwist twist, game, squad, [], @, callback
  
module.exports = new GeneralAssaultRule 'twists'