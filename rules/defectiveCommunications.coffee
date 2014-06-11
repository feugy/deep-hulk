Rule = require 'hyperion/model/Rule'
{useTwist} = require './common'

# "DefectiveCommunications" twist rule: a given squad cannot use its order this turn.
class DefectiveCommunicationsRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'defectiveCommunications'
      return callback null, null 
    # choose a victim within marine squads
    callback null, [
      name: 'squad'
      type: 'string'
      within: (other.name for other in game.squads when not other.isAlien)
    ]

  # Set twist to target to block its order usability
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    for target in game.squads when target.name is params.squad
      twist = squad.twist
      console.log "applied twist #{twist} on #{target.name}"
        
      # set twist to squad, to block orders
      target.twist = twist
      return useTwist twist, game, target, [], @, callback
  
module.exports = new DefectiveCommunicationsRule 'twists'