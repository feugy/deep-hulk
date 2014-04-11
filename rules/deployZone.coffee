Rule = require 'hyperion/model/Rule'
{getDeployZone} = require './common'

# Returns hint on tiles tha belongs to the current deploy zone
class DeployZoneRule extends Rule

  # Apply on alien squads that has a deploy zone
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (zone), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    return callback null, null unless squad?.type?.id is 'squad' and squad?.isAlien and squad?.deployZone?
    callback null, [
      # deployement zone
      name:'zone'
      type:'string'
      within: squad.deployZone.split ','
    ]

  # Returns tile of the chosen deployable zone, without checks on visibility, nor field existence
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, params, context, callback) =>
    # get deployable zone dimensions in configuration
    getDeployZone squad.mission?.id or squad.mission, params.zone, (err, zone) =>
      return callback err if err?
      # returns tiles, but do not check visibility
      tiles = []
      tiles.push x:x, y:y for y in [zone.lowY..zone.upY] for x in [zone.lowX..zone.upX] 
      callback null, tiles
  
module.exports = new DeployZoneRule 'hints'