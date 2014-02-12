_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{heavyWeapons, marineWeapons, commanderWeapons, weapons, weaponImages, moveCapacities} = require './constants'
  
# Squad configuration: set weapons and equipment
class ConfigureSquadRule extends Rule

  # Player can configure their squad while not deployed.
  # Weapon must be provided as squad member parameter
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameters: one per squad members for its weapon.
  canExecute: (actor, target, context, callback) =>
    if actor?._className is 'Player' and target?.type?.id is 'squad' and !(target?.map?)
      # check that target belongs to player
      for squad in actor.characters when squad.id is target.id
        return target.fetch (err, target) =>
          return callback err if err?
          callback null, (
            for member in target.members
              name: "#{member.id}-weapon"
              type: "string"
              within: if member.isCommander then commanderWeapons else marineWeapons
          )
      callback null, null
    else 
      callback null, null

  # Squad configuration modifies weapons in accordance to following rules:
  # - at least one bolter
  # - at least one heavy weapon
  # - at most one heavy weapon of a kind
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array of parameters: one per squad member.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  execute: (player, squad, params, context, callback) =>
    configured = (weapon for id, weapon of params when id.match /-weapon$/)
    
    # checks at least one bolder
    return callback new Error "bolterRequired" unless 'bolter' in configured
    # checks at least one heavy weapon
    return callback new Error "heavyWeaponRequired" if 0 is _.intersection(configured, heavyWeapons).length
    # checks at most one heavy weapon of a kind
    groups = _.groupBy configured
    return callback new Error "twoManyMissleLauncher" if groups.missileLauncher?.length > 1
    return callback new Error "twoManyFlamer" if groups.flamer?.length > 1
    return callback new Error "twoManyAutoCannon" if groups.autoCannon?.length > 1

    # update members weapons
    squad.fetch (err, squad) =>
      return callback err if err?
      Item.fetch squad.members, (err, members) =>
        return callback err if err?
        for member in members
          # reuse always the same weapon by their ids
          member.weapon = params["#{member.id}-weapon"]
          member.imageNum = weaponImages[squad.name][member.weapon]
          member.points = if id in heavyWeapons or id in commanderWeapons then 10 else 5
          # adapt marine possible moves
          member.moves = moveCapacities[member.weapon]
        # init first actions number
        squad.actions = squad.members.length * 2
        callback null
  
module.exports = new ConfigureSquadRule 'init'