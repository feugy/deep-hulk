Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{useTwist} = require './common'

# "OperationReport" twist rule: a given marine sergent cannot move or attack this turn.
class OperationsReportRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'operationsReport'
      return callback null, null 
    # choose a victim within marine squads
    callback null, [
      name: 'squad'
      type: 'string'
      within: (other.name for other in game.squads when not other.isAlien)
    ]

  # Reset to 0 available moves and attacks for alive sergent
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    # fetch target squad to access sergent
    for target in game.squads when target.name is params.squad
      target.fetch (err, target) =>
        return callback err if err?
        
        twist = squad.twist
        console.log "applied twist #{twist} on #{target.name}"
        
        # select sergent, and block him
        for marine in target.members when marine.isCommander and not marine.dead
          marine.moves = 0
          marine.rcNum = 0
          marine.ccNum = 0
          console.log "#{marine.name} (#{target.name}) affected by #{twist}"
          
        useTwist twist, game, target, [], @, callback
  
module.exports = new OperationsReportRule 'twists'