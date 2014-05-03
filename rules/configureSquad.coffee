_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{heavyWeapons, marineWeapons, commanderWeapons, weapons, weaponImages, moveCapacities, equipments, orders} = require './constants'
  
# Squad configuration: set weapons and equipment
class ConfigureSquadRule extends Rule

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
      params = (
        for member in squad.members
          name: "#{member.id}-weapon"
          type: "string"
          within: if member.isCommander then commanderWeapons else marineWeapons
      )
      # adds equipment and orders to be choosed
      params.push {
        name: 'equipments'
        type: 'string'
        numMin: 4
        numMax: 4
        within: equipments[squad.name]
      }, {
        name: 'targeter'
        type: 'object'
        numMin: 0
        numMax: 2
        within: squad.members
      }, {
        name: 'orders'
        type: 'string'
        numMin: 1
        numMax: 1
        within: orders[squad.name]
      }
      callback null, params
    else 
      callback null, null

  # Squad configuration modifies weapons in accordance to following rules:
  # - at least one bolter
  # - at least one heavy weapon
  # - at most one heavy weapon of a kind
  #
  # Also store choosen equipement, and applies some of them
  # (forceField, suspensors, combinedWeapon, detector) 
  #
  # Stores choosen orders
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
    return callback new Error "twoManyMissileLauncher" if groups.missileLauncher?.length > 1
    return callback new Error "twoManyFlamer" if groups.flamer?.length > 1
    return callback new Error "twoManyAutoCannon" if groups.autoCannon?.length > 1

    # update members weapons
    Item.fetch squad.members, (err, members) =>
      return callback err if err?
      for member in members
        weaponId = params["#{member.id}-weapon"]
        # reuse always the same weapon by their ids
        member.weapons = [weaponId]
        member.imageNum = weaponImages[squad.name][weaponId]
        member.points = if weaponId in heavyWeapons or weaponId in commanderWeapons then 10 else 5
        # adapt marine possible moves
        member.moves = moveCapacities[weaponId]
        member.equipment = []
      
      # init first actions number
      squad.actions = squad.members.length * 2
      squad.equipment = []
      squad.revealBlips = 0
      squad.orders = if _.isArray params.orders then params.orders else [params.orders]
      
      # apply equipment if needed
      commander = _.findWhere members, isCommander:true
      for equip,i in params.equipments or []
        switch equip
          # commander equipment
          when 'forceField', 'digitalWeapons', 'bionicEye', 'bionicArm'
            commander.equipment.push equip
            commander.armor = 3 if equip is 'forceField'
          # marines equipment
          when 'suspensors'
            for member in members when member.weapons[0] in heavyWeapons
              member.equipment.push equip 
              member.moves = moveCapacities.bolter
          when 'pistolBolters', 'assaultBlades'
            for member in members when member.weapons[0] is 'bolter'
              member.equipment.push equip
          when 'combinedWeapon'
            return callback new Error 'cantCombinedWeapon' unless 'heavyBolter' in commander.weapons
            commander.weapons.push 'flamer'
            commander.equipment.push equip
          when 'targeter'
            err = new Error 'missingTargeter'
            for member in members when member.id in params.targeter and not ('targeter' in member.equipment)
              if member.isCommander
                err = new Error 'targeterMustBeMarine'
              else
                member.equipment.push equip 
                err = null
                # applied only once !
                break
            return callback err if err?
          when 'detector'
            # detector allows to reveal 3 blips
            squad.revealBlips = 3
            squad.equipment.push equip
          # squad equipment: mediKit, meltaBomb, bondingGrenade
          else
            squad.equipment.push equip
      
      # ready for deploy
      squad.configured = true  
      callback null
  
module.exports = new ConfigureSquadRule 'init'