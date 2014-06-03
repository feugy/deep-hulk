_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{heavyWeapons, marineWeapons, commanderWeapons, weapons, weaponImages, moveCapacities} = require './constants'
  
# Aliens configuration: set weapons on dreadnoughts
class ConfigureAliensRule extends Rule

  # Player can configure their squad while not deployed.
  # Weapon must be provided as squad member parameter
  # 
  # @param player [Item] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameters: one per squad members for its weapon.
  canExecute: (player, squad, context, callback) =>
    if player?._className is 'Player' and squad?.type?.id is 'squad' and not squad?.map?
      # check that squad belongs to player
      return callback null, null unless _.findWhere player.characters, id:squad.id
      params = []
      for member in squad.members when member.kind is 'dreadnought'
        # adds a parameter per weapon per dreadnought
        for i in [0...member.life-1]
          params.push
            name: "#{member.id}-weapon-#{i}"
            type: "string"
            within: heavyWeapons
      callback null, params
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
    # check that all weapons are use only once on a fiven dreadnought
    for member in squad.members when member.kind is 'dreadnought'
      configured = (weapon for id, weapon of params when id.match member.id)
      for weapon in configured when _.filter(configured, (w) -> w is weapon).length > 1
        return callback new Error "twoMany"+weapon[0].toUpperCase()+weapon[1..]
    
    # update members weapons
    Item.fetch squad.members, (err, members) =>
      return callback err if err?
      # for each dreadnought, affect choosed weapons
      for dreadnought in members when dreadnought.kind is 'dreadnought'
        # remove previous weapons
        dreadnought.weapons.splice 1
        for i in [0...dreadnought.life-1]
          weaponId = params["#{dreadnought.id}-weapon-#{i}"]
          dreadnought.weapons.push weaponId
      # ready for deploy
      squad.configured = true
      callback null
  
module.exports = new ConfigureAliensRule 'init'