_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'

# When alien finished to deploy a given zone
class EndDeployRule extends Rule

  # May apply only for alien that has a possible deployement.
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    return callback null, null unless squad?.type?.id is 'squad' and squad?.isAlien and squad?.deployZone?
    callback null, [
      name:'zone'
      type:'string'
      within: squad.deployZone.split ','
    ]

  # Check other squad's remaining action. 
  # If possible, trigger next turn.
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array of parameters: notably the concerned zone.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, params, context, callback) =>
    # TODO last remaining zone: do not end if alien has remaining blips
    console.log "alien has finished to deploy into zone '#{params.zone}'"
    # removes existing deployable items for this zone
    Item.where('map', squad.map.id).where('type', 'deployable').where('zone', params.zone).exec (err, deployables) =>
      return callback err if err?
      @removed = @removed.concat deployables
      
      # unblock concerned squads: marines
      squad.game.fetch (err, game) =>
        return callback err if err?
        # and the marines squad that may be waiting for deployment
        for other in game.squads when other isnt squad and other.deployZone is params.zone
          other.deployZone = null
          @saved.push other
      
        # and at last the alien squad
        squad.deployZone = squad.deployZone.replace(params.zone, '')
        squad.deployZone = null if squad.deployZone.trim().length is 0
        callback null
  
module.exports = new EndDeployRule 'blips'