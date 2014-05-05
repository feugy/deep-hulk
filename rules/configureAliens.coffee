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
    if player?._className is 'Player' and squad?.type?.id is 'squad' and !(squad?.map?)
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
    for member in squad.members when member.kind is 'dreadnought'
      configured = (weapon for id, weapon of params when id.match member.id)
      if configured[0] is configured[1]
        return callback new Error "twoMany"+configured[0][0].toUpperCase()+configured[0][1..]
    
    # update members weapons
    Item.fetch squad.members, (err, members) =>
      return callback err if err?
      # remove previous weapons
      member.weapons.splice 1
      # for each dreadnought, affect choosed weapons
      for member in members when member.kind is 'dreadnought'
        for i in [0...member.life-1]
          weaponId = params["#{member.id}-weapon-#{i}"]
          member.weapons.push weaponId
          
      # ready for deploy
      squad.configured = true
      callback null
  
module.exports = new ConfigureAliensRule 'init'