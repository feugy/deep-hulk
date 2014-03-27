_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{isTargetable} = require './visibility'

# Rule to choose targets for weapon that supports it
class TargetRule extends Rule

  # Target addition allowed only on visible field targets and for character equiped with autoCannon
  # Only fields can be targeted
  # 
  # @param actor [Item] the concerned actor
  # @param target [Field] the concerned field
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
    # deny if actor cannot attack anymore, or if target isnt a field
    return callback null, null unless not actor.dead and actor.rcNum >= 1 and target?.mapId?
    # deny unless if wearing auto cannon
    idx = actor.weapons.indexOf _.findWhere(actor.weapons, id: 'autoCannon')
    return callback null, null if idx is -1
    # now check visibility rules: get all items at actor and target coordinates
    isTargetable actor, target, idx, (err, reachable) =>
      callback err, if reachable? then [] else null

  # Append target coordinates to actor current targets
  #
  # @param actor [Item] the concerned actor
  # @param target [Field] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  execute: (actor, target, params, context, callback) =>
    # add the target to list of current targets, unless already present
    added = "#{target.x}:#{target.y}"
    if actor.currentTargets? and -1 isnt actor.currentTargets.indexOf added
      return callback null
      
    if actor.currentTargets?
      actor.currentTargets += ','
    else
      actor.currentTargets = ''
    actor.currentTargets += added
    callback null
  
module.exports = new TargetRule 'shoot'