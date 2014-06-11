Rule = require 'hyperion/model/Rule'
ClientConf = require 'hyperion/model/ClientConf'
{useTwist} = require './common'
{moveCapacities} = require './constants'

# "DefectiveEquipment" twist rule: randomly pick an equipment to a given squad.
class DefectiveEquipmentRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'defectiveEquipment'
      return callback null, null 
    # choose a victim within marine squads
    callback null, [
      name: 'squad'
      type: 'string'
      within: (other.name for other in game.squads when not other.isAlien)
    ]

  # Randomly pick an equipment to this target squad, and removes it.
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    # get labels
    ClientConf.findCached ['default'], (err, [conf]) =>
      return callback err if err?
      
      for target in game.squads when target.name is params.squad
        twist = squad.twist
        console.log "applied twist #{twist} on #{target.name}"
        
        # fetch squad to access marines
        target.fetch (err, target) =>
          return callback err if err?
          
          # equipment is dispatched into marines and squd
          equipment = (marine: target, name: piece for piece in target.equipment)
          for member in target.members
            equipment.push marine: member, name: piece for piece in member.equipment
             
          # randomly pick one
          removed = equipment[Math.floor Math.random()*target.equipment.length]
          switch removed.name
            when 'suspensors', 'pistolBolters', 'assaultBlades'
              # those equipments are applied on several marines
              for member in target.members when removed.name in member.equipment
                member.equipment.splice member.equipment.indexOf(removed.name), 1
                if removed.name is 'suspensors'
                  # cancel suspensor effects
                  weapon = member.weapons[0]?.id or member.weapons[0]
                  member.moves = moveCapacities[weapon]
            else
              # just remove from concerned marine 
              removed.marine.equipment.splice removed.marine.equipment.indexOf(removed.name), 1
              # cancel equipment permanent effect
              switch removed.name 
                when 'forceField' then removed.marine.armor = 2
                when 'combinedWeapon' then removed.marine.weapons.splice removed.marine.weapons.indexOf('flamer'), 1
                when 'detector' then target.revealBlips = 0
  
          # send event concerning target squad, plus removed equipment name
          return useTwist twist, game, target, [], @, true, {equip: conf.values.labels[removed.name]}, callback
  
module.exports = new DefectiveEquipmentRule 'twists'